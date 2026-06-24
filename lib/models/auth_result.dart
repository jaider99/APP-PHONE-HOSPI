import 'package:supabase_flutter/supabase_flutter.dart';

/// Sealed class representing the result of an authentication operation.
/// Uses Dart 3 sealed classes for exhaustive pattern matching.
sealed class AuthResult {
  const AuthResult();

  /// Authentication succeeded with a valid session
  const factory AuthResult.success(Session session) = AuthSuccess;

  /// Authentication failed with an error message
  const factory AuthResult.failure(String message) = AuthFailure;

  /// Email verification is pending (sign up flow)
  const factory AuthResult.pendingVerification(String email) =
      AuthPendingVerification;

  /// Check if the result is successful
  bool get isSuccess => this is AuthSuccess;

  /// Check if the result is a failure
  bool get isFailure => this is AuthFailure;

  /// Check if verification is pending
  bool get isPending => this is AuthPendingVerification;

  /// Get the session if successful, null otherwise
  Session? get session => switch (this) {
        AuthSuccess(session: final s) => s,
        _ => null,
      };

  /// Get the error message if failed, null otherwise
  String? get errorMessage => switch (this) {
        AuthFailure(message: final m) => m,
        _ => null,
      };

  /// Execute callbacks based on result type
  T when<T>({
    required T Function(Session session) success,
    required T Function(String message) failure,
    required T Function(String email) pendingVerification,
  }) {
    return switch (this) {
      AuthSuccess(session: final s) => success(s),
      AuthFailure(message: final m) => failure(m),
      AuthPendingVerification(email: final e) => pendingVerification(e),
    };
  }

  /// Execute callback only on success
  void onSuccess(void Function(Session session) callback) {
    if (this case AuthSuccess(session: final s)) {
      callback(s);
    }
  }

  /// Execute callback only on failure
  void onFailure(void Function(String message) callback) {
    if (this case AuthFailure(message: final m)) {
      callback(m);
    }
  }
}

/// Successful authentication result containing the session
final class AuthSuccess extends AuthResult {
  const AuthSuccess(this.session);

  @override
  final Session session;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthSuccess &&
          runtimeType == other.runtimeType &&
          session.accessToken == other.session.accessToken;

  @override
  int get hashCode => session.accessToken.hashCode;

  @override
  String toString() => 'AuthSuccess(userId: ${session.user.id})';
}

/// Failed authentication result containing an error message
final class AuthFailure extends AuthResult {
  const AuthFailure(this.message);

  @override
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthFailure &&
          runtimeType == other.runtimeType &&
          message == other.message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'AuthFailure(message: $message)';
}

/// Pending verification result (email confirmation required)
final class AuthPendingVerification extends AuthResult {
  const AuthPendingVerification(this.email);

  final String email;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthPendingVerification &&
          runtimeType == other.runtimeType &&
          email == other.email;

  @override
  int get hashCode => email.hashCode;

  @override
  String toString() => 'AuthPendingVerification(email: $email)';
}

/// Helper extension to map Supabase error codes to user-friendly messages
extension AuthErrorMapper on AuthException {
  String get userFriendlyMessage {
    final code = message.toLowerCase();

    if (code.contains('invalid_credentials') ||
        code.contains('invalid login credentials')) {
      return 'Email or password is incorrect.';
    }
    if (code.contains('email_not_confirmed') ||
        code.contains('email not confirmed')) {
      return 'Please verify your email first.';
    }
    if (code.contains('too_many_requests') ||
        code.contains('rate limit')) {
      return 'Too many attempts. Try again later.';
    }
    if (code.contains('user_already_exists') ||
        code.contains('already registered')) {
      return 'An account with this email already exists.';
    }
    if (code.contains('weak_password')) {
      return 'Password is too weak. Use at least 6 characters.';
    }
    if (code.contains('invalid_email')) {
      return 'Please enter a valid email address.';
    }
    if (code.contains('session_expired') ||
        code.contains('refresh_token')) {
      return 'Your session has expired. Please sign in again.';
    }

    return 'Sign in failed. Please try again.';
  }
}
