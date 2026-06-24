import 'package:hospi_dash/core/config/env_config.dart';
import 'package:logger/logger.dart';

/// Application-wide logger
/// Provides consistent logging across the app
class AppLogger {
  AppLogger._();

  static final RegExp _bearerTokenPattern = RegExp(
    r'Bearer\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final RegExp _jwtPattern = RegExp(
    r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',
  );
  static final RegExp _urlPattern = RegExp(r'https?:\/\/\S+');
  static final RegExp _uuidPattern = RegExp(
    r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
  );
  static final RegExp _storagePathPattern = RegExp(
    r'\b[0-9a-fA-F-]{36}\/[0-9a-fA-F-]{36}\/[^\s]+',
  );

  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 80,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    level: EnvConfig.isProduction ? Level.warning : Level.trace,
  );

  /// Log debug message (development only)
  static void debug(String message, {dynamic error, StackTrace? stackTrace}) {
    _logger.d(_redact(message), error: _redactError(error), stackTrace: stackTrace);
  }

  /// Log info message
  static void info(String message, {dynamic error, StackTrace? stackTrace}) {
    _logger.i(_redact(message), error: _redactError(error), stackTrace: stackTrace);
  }

  /// Log warning message
  static void warning(String message, {dynamic error, StackTrace? stackTrace}) {
    _logger.w(_redact(message), error: _redactError(error), stackTrace: stackTrace);
  }

  /// Log error message
  static void error(String message, {dynamic error, StackTrace? stackTrace}) {
    _logger.e(_redact(message), error: _redactError(error), stackTrace: stackTrace);
  }

  /// Log fatal error
  static void fatal(String message, {dynamic error, StackTrace? stackTrace}) {
    _logger.f(_redact(message), error: _redactError(error), stackTrace: stackTrace);
  }

  /// Log trace (very verbose, development only)
  static void trace(String message, {dynamic error, StackTrace? stackTrace}) {
    _logger.t(_redact(message), error: _redactError(error), stackTrace: stackTrace);
  }

  static String redact(String value) => _redact(value);

  static Object? _redactError(dynamic error) {
    if (error == null) return null;
    return _redact(error.toString());
  }

  static String _redact(String value) {
    return value
        .replaceAll(_bearerTokenPattern, 'Bearer [REDACTED]')
        .replaceAll(_jwtPattern, '[REDACTED_JWT]')
        .replaceAll(_urlPattern, '[REDACTED_URL]')
        .replaceAll(_storagePathPattern, '[REDACTED_STORAGE_PATH]')
        .replaceAll(_uuidPattern, '[REDACTED_ID]');
  }
}
