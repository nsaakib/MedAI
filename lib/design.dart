import 'localization.dart';
import 'models.dart';

import 'package:flutter/material.dart';

const navy = Color(0xFF081872);
const blue = Color(0xFF176BFF);
const purple = Color(0xFF6848FF);
const cyan = Color(0xFF00DCD0);
const muted = Color(0xFF7484B9);
const border = Color(0xFFE6EDFF);
const mint = Color(0xFF17C7A0);
const soft = Color(0xFFF5F8FF);
const gradient = LinearGradient(
  colors: [Color(0xFF285BFF), Color(0xFF12B4F9)],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);
const aquaGradient = LinearGradient(
  colors: [Color(0xFF176BFF), Color(0xFF00E5CE)],
);

class Mark extends StatelessWidget {
  const Mark({super.key, this.size = 29});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/medai_brand_mark.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key, this.dark = false, this.large = false});
  final bool dark, large;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Mark(size: large ? 38 : 27),
      const SizedBox(width: 7),
      Flexible(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Med.',
                style: TextStyle(color: dark ? Colors.white : navy),
              ),
              TextSpan(
                text: 'ai',
                style: TextStyle(color: dark ? cyan : blue),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: large ? 30 : 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
      ),
    ],
  );
}

class Tile extends StatelessWidget {
  const Tile({
    super.key,
    required this.child,
    this.padding = 14,
    this.outlined = true,
    this.color = Colors.white,
    this.onTap,
  });
  final Widget child;
  final double padding;
  final bool outlined;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: color,
      elevation: outlined ? 0 : 4,
      shadowColor: const Color(0x24206090),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            border: outlined ? Border.all(color: border) : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x062060FF),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = blue});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withAlpha(20),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      tr(text),
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
    ),
  );
}

class Bubble extends StatelessWidget {
  const Bubble(this.icon, {super.key, this.color = blue, this.size = 38});
  final IconData icon;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withAlpha(21),
      borderRadius: BorderRadius.circular(size * .36),
    ),
    child: Icon(icon, color: color, size: size * .53),
  );
}

class ActionButton extends StatelessWidget {
  const ActionButton(
    this.text, {
    super.key,
    required this.onTap,
    this.icon = Icons.arrow_forward,
    this.aqua = false,
  });
  final String text;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool aqua;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      gradient: onTap == null
          ? null
          : aqua
          ? aquaGradient
          : gradient,
      color: onTap == null ? const Color(0xFFD7DEEE) : null,
      borderRadius: BorderRadius.circular(26),
      boxShadow: onTap == null
          ? []
          : const [
              BoxShadow(
                color: Color(0x24295BFF),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  tr(text),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 10),
                Icon(icon, color: Colors.white, size: 19),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class Heading extends StatelessWidget {
  const Heading(this.text, {super.key, this.action, this.onTap});
  final String text;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            tr(text),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        if (action != null)
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                tr(action!),
                style: const TextStyle(color: blue, fontSize: 11),
              ),
            ),
          ),
      ],
    ),
  );
}

Widget small(String text, {Color color = muted}) =>
    Text(tr(text), style: TextStyle(fontSize: 11, color: color, height: 1.5));
Widget gap([double height = 12]) => SizedBox(height: height);
void go(BuildContext c, String route, {Object? arguments}) =>
    Navigator.of(c).pushNamed('/$route', arguments: arguments);
void home(BuildContext c) =>
    Navigator.of(c).pushNamedAndRemoveUntil('/home', (route) => false);
void message(BuildContext c, String title, String text) => showDialog<void>(
  context: c,
  builder: (context) => AlertDialog(
    title: Text(tr(title)),
    content: Text(tr(text), style: const TextStyle(height: 1.5)),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Got it')),
      ),
    ],
  ),
);
Widget rowTile(
  IconData icon,
  String title,
  String subtitle,
  VoidCallback? tap, {
  Color color = blue,
  Widget? trailing,
}) => Tile(
  onTap: tap,
  child: Row(
    children: [
      Bubble(icon, color: color),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(title),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            if (subtitle.isNotEmpty) ...[gap(3), small(tr(subtitle))],
          ],
        ),
      ),
      trailing ?? const Icon(Icons.chevron_right, size: 18, color: blue),
    ],
  ),
);
Widget note(String text, {Color color = Colors.orange}) => Tile(
  color: color.withAlpha(15),
  padding: 12,
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.info_outline, color: color, size: 19),
      const SizedBox(width: 10),
      Expanded(
        child: small(
          tr(text),
          color: color == Colors.orange ? const Color(0xFF976232) : color,
        ),
      ),
    ],
  ),
);

