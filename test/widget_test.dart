import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_ai/main.dart';
import 'package:med_ai/models.dart';

void main() {
  testWidgets('welcome retains approved identity and has no demo bypass', (
    tester,
  ) async {
    final s = AppState();
    await tester.pumpWidget(MedAiApp(state: s));
    await tester.pumpAndSettle();
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.textContaining('Preview app'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
  for (final width in [360.0, 390.0, 480.0]) {
    testWidgets('empty real home renders at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = AppState();
      s.userId = 'a' * 32;
      s.api.token = 'local-test-only';
      s.name = 'Patient';
      await tester.pumpWidget(MedAiApp(state: s));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('0 medicines · 0 reminder times'),
        findsOneWidget,
      );
      expect(find.textContaining('Metformin'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    });
  }
}
