import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:med_ai/models.dart';
import 'package:med_ai/screens/extraction_live.dart';
import 'package:med_ai/services/api.dart';
import 'package:med_ai/services/vault.dart';

class UploadVault extends Vault {
  Map<String, dynamic>? saved;
  @override
  Future<void> write(String user, Map<String, dynamic> data) async { saved=data; }
}

AppState seeded(Api api, {bool conflict=false}) {
 final s=AppState(api:api,vault:UploadVault());
 s.userId='a'*32;api.token='test-token';s.conflict=conflict;
 s.uploads.add({'id':'selected-image','client_id':'selected-client','bytes':base64Encode([1,2,3]),'kind':'Prescription','language':'eng+ben'});
 s.documents.add({'id':'selected-image','kind':'Prescription','uploaded':false});
 return s;
}

void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 test('selected image uploads despite record conflict and unrelated queued image',() async {
  var uploads=0;
  final api=Api(client:MockClient((r) async {
   expect(r.method,'POST');expect(r.url.path,'/api/documents');
   expect(r.headers['Authorization'],'Bearer test-token');
   expect(r.body,contains('selected-client'));expect(r.body,isNot(contains('broken-client')));
   uploads++;
   return http.Response(jsonEncode({'id':'selected-image','kind':'Prescription'}),201);
  }));
  final s=seeded(api,conflict:true);
  s.pendingEvent='local-edit';
  s.uploads.insert(0,{'id':'broken','client_id':'broken-client','bytes':'AA==','kind':'Prescription','language':'eng'});
  await s.ensureDocumentUploaded('selected-image');
  expect(uploads,1);expect(s.documents.single['uploaded'],true);
  expect(s.uploads.single['id'],'broken');expect(s.conflict,true);expect(s.pendingEvent,'local-edit');
  await s.ensureDocumentUploaded('selected-image');expect(uploads,1);
  s.dispose();
 });
 test('document queued during in-flight state sync is uploaded after that sync',() async {
  final stateStarted=Completer<void>(),stateReply=Completer<http.Response>();
  String? selected;var uploads=0;
  final api=Api(client:MockClient((r) async {
   if(r.url.path=='/api/state') {if(!stateStarted.isCompleted)stateStarted.complete();return stateReply.future;}
   if(r.url.path=='/api/documents' && r.method=='GET')return http.Response('[]',200);
   if(r.url.path=='/api/documents' && r.method=='POST') {uploads++;return http.Response(jsonEncode({'id':selected,'kind':'Prescription'}),201);}
   return http.Response('{}',200);
  }));
  final s=AppState(api:api,vault:UploadVault());s.userId='a'*32;api.token='token';
  final first=s.sync();await stateStarted.future;
  selected=await s.queueDocument(Uint8List.fromList([1,2,3]),kind:'Prescription',language:'eng+ben');
  final ready=s.ensureDocumentUploaded(selected!);
  stateReply.complete(http.Response('{"state":{},"version":0}',200));
  await first;await ready;
  expect(uploads,1);expect(s.documents.single['uploaded'],true);expect(s.uploads,isEmpty);
  s.dispose();
 });
 test('failed upload keeps image queued and can retry',() async {
  var count=0;
  final api=Api(client:MockClient((_) async {
   count++;
   if(count==1)throw Exception('simulated network failure');
   return http.Response('{"id":"selected-image","kind":"Prescription"}',201);
  }));
  final s=seeded(api);
  await expectLater(s.ensureDocumentUploaded('selected-image'),throwsA(isA<ApiError>().having((e)=>e.message,'message',contains('queued photo is kept'))));
  expect(s.uploads.length,1);expect(s.documents.single['uploaded'],false);expect(s.syncing,false);
  await s.ensureDocumentUploaded('selected-image');expect(s.uploads,isEmpty);expect(s.documents.single['uploaded'],true);
  s.dispose();
 });
 test('an upload reply cannot enter another account after account switch',() async {
  final started=Completer<void>(),reply=Completer<http.Response>();
  final api=Api(client:MockClient((_) {started.complete();return reply.future;}));
  final s=seeded(api);
  final upload=s.ensureDocumentUploaded('selected-image');
  final checked=expectLater(upload,throwsA(isA<ApiError>().having((e)=>e.message,'message',contains('account changed'))));
  await started.future;
  s.userId=null;api.token=null;s.documents.clear();s.uploads.clear();
  reply.complete(http.Response('{"id":"selected-image"}',201));await checked;
  expect(s.documents,isEmpty);expect(s.uploads,isEmpty);s.dispose();
 });
 for (final status in [401,413,415,409]) {
  test('upload failure $status retains bytes',() async {
   final s=seeded(Api(client:MockClient((_) async=>http.Response('{}',status))));
   await expectLater(s.ensureDocumentUploaded('selected-image'),throwsA(isA<ApiError>().having((e)=>e.status,'status',status)));
   expect(s.uploads.single['bytes'],base64Encode([1,2,3]));
   expect(s.documents.single['uploaded'],false);expect(s.needsSignIn,status==401);s.dispose();
  });
 }
 testWidgets('OCR starts only after selected image upload completes', (tester) async {
  final uploadReply=Completer<http.Response>();var extractionCalls=0;
  final api=Api(client:MockClient((r) async {
   if(r.method=='POST' && r.url.path=='/api/documents')return uploadReply.future;
   if(r.url.path.endsWith('/extract')) {
    extractionCalls++;return http.Response('{"status":"ready","candidates":[],"review_required":true}',200);
   }
   return http.Response('{}',200);
  }));
  final s=seeded(api,conflict:true);
  await tester.pumpWidget(MaterialApp(home:Scope(state:s,child:const ExtractionLive(documentId:'selected-image'))));
  await tester.pump();
  expect(extractionCalls,0);expect(find.text('Uploading prescription…'),findsOneWidget);
  uploadReply.complete(http.Response('{"id":"selected-image","kind":"Prescription"}',201));
  await tester.pumpAndSettle();expect(extractionCalls,1);expect(find.textContaining('Sync this image'),findsNothing);
  await tester.pumpWidget(const SizedBox());s.dispose();
 });
}