class AppFrame extends StatelessWidget {
  const AppFrame({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.back = false,
    this.bottom = true,
    this.tab = 0,
    this.brand = true,
    this.actions,
    this.padding = 18,
  });
  final Widget child;
  final String? title, subtitle;
  final bool back, bottom, brand;
  final int tab;
  final List<Widget>? actions;
  final double padding;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F8FF),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          color: Colors.white,
          child: Stack(
            children: [
              const Positioned.fill(
                child: CustomPaint(painter: _WavePainter()),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Row(
                        children: [
                          if (back)
                            IconButton(
                              tooltip: tr('Back'),
                              onPressed: () {
                                if (Navigator.canPop(context)) {
                                  Navigator.pop(context);
                                } else {
                                  home(context);
                                }
                              },
                              icon: const Icon(Icons.chevron_left, color: navy),
                            ),
                          if (brand)
                            const Brand()
                          else
                            Expanded(
                              child: Text(
                                tr(title ?? ''),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (brand) const Spacer(),
                          PopupMenuButton<String>(
                            tooltip: tr('App language'),
                            icon: const Icon(Icons.language, color: blue),
                            initialValue: UiLanguage.locale.value.languageCode,
                            onSelected: (code) async {
                              try {
                                await Scope.of(context).setLanguage(code);
                              } catch (_) {
                                if (context.mounted)
                                  message(
                                    context,
                                    tr('Could not save'),
                                    tr(
                                      'Check available storage and try again.',
                                    ),
                                  );
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'en',
                                child: Text(tr('English')),
                              ),
                              PopupMenuItem(
                                value: 'bn',
                                child: Text(tr('বাংলা')),
                              ),
                            ],
                          ),
                          ...?actions,
                          if (brand && !back && actions == null) ...[
                            IconButton(
                              tooltip: tr('Notifications'),
                              onPressed: () => go(context, 'cases'),
                              icon: const Icon(
                                Icons.notifications_none,
                                color: navy,
                                size: 21,
                              ),
                            ),
                            InkWell(
                              onTap: () => go(context, 'profile'),
                              child: const CircleAvatar(
                                radius: 15,
                                child: Icon(Icons.person_outline, size: 19),
                              ),
                            ),
                          ],
                          if (!brand && back) const SizedBox(width: 40),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        key: PageStorageKey(title ?? 'page'),
                        padding: EdgeInsets.fromLTRB(padding, 2, padding, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (title != null && brand)
                              Text(
                                tr(title!),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -.5,
                                ),
                              ),
                            if (subtitle != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 3,
                                  bottom: 14,
                                ),
                                child: small(tr(subtitle!)),
                              ),
                            child,
                          ],
                        ),
                      ),
                    ),
                    if (bottom) BottomBar(tab: tab),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.tab});
  final int tab;
  @override
  Widget build(BuildContext context) => Container(
    height: 68,
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      boxShadow: [
        BoxShadow(
          color: Color(0x102663EE),
          blurRadius: 20,
          offset: Offset(0, -2),
        ),
      ],
    ),
    child: Row(
      children: [
        nav(context, 0, Icons.home_outlined, 'Home', 'home'),
        nav(context, 1, Icons.description_outlined, 'Reports', 'records'),
        Expanded(
          child: Center(
            child: Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [purple, blue, Color(0xFF22B6FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x55686BFF),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: IconButton(
                tooltip: tr('Add document'),
                onPressed: () => _navigate(context, 'add'),
                icon: const Icon(Icons.add, color: Colors.white, size: 30),
              ),
            ),
          ),
        ),
        nav(context, 3, Icons.history, 'History', 'history'),
        nav(context, 4, Icons.auto_awesome_rounded, 'AI Chat', 'ai-studio'),
      ],
    ),
  );
  bool _isDestination(BuildContext context, String target) =>
      ModalRoute.of(context)?.settings.name == '/$target';

  void _navigate(BuildContext context, String target) {
    if (_isDestination(context, target)) return;
    if (target == 'home') {
      home(context);
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/$target',
        (route) => route.settings.name == '/home' || route.isFirst,
      );
    }
  }

  Widget nav(
    BuildContext context,
    int i,
    IconData icon,
    String label,
    String target,
  ) => Expanded(
    child: InkWell(
      onTap: () => _navigate(context, target),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: _isDestination(context, target) ? purple : muted,
            size: 23,
          ),
          const SizedBox(height: 3),
          Text(
            tr(label),
            style: TextStyle(
              fontSize: 9,
              color: _isDestination(context, target) ? blue : muted,
            ),
          ),
          const SizedBox(height: 5),
          Container(
            height: 2,
            width: 20,
            color: _isDestination(context, target)
                ? purple
                : Colors.transparent,
          ),
        ],
      ),
    ),
  );
}

class _WavePainter extends CustomPainter {
  const _WavePainter();
  @override
  void paint(Canvas c, Size s) {
    final p = Path()
      ..moveTo(0, 170)
      ..cubicTo(s.width * .65, 215, s.width * .75, 30, s.width, 95)
      ..lineTo(s.width, 0)
      ..lineTo(0, 0)
      ..close();
    c.drawPath(
      p,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.white, Color(0xFFEEF2FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & s),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class Segments extends StatelessWidget {
  const Segments({
    super.key,
    required this.labels,
    required this.value,
    required this.onChanged,
  });
  final List<String> labels;
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: soft,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        for (int i = 0; i < labels.length; i++)
          Expanded(
            child: InkWell(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration:
                    MediaQuery.disableAnimationsOf(context) ||
                        MediaQuery.accessibleNavigationOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: value == i ? gradient : null,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  tr(labels[i]),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: value == i ? Colors.white : navy,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

final medicineActionStyle = FilledButton.styleFrom(
  backgroundColor: const Color(0xFFEAF0FF),
  foregroundColor: navy,
  elevation: 1,
  shadowColor: const Color(0x16206090),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
);
