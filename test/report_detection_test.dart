import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:med_ai/models.dart';
import 'package:med_ai/services/api.dart';
import 'package:med_ai/services/vault.dart';
import 'package:med_ai/screens/documents_live.dart';

class DetectionVault extends Vault {
  Map<String, dynamic>? saved;
  @override
  Future<void> write(String user, Map<String, dynamic> data) async {
    saved = data;
  }
}

const detected = <String, dynamic>{
  'id': 'photo',
  'kind': 'Lab Report',
  'ocr_text': 'Lipid Profile\nHDL 45',
  'report_type': 'lipid',
  'report_title': 'Cholesterol and fats',
  'report_detection_status': 'identified',
  'report_detection_version': 1,
  'report_metadata_revision': 1,
};

AppState signed(Api api) {
  final state = AppState(api: api, vault: DetectionVault());
  state.userId = 'a' * 32;
  api.token = 'synthetic-token';
  state.documents.add({'id': 'photo', 'kind': 'Lab Report', 'uploaded': true});
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'opening uploaded report automatically identifies and fills the type',
    (tester) async {
      final reply = Completer<http.Response>();
      var calls = 0;
      final api = Api(
        client: MockClient((request) async {
          expect(request.url.path, '/api/documents/photo/classify');
          expect(request.method, 'POST');
          calls++;
          return reply.future;
        }),
      );
      final state = signed(api);
      await tester.pumpWidget(
        Scope(
          state: state,
          child: MaterialApp(
            home: ReportReview(report: state.documents.single),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Identifying report type…'), findsOneWidget);
      expect(calls, 1);
      reply.complete(http.Response(jsonEncode(detected), 200));
      await tester.pumpAndSettle();
      expect(find.textContaining('Automatically identified'), findsOneWidget);
      expect(state.documents.single['report_type'], 'lipid');
      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      expect(dropdown.initialValue, 'lipid');
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'failed identification keeps image metadata and offers a working retry',
    (tester) async {
      var calls = 0;
      final api = Api(
        client: MockClient((_) async {
          calls++;
          if (calls == 1)
            return http.Response('{"detail":"Synthetic network failure"}', 503);
          return http.Response(jsonEncode(detected), 200);
        }),
      );
      final state = signed(api);
      await tester.pumpWidget(
        Scope(
          state: state,
          child: MaterialApp(
            home: ReportReview(report: state.documents.single),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(state.documents.single['id'], 'photo');
      await tester.ensureVisible(find.text('Retry identification'));
      await tester.tap(find.text('Retry identification'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(state.documents.single['report_type'], 'lipid');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  test(
    'deduplicates concurrent classification and rejects a stale account response',
    () async {
      final reply = Completer<http.Response>(), started = Completer<void>();
      var calls = 0;
      final api = Api(
        client: MockClient((_) {
          calls++;
          started.complete();
          return reply.future;
        }),
      );
      final state = signed(api);
      final first = state.classifyReport('photo');
      final second = state.classifyReport('photo');
      expect(identical(first, second), isTrue);
      final checked = expectLater(first, throwsA(isA<StateError>()));
      await started.future;
      state.userId = 'b' * 32;
      api.token = 'other-token';
      state.documents.clear();
      reply.complete(http.Response(jsonEncode(detected), 200));
      await checked;
      expect(calls, 1);
      expect(state.documents, isEmpty);
      state.dispose();
    },
  );

  test(
    'a stale document sync cannot overwrite the new detected label',
    () async {
      final docsStarted = Completer<void>(),
          docsReply = Completer<http.Response>();
      final api = Api(
        client: MockClient((r) async {
          if (r.url.path.endsWith('/classify'))
            return http.Response(jsonEncode(detected), 200);
          if (r.url.path == '/api/state')
            return http.Response('{"state":{},"version":0}', 200);
          if (r.url.path == '/api/documents') {
            docsStarted.complete();
            return docsReply.future;
          }
          return http.Response('{}', 200);
        }),
      );
      final state = signed(api);
      final sync = state.sync();
      await docsStarted.future;
      await state.classifyReport('photo');
      docsReply.complete(
        http.Response(
          '[{"id":"photo","kind":"Lab Report","report_type":null}]',
          200,
        ),
      );
      await sync;
      expect(state.documents.single['report_type'], 'lipid');
      state.dispose();
    },
  );

  testWidgets(
    'manual report category is preserved without another model request',
    (tester) async {
      final api = Api(
        client: MockClient((_) async {
          fail('Reviewed report must not be automatically relabeled');
        }),
      );
      final state = signed(api);
      final manual = {
        ...detected,
        'report_type': 'urine',
        'report_reviewed': true,
      };
      await tester.pumpWidget(
        Scope(
          state: state,
          child: MaterialApp(home: ReportReview(report: manual)),
        ),
      );
      await tester.pumpAndSettle();
      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      expect(dropdown.initialValue, 'urine');
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
