import 'localization.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/services.dart';

import 'design.dart';

/// One motion language for named routes and directly pushed detail pages.
/// Keep native Cupertino navigation/interactive back gestures on Apple devices.
class MedPageTransitions extends PageTransitionsBuilder {
  const MedPageTransitions();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      return child;
    }
    final eased = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return SlideTransition(
      textDirection: Directionality.of(context),
      position: eased.drive(
        Tween(begin: const Offset(.16, 0), end: Offset.zero),
      ),
      child: child,
    );
  }
}

class MedCupertinoTransitions extends PageTransitionsBuilder {
  const MedCupertinoTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context))
      return child;
    return cupertino.CupertinoRouteTransitionMixin.buildPageTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

class MedLoader extends StatefulWidget {
  const MedLoader({
    super.key,
    this.size = 76,
    this.label = 'Loading',
    this.dark = false,
  });
  final double size;
  final String label;
  final bool dark;

  @override
  State<MedLoader> createState() => _MedLoaderState();
}

class _MedLoaderState extends State<MedLoader>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (reduced) {
      controller.stop();
      controller.value = 0;
    } else if (!controller.isAnimating) {
      controller.repeat();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    liveRegion: true,
    child: ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: widget.size,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: controller,
                builder: (_, child) => CustomPaint(
                  painter: _OrbitPainter(controller.value, widget.dark),
                  child: child,
                ),
                child: Center(child: Mark(size: widget.size * .38)),
              ),
            ),
          ),
          if (widget.label.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              tr(widget.label),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.dark ? const Color(0xFFB8D5FF) : muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter(this.progress, this.dark);
  final double progress;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .42;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = (dark ? cyan : blue).withAlpha(35),
    );
    const colors = [cyan, blue, purple];
    for (var i = 0; i < colors.length; i++) {
      final angle = progress * math.pi * 2 + i * math.pi * 2 / 3 - math.pi / 2;
      final offset = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(offset, size.width * .043, Paint()..color = colors[i]);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) =>
      old.progress != progress || old.dark != dark;
}

/// Only appears while the encrypted local session is actually being restored.
class MedLaunchScreen extends StatelessWidget {
  const MedLaunchScreen({super.key});

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: const Color(0xFF001631),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
    child: const Scaffold(
      backgroundColor: Color(0xFF001631),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Brand(dark: true, large: true),
              SizedBox(height: 36),
              MedLoader(
                size: 88,
                label: 'Opening your secure workspace…',
                dark: true,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
