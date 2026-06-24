import 'package:flutter/foundation.dart';

/// Environment types for the application
enum Environment {
  development,
  staging,
  production,
}

class EnvConfigException implements Exception {
  const EnvConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Environment configuration singleton
/// Handles secure configuration for different environments
class EnvConfig {
  EnvConfig._();

  static late Environment _environment;
  static late String _supabaseUrl;
  static late String _supabaseAnonKey;
  static late String _apiBaseUrl;

  static Environment get environment => _environment;
  static String get supabaseUrl => _supabaseUrl;
  static String get supabaseAnonKey => _supabaseAnonKey;
  static String get apiBaseUrl => _apiBaseUrl;

  static bool get isDevelopment => _environment == Environment.development;
  static bool get isStaging => _environment == Environment.staging;
  static bool get isProduction => _environment == Environment.production;

  static bool get hasSupabaseUrl => _supabaseUrlDefine.trim().isNotEmpty;
  static bool get hasSupabaseAnonKey =>
      _supabaseAnonKeyDefine.trim().isNotEmpty;

  static const _appEnvDefine = String.fromEnvironment('APP_ENV');
  static const _supabaseUrlDefine = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseAnonKeyDefine =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static Future<void> initializeFromEnvironment() async {
    await initialize(_resolveEnvironment(_appEnvDefine));
  }

  /// Initialize environment configuration
  /// In production, use --dart-define or a secure secrets manager
  static Future<void> initialize(Environment env) async {
    _environment = env;

    switch (env) {
      case Environment.development:
        _supabaseUrl = _supabaseUrlDefine;
        _supabaseAnonKey = _supabaseAnonKeyDefine;
        _apiBaseUrl = 'https://dev-api.hospidash.com';

      case Environment.staging:
        _supabaseUrl = _supabaseUrlDefine;
        _supabaseAnonKey = _supabaseAnonKeyDefine;
        _apiBaseUrl = 'https://staging-api.hospidash.com';

      case Environment.production:
        _supabaseUrl = _supabaseUrlDefine;
        _supabaseAnonKey = _supabaseAnonKeyDefine;
        _apiBaseUrl = 'https://api.hospidash.com';
    }

    _validate();
  }

  static Environment _resolveEnvironment(String rawValue) {
    final value = rawValue.trim().toLowerCase();
    if (value.isEmpty) {
      if (kReleaseMode) {
        throw const EnvConfigException(
          'APP_ENV is required for release builds. Use APP_ENV=staging or APP_ENV=production.',
        );
      }
      return Environment.development;
    }

    final env = switch (value) {
      'development' || 'dev' => Environment.development,
      'staging' || 'stage' => Environment.staging,
      'production' || 'prod' => Environment.production,
      _ => throw EnvConfigException(
          'Unsupported APP_ENV "$rawValue". Use development, staging, or production.',
        ),
    };

    if (kReleaseMode && env == Environment.development) {
      throw const EnvConfigException(
        'Release builds cannot run with APP_ENV=development.',
      );
    }

    return env;
  }

  static void _validate() {
    _requireDefine('SUPABASE_URL', _supabaseUrl);
    _requireDefine('SUPABASE_ANON_KEY', _supabaseAnonKey);
    _rejectPlaceholderDefine('SUPABASE_URL', _supabaseUrl);
    _rejectPlaceholderDefine('SUPABASE_ANON_KEY', _supabaseAnonKey);

    final uri = Uri.tryParse(_supabaseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const EnvConfigException(
        'SUPABASE_URL must be a valid absolute URL.',
      );
    }

    if (!isDevelopment && uri.scheme != 'https') {
      throw const EnvConfigException(
        'SUPABASE_URL must use HTTPS outside development.',
      );
    }

    if (_supabaseAnonKey.length < 64) {
      throw const EnvConfigException(
        'SUPABASE_ANON_KEY is missing or too short.',
      );
    }

    if (_supabaseAnonKey.toLowerCase().contains('service_role')) {
      throw const EnvConfigException(
        'SUPABASE_ANON_KEY must not contain a service-role key.',
      );
    }
  }

  static void _requireDefine(String name, String value) {
    if (value.trim().isEmpty) {
      throw EnvConfigException(
        'Missing $name.\nRun with:\nflutter run --dart-define-from-file=env/dev.json',
      );
    }
  }

  static void _rejectPlaceholderDefine(String name, String value) {
    final normalizedValue = value.trim().toLowerCase();
    final hasPlaceholder = normalizedValue.contains('your-project') ||
        normalizedValue.contains('your_supabase_anon_key') ||
        normalizedValue.contains('your-supabase-anon-key') ||
        normalizedValue.contains('your-anon-key');

    if (hasPlaceholder) {
      throw EnvConfigException(
        '$name still contains a placeholder value.\nUpdate env/dev.json with your real Supabase project URL and anon key, then run:\nflutter run --dart-define-from-file=env/dev.json',
      );
    }
  }
}
