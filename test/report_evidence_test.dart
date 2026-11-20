import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:med_ai/models.dart';
import 'package:med_ai/services/api.dart';
import 'package:med_ai/screens/ai_studio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_ai/screens/report_evidence.dart';

void main() {
  testWidgets(
    'actual report values and ranges are visible separately from AI prose',
    (tester) async {
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReportEvidence(
                sources: const [
                  {
                    'label': 'R1',
                    'document_id': 'test-report',
                    'title': 'Synthetic CBC',
                    'date': '2026-11-01',
                    'excerpt':
                        'Hemoglobin 10.2 g/dL Reference 12.0-16.0\nWBC 7000 cells/uL Reference 4000-11000',
                  },
                ],
                onOpen: (id) => opened = id,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Report details used'), findsOneWidget);
      expect(
        find.textContaining('Hemoglobin 10.2 g/dL Reference 12.0-16.0'),
        findsOneWidget,
      );
      expect(
        find.textContaining('WBC 7000 cells/uL Reference 4000-11000'),
        findsOneWidget,
      );
      await tester.tap(find.text('View original report'));
      expect(opened, 'test-report');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('an empty report source list adds no invented test values', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportEvidence(sources: const [], onOpen: (_) {}),
        ),
      ),
    );
    expect(find.text('Report details used'), findsNothing);
  });

  testWidgets(
    'asking about a report retrieves records and shows the source details',
    (tester) async {
      var sends = 0;
      final api = Api(
        client: MockClient((request) async {
          if (request.method == 'GET')
            return http.Response('{"threads":[]}', 200);
          sends++;
          final body = jsonDecode(request.body);
          expect(body['use_records'], true);
          expect(body['consent'], true);
          return http.Response(
            jsonEncode({
              'id': 'test-thread',
              'turns': [
                {
                  'question': body['question'],
                  'answer': 'Hemoglobin is 10.2 g/dL [R1].',
                  'language': 'en',
                  'triage': null,
                  'report_details': [
                    {
                      'label': 'R1',
                      'document_id': 'test-report',
                      'title': 'Synthetic CBC',
                      'excerpt': 'Hemoglobin 10.2 g/dL Reference 12-16',
                    },
                  ],
                  'sources': [],
                  'health': [],
                  'findings': [],
                },
              ],
            }),
            200,
          );
        }),
      );
      final s = AppState(api: api);
      s.userId = 'a' * 32;
      api.token = 'test-token';
      await tester.pumpWidget(
        MaterialApp(
          home: Scope(state: s, child: const AiStudio()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Explain my report');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(sends, 0);
      expect(find.textContaining('configured AI provider'), findsOneWidget);
      await tester.tap(find.text('Allow and send'));
      await tester.pumpAndSettle();
      expect(sends, 1);
      expect(find.text('Report details used'), findsOneWidget);
      expect(
        find.textContaining('Hemoglobin 10.2 g/dL Reference 12-16'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    },
  );
}
