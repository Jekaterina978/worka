import 'package:flutter/material.dart' as m;
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'config/app_env.dart';
import 'firebase_options.dart';
import 'controllers/paid_entitlements_controller.dart';
import 'features/payments/contact_access_controller.dart';
import 'features/payments/payments_routes.dart';
import 'features/payments/screens/credits_wallet_screen.dart';
import 'features/payments/screens/promote_job_screen.dart';
import 'features/payments/screens/verification_status_screen.dart';
import 'features/payments/screens/verification_upload_screen.dart';
import 'features/payments/screens/verified_employer_paywall_screen.dart';
import 'features/monetization/monetization_routes.dart';
import 'features/monetization/screens/boost_profile_paywall_screen.dart';
import 'features/monetization/employer/private_plans_screen.dart';
import 'features/monetization/screens/worker_plans_screen.dart';
import 'services/firebase_debug_diagnostics.dart';
import 'services/app_mode.dart';
import 'services/auth_controller.dart';
import 'services/auth_guard.dart';
import 'services/guest_uid_service.dart';
import 'services/guest_migration_service.dart';
import 'services/test_data_migration_service.dart';
import 'services/response_stats_service.dart';
import 'auth/auth_gate.dart';
import 'screens/payment_result_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/new_response_screen.dart';
import 'screens/cv/my_cvs_screen.dart';
import 'screens/employer/my_publications_screen.dart';
import 'theme/worka_colors.dart';
import 'widgets/response_card.dart';

const bool kDebugBypassAuth = true;
const bool enableNewHome = false;
const String publishableKey = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
const String _stripeEnv = String.fromEnvironment('STRIPE_ENV');
const String _stripeMerchantIdentifier = String.fromEnvironment(
  'STRIPE_MERCHANT_IDENTIFIER',
);
const String _stripeUrlScheme = String.fromEnvironment('STRIPE_URL_SCHEME');

final Set<String> _runningGuestMigrations = <String>{};

Future<void> _runGuestMigrationAfterAuth({required String userUid}) async {
  final uid = userUid.trim();
  if (uid.isEmpty) return;
  if (_runningGuestMigrations.contains(uid)) return;

  _runningGuestMigrations.add(uid);
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = 'guest_migrated_to_$uid';
    if (prefs.getBool(key) == true) return;

    final guestUid = await GuestUidService.getOrCreate();
    if (guestUid.trim().isEmpty || guestUid.trim() == uid) {
      await prefs.setBool(key, true);
      return;
    }

    final testMode = await AppMode.isTestProfileEnabled();
    await GuestMigrationService.migrate(
      db: FirebaseFirestore.instance,
      guestUid: guestUid,
      userUid: uid,
      testMode: testMode,
    );
    await prefs.setBool(key, true);
  } catch (e, st) {
    m.debugPrint('guest migration failed for user=$uid: $e');
    m.debugPrint('$st');
  } finally {
    _runningGuestMigrations.remove(uid);
  }
}

