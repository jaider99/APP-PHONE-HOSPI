import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/bootstrap/bootstrap_error_app.dart';
import 'package:hospi_dash/core/config/env_config.dart';
import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/theme/app_theme.dart';
import 'package:hospi_dash/core/utils/app_logger.dart';
import 'package:hospi_dash/services/storage_service.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      if (_isRetryableSupabaseNetworkError(details.exception)) {
        debugPrint(
          '[AUTH][network] Suppressed transient auth error: ${details.exception}',
        );
        return;
      }
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      if (_isRetryableSupabaseNetworkError(error)) {
        debugPrint('[AUTH][network] Suppressed transient auth error: $error');
        return true;
      }
      return false;
    };

    if (kDebugMode) {
      debugPrint('[BOOT] Starting app');
    }

    try {
      if (kDebugMode) {
        debugPrint('[BOOT] Loading environment config');
        debugPrint('[BOOT] SUPABASE_URL present: ${EnvConfig.hasSupabaseUrl}');
        debugPrint(
          '[BOOT] SUPABASE_ANON_KEY present: ${EnvConfig.hasSupabaseAnonKey}',
        );
      }

      await EnvConfig.initializeFromEnvironment();

      if (kDebugMode) {
        debugPrint('[BOOT] Initializing Supabase');
      }

      await SupabaseService.initialize();

      if (kDebugMode) {
        final session = SupabaseService.currentSession;
        debugPrint('[BOOT] Supabase initialized');
        debugPrint('[BOOT] Supabase ready. Session exists: ${session != null}');
      }

      if (kDebugMode) {
        debugPrint('[BOOT] before runApp');
      }

      runApp(
        const ProviderScope(
          child: HospiDashApp(),
        ),
      );

      if (kDebugMode) {
        debugPrint('[BOOT] after runApp');
      }

      _startDeferredStartupChecks();
    } catch (error, stackTrace) {
      debugPrint('[BOOT ERROR] $error');
      debugPrintStack(stackTrace: stackTrace);

      runApp(
        BootstrapErrorApp(
          error: error.toString(),
        ),
      );
    }
  }, (error, stackTrace) {
    if (_isRetryableSupabaseNetworkError(error)) {
      debugPrint('[AUTH][network] Suppressed transient auth error: $error');
      return;
    }

    debugPrint('[UNHANDLED ERROR] $error');
    debugPrintStack(stackTrace: stackTrace);
  });
}

void _startDeferredStartupChecks() {
  if (!EnvConfig.isDevelopment) return;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (kDebugMode) {
      debugPrint('[BOOT] before deferred verifyStorageConfig');
    }

    unawaited(
      StorageService()
          .verifyStorageConfig()
          .then((result) {
        if (kDebugMode) {
          debugPrint(
            '[BOOT] after deferred verifyStorageConfig status=${result.status.name}'
            '${result.stage == null ? '' : ' stage=${result.stage}'}',
          );
        }
      }).catchError((Object error, StackTrace stackTrace) {
        AppLogger.info(
          '[BOOT] Storage health check skipped; uploads will validate storage on demand.',
          error: error,
        );
      }),
    );
  });
}

class HospiDashApp extends ConsumerWidget {
  const HospiDashApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'HospiDash',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}

bool _isRetryableSupabaseNetworkError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('authretryablefetchexception') &&
      (message.contains('failed host lookup') ||
          message.contains('socketexception') ||
          message.contains('errno = 7') ||
          message.contains('no address associated with hostname'));
}
