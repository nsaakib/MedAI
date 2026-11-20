import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_ai/main.dart';
import 'package:med_ai/models.dart';
import 'package:med_ai/motion.dart';
import 'package:med_ai/screens/auth_live.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(480, 800),
    const Size(740, 360),
  ]) {
    for (final mode in ['welcome', 'login', 'register']) {
      testWidgets('$mode fits $size with larger text and safe scrolling', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = AppState();
        await tester.pumpWidget(
          MaterialApp(
            home: Scope(
              state: state,
              child: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(1.5),
                ),
                child: AuthLive(mode: mode),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find
            .text(
              mode == 'welcome'
                  ? 'Get Started'
                  : mode == 'login'
                  ? 'Log In'
                  : 'Create Account',
            )
            .first;
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(button, findsOneWidget);
        // The retained brand mark and decorative artwork are both images.
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          expect(image.fit, BoxFit.contain);
        }
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      });
    }
  }

  testWidgets('keyboard hides decorative artwork without hiding form fields', (
    tester,
  ) async {
    final state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        home: Scope(
          state: state,
          child: const MediaQuery(
            data: MediaQueryData(
              size: Size(390, 844),
              viewInsets: EdgeInsets.only(bottom: 300),
            ),
            child: AuthLive(mode: 'register'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Only the small brand image remains; keyboard hides the large artwork.
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, lessThanOrEqualTo(38));
    expect(
      (tester.widget<AnimatedSize>(find.byType(AnimatedSize)).child as SizedBox)
          .height,
      16,
    );
    expect(find.byType(TextFormField), findsNWidgets(3));
    await tester.ensureVisible(find.text('Create Account').first);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('loader stops ticking under reduced motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Center(child: MedLoader(label: 'Opening workspace')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Opening workspace'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('named navigation arrives and returns without changing auth', (
    tester,
  ) async {
    final state = AppState();
    await tester.pumpWidget(MedAiApp(state: state));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Get Started'));
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(find.text('Create Your Account'), findsOneWidget);
    expect(state.signedIn, isFalse);
    final context = tester.element(find.byType(AuthLive).last);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(find.text('Get Started'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
