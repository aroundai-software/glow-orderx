import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'core/db_init.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/offline_data_provider.dart';
import 'providers/offline_status_provider.dart';
import 'screens/auth/company_key_screen.dart';
import 'screens/auth/email_registration_screen.dart';
import 'screens/auth/email_otp_verification_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/password_reset_screen.dart';
import 'screens/auth/mobile_login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/salesman/salesman_dashboard.dart';

void main() async {
  // Wrap everything in runZonedGuarded to catch async errors
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Set up Flutter framework error handler
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _logError(
        'FlutterError',
        details.exception,
        details.stack,
        details.context?.toDescription(),
      );
    };

    // Handle errors in the presentation layer (e.g. during build)
    if (kDebugMode) {
      // In debug mode, also log to console with full details
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.dumpErrorToConsole(details);
        _logError(
          'FlutterError',
          details.exception,
          details.stack,
          details.context?.toDescription(),
        );
      };
    }

    await initDbForPlatform();

    try {
      // Initialize Supabase
      await Supabase.initialize(
        url: 'https://ebtarbistoxwtfegdyau.supabase.co',
        anonKey:'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVidGFyYmlzdG94d3RmZWdkeWF1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAxNDk5MjgsImV4cCI6MjEwNTcyNTkyOH0.GXAOE4OJRljQuxjq3IHbRQdIVdLPhTUA9zSF-hgMVQ0',
      );

      print('✅ Supabase initialized successfully');
    } catch (e, stack) {
      print('❌ Supabase initialization error: $e');
      _logError('SupabaseInitError', e, stack, 'During Supabase.initialize');
    }

    runApp(const MyApp());
  }, (error, stackTrace) {
    // This catches all uncaught async errors
    _logError('UncaughtAsyncError', error, stackTrace, null);
  });
}

/// Logs errors to console and optionally to Supabase for remote debugging.
/// This helps diagnose crashes on devices where ADB is not available.
void _logError(
  String errorType,
  Object error,
  StackTrace? stackTrace,
  String? context,
) {
  final timestamp = DateTime.now().toIso8601String();
  final errorMessage = error.toString();
  final stackString = stackTrace?.toString() ?? 'No stack trace';

  // Always log to console
  print('');
  print('═══════════════════════════════════════════════════════════');
  print('🚨 [$errorType] Error caught at $timestamp');
  if (context != null) {
    print('📍 Context: $context');
  }
  print('❌ Error: $errorMessage');
  print('📚 Stack trace:');
  print(stackString.split('\n').take(15).join('\n')); // First 15 lines
  print('═══════════════════════════════════════════════════════════');
  print('');

  // Optionally log to Supabase for remote debugging (fire-and-forget)
  _logErrorToSupabase(errorType, errorMessage, stackString, context, timestamp);
}

/// Attempts to log the error to Supabase sync_queue table for remote viewing.
/// This is fire-and-forget - we don't await it to avoid blocking the app.
Future<void> _logErrorToSupabase(
  String errorType,
  String errorMessage,
  String stackTrace,
  String? context,
  String timestamp,
) async {
  // Skip logging during hot restarts or if Supabase not ready
  try {
    final client = Supabase.instance.client;

    // Use upsert with a conflict resolution to avoid duplicate key issues
    await client.from('sync_queue').insert({
      'action': 'error_log',
      'status': 'logged',
      'payload': {
        'error_type': errorType,
        'error_message': errorMessage.length > 1000
            ? errorMessage.substring(0, 1000)
            : errorMessage,
        'stack_trace': stackTrace.length > 2000
            ? stackTrace.substring(0, 2000)
            : stackTrace,
        'context': context,
        'timestamp': timestamp,
        'platform': kIsWeb ? 'web' : 'mobile',
      },
    });
    print('📤 Error logged to Supabase sync_queue');
  } catch (e) {
    // Silently fail - we don't want error logging to cause more errors
    // During hot restarts on web, Supabase client can be in invalid state
    if (kDebugMode) {
      print(
          '⚠️ Failed to log error to Supabase (expected during hot restart): $e');
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => OfflineDataProvider()),
        ChangeNotifierProvider(create: (_) => OfflineStatusProvider()),
      ],
      child: MaterialApp(
        title: 'Orderx',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const AuthWrapper(),
        routes: {
          '/register': (context) => const RegisterScreen(),
          '/email-register': (context) => const EmailRegistrationScreen(),
          '/mobile-login': (context) => const MobileLoginScreen(),
          '/enter-company-key': (context) => const CompanyKeyScreen(),
          '/forgot-password': (context) => const ForgotPasswordScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name == '/email-otp-verification') {
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (context) => EmailOtpVerificationScreen(
                email: args['email'],
                userId: args['userId'],
                verificationType: args['verificationType'],
              ),
            );
          } else if (settings.name == '/reset-password') {
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (context) => PasswordResetScreen(
                userId: args['userId'],
                email: args['email'],
              ),
            );
          }
          return null;
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (authProvider.isLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        print(
            '🏠 AuthWrapper: currentUser=${authProvider.currentUser?.name}, companyId=${authProvider.selectedCompanyId}, isOffline=${authProvider.isOfflineMode}');

        if (authProvider.currentUser == null) {
          if (authProvider.selectedCompanyId == null) {
            return const CompanyKeyScreen();
          }
          return const MobileLoginScreen();
        }

        // Route based on user type
        if (authProvider.currentUser!.userType == 'admin') {
          return const AdminDashboard();
        } else {
          return const SalesmanDashboard();
        }
      },
    );
  }
}
