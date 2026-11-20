import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:med_ai/models.dart';
import 'package:med_ai/services/api.dart';
import 'package:med_ai/screens/report_chat.dart';

void main() {
  testWidgets('consent precedes sending and selected report and language reach API', (tester) async {
    int sends = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET') return http.Response(jsonEncode({'configured':true, 'turns':[]}), 200);
      sends++;
      final body = jsonDecode(request.body);
      expect(body['consent'], isTrue);
      expect(body['document_ids'], ['report-123']);
      expect(body['language'], 'auto');
      return http.Response(jsonEncode({'request_id':body['request_id'], 'question':body['question'],
        'answer':'Example explanation', 'sources':[]}), 200);
    });
    final state = AppState(api: Api(client: client));
    await tester.pumpWidget(Scope(state: state, child: const MaterialApp(home: ReportChat(documentId:'report-123'))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Explain CBC');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(sends, 0);
    await tester.tap(find.text('Allow and send'));
    await tester.pumpAndSettle();
    expect(sends, 1);
    expect(find.text('Example explanation'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose(); client.close();
  });

  for (final size in [const Size(320,568), const Size(390,844)]) {
    testWidgets('messages scroll without moving composer at $size and keyboard resizes', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final client = MockClient((_) async => http.Response(jsonEncode({'configured':true,
        'turns':List.generate(30, (i) => {'request_id':'turn-$i','question':'Question $i',
          'answer':List.filled(15, 'Report explanation $i.').join(' '),'sources':[]})}),200));
      final state = AppState(api:Api(client:client));
      await tester.pumpWidget(Scope(state:state, child:const MaterialApp(home:ReportChat())));
      await tester.pumpAndSettle();
      final composer = find.byKey(const ValueKey('chat-composer'));
      final messages = find.byKey(const ValueKey('chat-messages'));
      final before = tester.getTopLeft(composer);
      final list = tester.widget<ListView>(messages);
      final originalOffset = list.controller!.offset;
      await tester.drag(messages, const Offset(0, 250));
      await tester.pumpAndSettle();
      expect(list.controller!.offset, greaterThan(originalOffset));
      expect(tester.getTopLeft(composer), before);
      tester.view.viewInsets = const FakeViewPadding(bottom:180);
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(composer).dy, lessThanOrEqualTo(size.height-180));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose(); client.close();
    });
  }
}
