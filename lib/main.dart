import 'localization.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design.dart';
import 'models.dart';
import 'motion.dart';
import 'screens/auth_live.dart';
import 'screens/workspace.dart';
import 'screens/private_profile.dart';
import 'screens/documents_live.dart';
import 'screens/medicines_live.dart';
import 'screens/doctors_live.dart';
import 'services/doctors_directory.dart';
import 'screens/care_live.dart';
import 'screens/sos_live.dart';
import 'screens/ai_studio.dart';
import 'screens/health_dashboard.dart';
import 'screens/health_live.dart';
import 'screens/knowledge_live.dart';
import 'screens/purchase_flow.dart';
import 'screens/pharmacies_live.dart';
import 'screens/extraction_live.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  runApp(MedBootstrap(state: state));
}

class MedBootstrap extends StatefulWidget {
  const MedBootstrap({super.key, required this.state});
  final AppState state;
  @override
  State<MedBootstrap> createState() => _MedBootstrapState();
}

class _MedBootstrapState extends State<MedBootstrap> {
  late final Future<void> initialization;
  @override
  void initState() {
    super.initState();
    initialization = widget.state.initialize();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: initialization,
    builder: (_, snapshot) {
      if (snapshot.connectionState == ConnectionState.done) {
        return MedAiApp(state: widget.state);
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Inter'),
        home: const MedLaunchScreen(),
      );
    },
  );
}

class MedAiApp extends StatelessWidget {
  const MedAiApp({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext c) => Scope(
    state: state,
    child: ValueListenableBuilder<Locale>(
      valueListenable: UiLanguage.locale,
      builder: (context, locale, _) => MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('bn')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        title: 'Med.ai',
        debugShowCheckedModeBanner: false,
        initialRoute:
            isSosRoute(
              WidgetsBinding.instance.platformDispatcher.defaultRouteName,
            )
            ? '/ambulance-sos'
            : (state.signedIn ? '/home' : '/welcome'),
        theme: ThemeData(
          useMaterial3: true,
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: MedPageTransitions(),
              TargetPlatform.iOS: MedCupertinoTransitions(),
              TargetPlatform.macOS: MedCupertinoTransitions(),
              TargetPlatform.windows: MedPageTransitions(),
              TargetPlatform.linux: MedPageTransitions(),
              TargetPlatform.fuchsia: MedPageTransitions(),
            },
          ),
          fontFamily: locale.languageCode == 'bn' ? 'NotoSansBengali' : 'Inter',
          scaffoldBackgroundColor: Colors.white,
          colorScheme: ColorScheme.fromSeed(
            seedColor: blue,
            primary: blue,
            secondary: purple,
            surface: Colors.white,
          ),
          textTheme: const TextTheme(
            bodyMedium: TextStyle(color: navy, fontSize: 12),
            bodyLarge: TextStyle(color: navy, fontSize: 13),
          ),
          inputDecorationTheme: InputDecorationTheme(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 13,
            ),
            filled: true,
            fillColor: const Color(0xFFFAFCFF),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: border),
            ),
            labelStyle: const TextStyle(color: muted, fontSize: 12),
          ),
        ),
        onGenerateRoute: (settings) {
          final Widget page = switch (isSosRoute(settings.name)
              ? '/ambulance-sos'
              : settings.name) {
            '/welcome' => const AuthLive(mode: 'welcome'),
            '/login' => const AuthLive(mode: 'login'),
            '/register' => const AuthLive(mode: 'register'),
            '/home' => const HomeLive(),
            '/knowledge' => const KnowledgeLive(),
            '/add' ||
            '/camera' ||
            '/review' ||
            '/analyzing' ||
            '/extraction' => const DocumentsLive(),
            '/medicine' => MedicineLive(
              id: settings.arguments is String
                  ? settings.arguments as String
                  : null,
              initial: settings.arguments is Map
                  ? Map<String, dynamic>.from(settings.arguments as Map)
                  : null,
            ),
            '/ocr-review' => ExtractionLive(
              documentId: settings.arguments as String,
            ),
            '/today' => const MedicineListLive(),
            '/prices' => const PurchaseFlowLive(step: PurchaseStep.prices),
            '/total-cost' => const PurchaseFlowLive(step: PurchaseStep.total),
            '/budget' => const PurchaseFlowLive(step: PurchaseStep.budget),
            '/budget-result' => const PurchaseFlowLive(
              step: PurchaseStep.result,
            ),
            '/quantities' => const PurchaseFlowLive(
              step: PurchaseStep.quantities,
            ),
            '/basket' => const PurchaseFlowLive(step: PurchaseStep.basket),
            '/reminders' => const RemindersLive(),
            '/records' ||
            '/history' => RecordsLive(history: settings.name == '/history'),
            '/ai-studio' => AiStudio(statistics: settings.arguments == true),
            '/health-dashboard' => const HealthDashboard(),
            '/health' || '/heart' => const HealthLive(),
            '/private-profile' => const PrivateProfile(),
            '/profile' || '/settings' => const ProfileLive(),
            '/pharmacies' => const PharmaciesLive(),
            '/doctors' => DoctorsLive(
              initialDivision: settings.arguments is Map
                  ? (settings.arguments as Map)['division'] as String?
                  : null,
              initialSpecialty: settings.arguments is Map
                  ? (settings.arguments as Map)['specialty'] as String?
                  : null,
            ),
            '/doctor-profile' =>
              settings.arguments is DoctorListing
                  ? DoctorProfileLive(
                      doctor: settings.arguments as DoctorListing,
                    )
                  : const DoctorsLive(),
            '/doctor-appointment' =>
              settings.arguments is DoctorListing
                  ? DoctorAppointmentLive(
                      doctor: settings.arguments as DoctorListing,
                    )
                  : const DoctorsLive(),
            '/ambulance-sos' => const EmergencySosLive(),
            '/care' => const CareLive(),
            '/handoff' || '/match' => const ReviewRequestLive(),
            '/cases' => const CasesLive(),
            _ => const ServiceStatusLive(),
          };
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (context) => AnimatedBuilder(
              animation: state,
              builder: (c, _) => AnnotatedRegion<SystemUiOverlayStyle>(
                value:
                    const [
                      '/welcome',
                      '/login',
                      '/register',
                    ].contains(settings.name)
                    ? SystemUiOverlayStyle.light.copyWith(
                        statusBarColor: Colors.transparent,
                        systemNavigationBarColor: const Color(0xFF001631),
                        systemNavigationBarIconBrightness: Brightness.light,
                      )
                    : SystemUiOverlayStyle.dark.copyWith(
                        statusBarColor: Colors.transparent,
                        systemNavigationBarColor: Colors.white,
                        systemNavigationBarIconBrightness: Brightness.dark,
                      ),
                child:
                    (!state.signedIn || state.needsSignIn) &&
                        !const [
                          '/welcome',
                          '/login',
                          '/register',
                        ].contains(settings.name)
                    ? const AuthLive(mode: 'login')
                    : page,
              ),
            ),
          );
        },
      ),
    ),
  );
}