Future<void> main() async {
  m.WidgetsFlutterBinding.ensureInitialized();
  final env = AppEnv.current;
  final firebaseOptions = DefaultFirebaseOptions.currentPlatform(env);
  if (kDebugMode) {
    m.debugPrint('[env] APP_ENV=$env projectId=${firebaseOptions.projectId}');
  }
  if (env.isDev && firebaseOptions.projectId.startsWith('TODO')) {
    m.runApp(
      _MissingDevConfigScreen(env: env, projectId: firebaseOptions.projectId),
    );
    return;
  }
  await Firebase.initializeApp(options: firebaseOptions);
  // Always log active Firebase environment.
  // Safe: does not change behavior, only reports.
  m.debugPrint(
    '[env] ${{'env': env.name, 'projectId': Firebase.app().options.projectId}}',
  );
  if (env.isDev && Firebase.app().options.projectId == 'worka-416c0') {
    m.runApp(const _ProdInDevBlockerScreen());
    return;
  }
  if (kIsWeb) {
    try {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      if (kDebugMode) {
        m.debugPrint('FirebaseAuth web persistence set to LOCAL');
      }
    } catch (e, st) {
      m.debugPrint('Failed to set FirebaseAuth web persistence: $e');
      m.debugPrint('$st');
    }
  }
  await AppMode.init();
  AuthController.instance.init();
  AuthController.instance.registerResetter(
    'response_stats_service',
    ResponseStatsService.clearCaches,
  );
  AuthController.instance.registerResetter(
    'response_card',
    ResponseCard.clearCaches,
  );
  AuthController.instance.registerResetter(
    'my_cvs',
    MyCvsScreen.clearGlobalCaches,
  );
  AuthController.instance.registerResetter(
    'my_publications',
    MyPublicationsScreen.clearGlobalCaches,
  );
  final guestUid = await GuestUidService.getOrCreate();
  AuthGuard.setCachedGuestUid(guestUid);
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );
  await TestDataMigrationService.run(FirebaseFirestore.instance);
  await FirebaseDebugDiagnostics.debugWritePing();
  if (kDebugMode && kDebugBypassAuth) {
    m.debugPrint(
      'debug bypass auth is enabled (effectiveUid mode), anonymous sign-in disabled',
    );
  }
  FirebaseAuth.instance.authStateChanges().listen((u) {
    m.debugPrint(
      '[AUTH] onAuthStateChanged uid=${u?.uid} email=${u?.email} anon=${u?.isAnonymous}',
    );
    final uid = u?.uid.trim() ?? '';
    if (uid.isNotEmpty) {
      _runGuestMigrationAfterAuth(userUid: uid);
    }
  });
  if (kIsWeb) {
    m.debugPrint(
      'Stripe web init skipped: flutter_stripe native init is disabled on web.',
    );
  } else {
    final trimmedPublishable = publishableKey.trim();
    if (trimmedPublishable.isEmpty) {
      throw StateError(
        'Missing STRIPE_PUBLISHABLE_KEY. '
        'Run with --dart-define=STRIPE_PUBLISHABLE_KEY=pk_...',
      );
    }
    if (trimmedPublishable.isNotEmpty) {
      final normalizedEnv = _stripeEnv.trim().toLowerCase();
      final shouldRequireLiveKey =
          kReleaseMode || normalizedEnv == 'production';
      if (shouldRequireLiveKey && trimmedPublishable.startsWith('pk_test_')) {
        throw StateError(
          'Stripe publishable key is TEST key in production/release mode. '
          'Set --dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_... for production.',
        );
      }
      Stripe.publishableKey = trimmedPublishable;
      if (kReleaseMode && trimmedPublishable.startsWith('pk_test_')) {
        m.debugPrint(
          'WARNING: Release build is configured with Stripe TEST publishable key (pk_test_...).',
        );
      }
      if (!kReleaseMode && trimmedPublishable.startsWith('pk_live_')) {
        m.debugPrint(
          'WARNING: Non-release build is configured with Stripe LIVE publishable key (pk_live_...).',
        );
      }
      if (_stripeMerchantIdentifier.trim().isNotEmpty) {
        Stripe.merchantIdentifier = _stripeMerchantIdentifier.trim();
      } else if (kDebugMode) {
        m.debugPrint(
          'Stripe merchant identifier is empty. '
          'For iOS Apple Pay flows pass --dart-define=STRIPE_MERCHANT_IDENTIFIER=merchant....',
        );
      }
      if (_stripeUrlScheme.trim().isNotEmpty) {
        Stripe.urlScheme = _stripeUrlScheme.trim();
      } else if (kDebugMode) {
        m.debugPrint(
          'Stripe URL scheme is empty. '
          'Pass --dart-define=STRIPE_URL_SCHEME=your.app.scheme for return URL handling.',
        );
      }
      await Stripe.instance.applySettings();
      if (kDebugMode) {
        m.debugPrint(
          'Stripe client configured: '
          'publishableKey=present merchantIdentifier=${_stripeMerchantIdentifier.trim().isNotEmpty ? 'present' : 'missing'} '
          'urlScheme=${_stripeUrlScheme.trim().isNotEmpty ? 'present' : 'missing'}',
        );
      }
    }
  }
  m.runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(
          value: PaidEntitlementsController.instance,
        ),
        ChangeNotifierProvider.value(
          value: ContactAccessController.instance,
        ),
      ],
      child: const WorkaApp(),
    ),
  );
}

class _MissingDevConfigScreen extends m.StatelessWidget {
  const _MissingDevConfigScreen({required this.env, required this.projectId});

  final AppEnv env;
  final String projectId;

