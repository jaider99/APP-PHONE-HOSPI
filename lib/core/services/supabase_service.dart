import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hospi_dash/core/config/env_config.dart';

/// Singleton service for Supabase client initialization and access
class SupabaseService {
  SupabaseService._();

  static SupabaseClient? _client;

  /// Get the Supabase client instance
  /// Throws if not initialized
  static SupabaseClient get client {
    if (_client == null) {
      throw StateError(
        'SupabaseService not initialized. Call initialize() first.',
      );
    }
    return _client!;
  }

  /// Check if Supabase is initialized
  static bool get isInitialized => _client != null;

  /// Initialize Supabase with environment configuration
  static Future<void> initialize() async {
    if (_client != null) return;

    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      anonKey: EnvConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
    );

    _client = Supabase.instance.client;
  }

  /// Get the current authenticated user
  static User? get currentUser => _client?.auth.currentUser;

  /// Check if a user is authenticated
  static bool get isAuthenticated => currentUser != null;

  /// Get the current session
  static Session? get currentSession => _client?.auth.currentSession;

  /// Listen to auth state changes
  static Stream<AuthState> get authStateChanges =>
      _client?.auth.onAuthStateChange ?? const Stream.empty();
}
