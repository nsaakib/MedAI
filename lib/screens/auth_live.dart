import '../localization.dart';

import 'package:flutter/material.dart';

import '../design.dart';
import '../models.dart';
import '../motion.dart';
import 'medicine_setup.dart';

class AuthLive extends StatefulWidget {
  const AuthLive({super.key, required this.mode});
  final String mode;
  @override
  State<AuthLive> createState() => _AuthLiveState();
}

class _AuthLiveState extends State<AuthLive> {
  final form = GlobalKey<FormState>();
  String name = '', email = '', password = '';
  bool hidden = true, busy = false;
  String? error;
  @override
  Widget build(BuildContext c) {
    final welcome = widget.mode == 'welcome';
    final signup = widget.mode == 'register';
    final keyboard = MediaQuery.viewInsetsOf(c).bottom > 0;
    final reduced =
        MediaQuery.disableAnimationsOf(c) ||
        MediaQuery.accessibleNavigationOf(c);
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: const Color(0xFF001631),
        body: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _AuthBackdrop()),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, viewport) => Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: LayoutBuilder(
                      builder: (context, bounds) {
                        final padding = bounds.maxWidth < 360 ? 20.0 : 24.0;
                        final artWidth = bounds.maxWidth - padding * 2;
                        final compact = viewport.maxHeight < 640;
                        final artHeight = welcome
                            ? (artWidth * .67).clamp(
                                160.0,
                                compact ? 220.0 : 290.0,
                              )
                            : (artWidth * .47).clamp(110.0, 180.0);
                        return SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.symmetric(
                            horizontal: padding,
                            vertical: 24,
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: (viewport.maxHeight - 48).clamp(
                                0.0,
                                double.infinity,
                              ),
                            ),
                            child: AutofillGroup(
                              child: Form(
                                key: form,
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      children: [
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.white,
                                            ),
                                            icon: const Icon(Icons.language),
                                            label: Text(
                                              UiLanguage
                                                          .locale
                                                          .value
                                                          .languageCode ==
                                                      'bn'
                                                  ? 'English'
                                                  : 'বাংলা',
                                            ),
                                            onPressed: busy
                                                ? null
                                                : () async {
                                                    try {
                                                      await Scope.of(
                                                        context,
                                                      ).setLanguage(
                                                        UiLanguage
                                                                    .locale
                                                                    .value
                                                                    .languageCode ==
                                                                'bn'
                                                            ? 'en'
                                                            : 'bn',
                                                      );
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
                                          ),
                                        ),
                                        Brand(dark: true, large: !keyboard),
                                        gap(10),
                                        Text(
                                          tr(
                                            'Your Health · Our AI · A Smarter Tomorrow',
                                          ),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Color(0xFFA9C8FF),
                                            fontSize: 11,
                                            height: 1.5,
                                          ),
                                        ),
                                        AnimatedSize(
                                          duration: reduced
                                              ? Duration.zero
                                              : const Duration(
                                                  milliseconds: 220,
                                                ),
                                          curve: Curves.easeOutCubic,
                                          alignment: Alignment.topCenter,
                                          child: SizedBox(
                                            height: keyboard
                                                ? 16
                                                : artHeight + 24,
                                            width: double.infinity,
                                            child: keyboard
                                                ? const SizedBox.shrink()
                                                : Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 18,
                                                          bottom: 6,
                                                        ),
                                                    child: Image.asset(
                                                      'assets/${welcome
                                                          ? 'welcome'
                                                          : signup
                                                          ? 'signup'
                                                          : 'login'}_art.png',
                                                      fit: BoxFit.contain,
                                                      alignment:
                                                          Alignment.center,
                                                      filterQuality:
                                                          FilterQuality.high,
                                                      excludeFromSemantics:
                                                          true,
                                                      errorBuilder:
                                                          (_, error, stack) =>
                                                              const Center(
                                                                child: Mark(
                                                                  size: 72,
                                                                ),
                                                              ),
                                                    ),
                                                  ),
                                          ),
                                        ),
                                        gap(keyboard ? 0 : 12),
                                        if (welcome)
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: tr('Your health, '),
                                                ),
                                                TextSpan(
                                                  text: tr('connected'),
                                                  style: TextStyle(color: cyan),
                                                ),
                                              ],
                                            ),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 29,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -.7,
                                              height: 1.15,
                                            ),
                                          )
                                        else
                                          Text(
                                            tr(
                                              signup
                                                  ? 'Create Your Account'
                                                  : 'Welcome Back',
                                            ),
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 27,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -.6,
                                            ),
                                          ),
                                        if (!keyboard) ...[
                                          gap(12),
                                          Text(
                                            tr(
                                              'Your records. Your medicines.\nConnected to your care team.',
                                            ),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Color(0xFFB8D5FF),
                                              height: 1.6,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                        gap(keyboard ? 18 : 24),
                                        if (!welcome) ...[
                                          if (signup)
                                            field(
                                              'Full name',
                                              Icons.person_outline,
                                              (v) => name = v!,
                                              validator: (v) => tr(
                                                v == null || v.trim().isEmpty
                                                    ? 'Enter your name'
                                                    : null,
                                              ),
                                            ),
                                          field(
                                            'Email address',
                                            Icons.mail_outline,
                                            (v) => email = v!,
                                            validator: (v) => tr(
                                              v == null || !v.contains('@')
                                                  ? 'Enter your email'
                                                  : null,
                                            ),
                                          ),
                                          field(
                                            'Password',
                                            Icons.lock_outline,
                                            (v) => password = v!,
                                            obscure: hidden,
                                            validator: (v) => tr(
                                              v == null || v.length < 10
                                                  ? 'Use at least 10 characters'
                                                  : null,
                                            ),
                                            suffix: IconButton(
                                              tooltip: tr(
                                                hidden
                                                    ? 'Show password'
                                                    : 'Hide password',
                                              ),
                                              onPressed: () => setState(
                                                () => hidden = !hidden,
                                              ),
                                              icon: Icon(
                                                hidden
                                                    ? Icons.visibility_outlined
                                                    : Icons
                                                          .visibility_off_outlined,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Column(
                                      children: [
                                        if (error != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 15,
                                            ),
                                            child: Text(
                                              tr(error!),
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Color(0xFFFFBFC5),
                                              ),
                                            ),
                                          ),
                                        ActionButton(
                                          tr(
                                            welcome
                                                ? 'Get Started'
                                                : signup
                                                ? 'Create Account'
                                                : 'Log In',
                                          ),
                                          aqua: true,
                                          onTap: busy
                                              ? null
                                              : welcome
                                              ? () => go(c, 'register')
                                              : submit,
                                        ),
                                        gap(12),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.white,
                                              side: const BorderSide(
                                                color: Color(0xFF3B6293),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 18,
                                                    vertical: 16,
                                                  ),
                                              shape: const StadiumBorder(),
                                            ),
                                            onPressed: busy
                                                ? null
                                                : () => go(
                                                    c,
                                                    welcome || signup
                                                        ? 'login'
                                                        : 'register',
                                                  ),
                                            child: Text(
                                              tr(
                                                welcome || signup
                                                    ? 'Log In'
                                                    : 'Create Account',
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (!welcome)
                                          TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => message(
                                                    c,
                                                    tr('Account access'),
                                                    tr(
                                                      'Password reset and email verification are not configured yet. Contact your project administrator for account recovery.',
                                                    ),
                                                  ),
                                            child: Text(
                                              tr('Need help signing in?'),
                                              style: TextStyle(
                                                color: Color(0xFFA9C8FF),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        gap(18),
                                        Text(
                                          tr(
                                            'Records are encrypted on your device and server.',
                                          ),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Color(0xFF92AFE0),
                                            fontSize: 11,
                                            height: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (busy)
              Positioned.fill(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const ModalBarrier(
                      dismissible: false,
                      color: Color(0xDE001631),
                    ),
                    MedLoader(
                      dark: true,
                      label: signup
                          ? 'Creating your account…'
                          : 'Connecting securely…',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget field(
    String label,
    IconData icon,
    FormFieldSetter<String> save, {
    bool obscure = false,
    Widget? suffix,
    FormFieldValidator<String>? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: TextFormField(
      obscureText: obscure,
      enabled: !busy,
      keyboardType: label == 'Email address'
          ? TextInputType.emailAddress
          : TextInputType.text,
      autofillHints: [
        label == 'Full name'
            ? AutofillHints.name
            : label == 'Email address'
            ? AutofillHints.email
            : widget.mode == 'register'
            ? AutofillHints.newPassword
            : AutofillHints.password,
      ],
      textInputAction: label == 'Password'
          ? TextInputAction.done
          : TextInputAction.next,
      onFieldSubmitted: label == 'Password'
          ? (_) {
              if (!busy) submit();
            }
          : null,
      autocorrect: false,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      onSaved: save,
      validator: validator,
      decoration: InputDecoration(
        labelText: tr(label),
        labelStyle: const TextStyle(color: Color(0xFFB8D5FF)),
        prefixIcon: Icon(icon, color: Colors.white, size: 19),
        suffixIcon: suffix,
        fillColor: const Color(0xFF052246),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFF205F9B)),
        ),
      ),
    ),
  );
  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    form.currentState!.save();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final s = Scope.of(context);
      await s.authenticate(
        email.trim(),
        password,
        fullName: widget.mode == 'register' ? name.trim() : null,
      );
      if (mounted && widget.mode == 'register' && !s.mealsConfigured) {
        await setupMeals(context, s);
      }
      if (mounted) home(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _AuthBackdrop extends CustomPainter {
  const _AuthBackdrop();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF041C41), Color(0xFF002454), Color(0xFF00142C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );
    final wave = Path()
      ..moveTo(0, size.height * .83)
      ..cubicTo(
        size.width * .32,
        size.height * .76,
        size.width * .48,
        size.height * 1.04,
        size.width,
        size.height * .9,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      wave,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x992C5DF2), Color(0x5526BCFF)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _AuthBackdrop oldDelegate) => false;
}