  @override
  m.Widget build(m.BuildContext context) {
    return m.MaterialApp(
      debugShowCheckedModeBanner: false,
      home: m.Scaffold(
        appBar: m.AppBar(title: const m.Text('Dev Firebase config is not set')),
        body: m.Padding(
          padding: const m.EdgeInsets.all(16),
          child: m.Column(
            crossAxisAlignment: m.CrossAxisAlignment.start,
            children: [
              const m.Text(
                'Replace TODO_* values in lib/firebase_options.dart with real non-production Firebase config.',
                style: m.TextStyle(fontSize: 16, fontWeight: m.FontWeight.w700),
              ),
              const m.SizedBox(height: 12),
              m.Text('Current env: $env'),
              m.Text('Current projectId: $projectId'),
              const m.SizedBox(height: 12),
              const m.Text(
                'To proceed:',
                style: m.TextStyle(fontWeight: m.FontWeight.w700),
              ),
              const m.Text(
                '1) Fill the dev block in lib/firebase_options.dart with a real non-prod Firebase project.',
              ),
              const m.Text(
                '2) Add matching dev google-services.json / GoogleService-Info.plist.',
              ),
              const m.SizedBox(height: 12),
              const m.Text(
                'If you must run against production, start the app with '
                '--dart-define=APP_ENV=prod (not recommended for day-to-day dev).',
                style: m.TextStyle(color: m.Colors.redAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProdInDevBlockerScreen extends m.StatelessWidget {
  const _ProdInDevBlockerScreen();

  @override
  m.Widget build(m.BuildContext context) {
    return m.MaterialApp(
      debugShowCheckedModeBanner: false,
      home: m.Scaffold(
        appBar: m.AppBar(
          title: const m.Text('You are using production Firebase in dev mode'),
          backgroundColor: m.Colors.redAccent,
        ),
        body: const m.Center(
          child: m.Padding(
            padding: m.EdgeInsets.all(16),
            child: m.Text(
              'APP_ENV=dev but Firebase projectId is worka-416c0 (production).\n'
              'Switch to a non-prod project or run with --dart-define=APP_ENV=prod if you truly need prod.',
              style: m.TextStyle(fontSize: 16, fontWeight: m.FontWeight.w700),
              textAlign: m.TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class WorkaApp extends m.StatelessWidget {
  const WorkaApp({super.key});

  @override
  m.Widget build(m.BuildContext context) {
    final base = m.ThemeData(
      useMaterial3: true,
      brightness: m.Brightness.light,
    );

    final baseTextTheme = base.textTheme.apply(
      fontFamily: 'Inter',
      bodyColor: const m.Color(0xFF111111),
      displayColor: const m.Color(0xFF111111),
    );
    final textTheme = baseTextTheme.copyWith(
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontWeight: m.FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontWeight: m.FontWeight.w600,
        letterSpacing: -0.1,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontWeight: m.FontWeight.w500,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontWeight: m.FontWeight.w400,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontWeight: m.FontWeight.w400,
        letterSpacing: 0.1,
      ),
    );

    final theme = base.copyWith(
      textTheme: textTheme,
      primaryColor: WorkaColors.primaryBlue,

      /// ✅ Глобальные поверхности из токенов WorkaColors
      scaffoldBackgroundColor: const m.Color(0xFF4A6FDB),
      canvasColor: WorkaColors.bg,
      cardColor: WorkaColors.surface,

      /// ✅ Dialog / BottomSheet / Dropdown / Menu — белые
      dialogTheme: const m.DialogThemeData(
        backgroundColor: m.Colors.white,
        surfaceTintColor: m.Colors.white,
      ),

      /// ✅ CardThemeData (а не CardTheme)
      cardTheme: m.CardThemeData(
        color: WorkaColors.surface,
        surfaceTintColor: WorkaColors.surface,
        shape: m.RoundedRectangleBorder(
          borderRadius: m.BorderRadius.circular(20),
        ),
        elevation: 0,
        shadowColor: m.Colors.black.withValues(alpha: 0.08),
      ),

      bottomSheetTheme: const m.BottomSheetThemeData(
        backgroundColor: m.Colors.white,
        surfaceTintColor: m.Colors.white,
      ),

      datePickerTheme: const m.DatePickerThemeData(
        backgroundColor: m.Colors.white,
        surfaceTintColor: m.Colors.white,
      ),

      colorScheme: base.colorScheme.copyWith(
        primary: WorkaColors.primaryBlue,
        secondary: WorkaColors.accentOrange,
        onPrimary: m.Colors.white,
        surface: WorkaColors.surface,
      ),

      popupMenuTheme: const m.PopupMenuThemeData(
        color: m.Colors.white,
        surfaceTintColor: m.Colors.white,
      ),

      /// ✅ Чтобы dropdown/menus не уходили в серый
      dropdownMenuTheme: const m.DropdownMenuThemeData(
        menuStyle: m.MenuStyle(
          backgroundColor: m.WidgetStatePropertyAll(m.Colors.white),
          surfaceTintColor: m.WidgetStatePropertyAll(m.Colors.white),
        ),
      ),

      inputDecorationTheme: m.InputDecorationTheme(
        filled: true,
        fillColor: WorkaColors.surface,
        contentPadding: const m.EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: m.OutlineInputBorder(
          borderRadius: m.BorderRadius.circular(16),
          borderSide: const m.BorderSide(color: WorkaColors.border),
        ),
        enabledBorder: m.OutlineInputBorder(
          borderRadius: m.BorderRadius.circular(16),
          borderSide: const m.BorderSide(color: WorkaColors.border),
        ),
        focusedBorder: m.OutlineInputBorder(
          borderRadius: m.BorderRadius.circular(16),
          borderSide: const m.BorderSide(
            color: WorkaColors.primaryBlue,
            width: 2,
          ),
        ),
      ),

      /// ✅ Hover оставить СИЛЬНЫМ синим (как ты просила)
      hoverColor: WorkaColors.hoverBlue,
      splashColor: WorkaColors.hoverBlue,
      highlightColor: WorkaColors.hoverBlue,

      /// ✅ Линии/бордеры как у тебя
      dividerColor: WorkaColors.divider,
      switchTheme: m.SwitchThemeData(
        trackColor: m.WidgetStateProperty.resolveWith((states) {
          if (states.contains(m.WidgetState.selected)) {
            return WorkaColors.blue.withValues(alpha: 0.45);
          }
          return const m.Color(0xFFDADADA);
        }),
        thumbColor: m.WidgetStateProperty.resolveWith((states) {
          if (states.contains(m.WidgetState.selected)) return m.Colors.white;
          return const m.Color(0xFFBDBDBD);
        }),
        trackOutlineColor: m.WidgetStateProperty.resolveWith((states) {
          if (states.contains(m.WidgetState.selected)) {
            return WorkaColors.blue.withValues(alpha: 0.6);
          }
          return const m.Color(0xFFCFCFCF);
        }),
      ),
    );

    return m.MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        m.Locale('ru', 'RU'),
        m.Locale('en', 'US'),
        m.Locale('et', 'EE'),
      ],
      locale: const m.Locale('ru', 'RU'),
      routes: {
        '/welcome': (_) => const WelcomeScreen(),
        '/new-response': (_) => const NewResponseScreen(),
        '/payments/success': (_) => const PaymentSuccessScreen(),
        '/payments/cancel': (_) => const PaymentCancelScreen(),
        PaymentsRoutes.wallet: (_) => const CreditsWalletScreen(),
        PaymentsRoutes.verificationPaywall: (_) =>
            const VerifiedEmployerPaywallScreen(),
        PaymentsRoutes.verificationUpload: (_) =>
            const VerificationUploadScreen(),
        PaymentsRoutes.verificationStatus: (_) =>
            const VerificationStatusScreen(),
        MonetizationRoutes.workerBoostProfile: (_) =>
            const BoostProfilePaywallScreen(),
        MonetizationRoutes.workerPlans: (_) => const WorkerPlansScreen(),
        MonetizationRoutes.employerPlans: (_) => const PrivatePlansScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == PaymentsRoutes.promoteJob) {
          final args = (settings.arguments is Map)
              ? Map<String, dynamic>.from(settings.arguments as Map)
              : <String, dynamic>{};
          final jobId = (args['jobId'] ?? '').toString().trim();
          return m.MaterialPageRoute(
            builder: (_) => PromoteJobScreen(jobCode: jobId),
            settings: settings,
          );
        }
        return null;
      },
      navigatorObservers: [LoggingRouteObserver()],
      home: const AuthGate(),
    );
  }
}

class LoggingRouteObserver extends m.RouteObserver<m.PageRoute<dynamic>> {
  LoggingRouteObserver();

  void _log(String action, m.Route<dynamic>? route) {
    final name =
        route?.settings.name ?? route?.runtimeType.toString() ?? '<anon>';
    m.debugPrint('[NAV] route $action $name');
  }

  @override
  void didPush(m.Route<dynamic> route, m.Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _log('push', route);
  }

  @override
  void didReplace({m.Route<dynamic>? newRoute, m.Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _log('replace', newRoute);
  }

  @override
  void didPop(m.Route<dynamic> route, m.Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _log('pop->', previousRoute);
  }
}
