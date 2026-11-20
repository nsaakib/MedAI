import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_ai/models.dart';
import 'package:med_ai/screens/documents_live.dart';

class ReportState extends AppState {
  bool deferred = false;
  Map<String, dynamic>? saved;
  @override
  Future<String> queueDocument(
    Uint8List bytes, {
    String? kind,
    String? language,
  }) async {
    documents.add({
      'id': 'report-test',
      'kind': kind,
      'created': 1794480000,
      'uploaded': !deferred,
      'ocr_text': '',
      'report_title': 'Untitled report',
    });
    notifyListeners();
    return 'report-test';
  }

  @override
  Future<void> updateReportDetails(
    String id,
    Map<String, dynamic> details,
  ) async {
    saved = details;
  }
}

void main() {
  for (final deferred in [false, true]) {
    testWidgets(
      'upload opens review and saves back to library; queued=$deferred',
      (tester) async {
        final state = ReportState()..deferred = deferred;
        await tester.pumpWidget(
          Scope(
            state: state,
            child: const MaterialApp(home: ReportsLibrary()),
          ),
        );
        await tester.ensureVisible(find.text('Upload report'));
        await tester.tap(find.text('Upload report'));
        await tester.pumpAndSettle();
        // Bypass the platform image picker; exercise the real save/navigation path.
        final dynamic upload = tester.state(find.byType(DocumentsLive));
        upload.image = Uint8List.fromList([1, 2, 3]);
        await upload.save();
        await tester.pumpAndSettle();
        if (deferred) {
          expect(find.byType(ReportReview), findsNothing);
          expect(find.textContaining('Saved on this device.'), findsOneWidget);
          state.documents.single['uploaded'] = true;
          state.notifyListeners();
          await tester.pumpAndSettle();
        }
        expect(find.byType(ReportReview), findsOneWidget);
        expect(
          find.textContaining('no readable text was detected'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Save report'));
        await tester.tap(find.text('Save report'));
        await tester.pumpAndSettle();
        expect(state.saved, isNotNull);
        expect(find.byType(ReportsLibrary), findsOneWidget);
        expect(find.byType(DocumentsLive), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      },
    );
  }
}
