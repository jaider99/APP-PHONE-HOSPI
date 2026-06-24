import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Enum representing different authentication status states
enum AuthStatus {
  /// Initial state before auth check
  initial,

  /// User is authenticated with valid session
  authenticated,

  /// User is not authenticated
  unauthenticated,

  /// OTP verification is pending
  pendingOtp,

  /// Auth operation is in progress
  loading,

  /// Auth operation resulted in an error
  error,
}

/// Immutable state class for authentication
class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.session,
    this.errorMessage,
    this.biometricsAvailable = false,
    this.biometricsEnabled = false,
    this.pendingEmail,
    this.lastOtpSentAt,
  });

  /// Current authentication status
  final AuthStatus status;

  /// Currently authenticated user (null if unauthenticated)
  final User? user;

  /// Current active session (null if unauthenticated)
  final Session? session;

  /// Error message if status is error
  final String? errorMessage;

  /// Whether biometric authentication is available on device
  final bool biometricsAvailable;

  /// Whether user has enabled biometric login
  final bool biometricsEnabled;

  /// Email pending OTP verification (for sign up flow)
  final String? pendingEmail;

  /// Timestamp of last OTP sent (for cooldown)
  final DateTime? lastOtpSentAt;

  /// Initial state factory
  factory AuthState.initial() => const AuthState();

  /// Loading state factory
  factory AuthState.loading() => const AuthState(status: AuthStatus.loading);

  /// Authenticated state factory
  factory AuthState.authenticated({
    required User user,
    required Session session,
    bool biometricsAvailable = false,
    bool biometricsEnabled = false,
  }) =>
      AuthState(
        status: AuthStatus.authenticated,
        user: user,
        session: session,
        biometricsAvailable: biometricsAvailable,
        biometricsEnabled: biometricsEnabled,
      );

  /// Unauthenticated state factory
  factory AuthState.unauthenticated({
    bool biometricsAvailable = false,
    bool biometricsEnabled = false,
  }) =>
      AuthState(
        status: AuthStatus.unauthenticated,
        biometricsAvailable: biometricsAvailable,
        biometricsEnabled: biometricsEnabled,
      );

  /// Pending OTP state factory
  factory AuthState.pendingOtp({
    required String email,
    DateTime? lastOtpSentAt,
  }) =>
      AuthState(
        status: AuthStatus.pendingOtp,
        pendingEmail: email,
        lastOtpSentAt: lastOtpSentAt ?? DateTime.now(),
      );

  /// Error state factory
  factory AuthState.error(String message) => AuthState(
        status: AuthStatus.error,
        errorMessage: message,
      );

  /// Check if user is authenticated
  bool get isAuthenticated => status == AuthStatus.authenticated;

  /// Check if auth is loading
  bool get isLoading => status == AuthStatus.loading;

  /// Check if there's an error
  bool get hasError => status == AuthStatus.error;

  /// Check if OTP is pending
  bool get isPendingOtp => status == AuthStatus.pendingOtp;

  /// Check if OTP can be resent (60 second cooldown)
  bool get canResendOtp {
    if (lastOtpSentAt == null) return true;
    return DateTime.now().difference(lastOtpSentAt!).inSeconds >= 60;
  }

  /// Seconds remaining until OTP can be resent
  int get otpCooldownRemaining {
    if (lastOtpSentAt == null) return 0;
    final elapsed = DateTime.now().difference(lastOtpSentAt!).inSeconds;
    return (60 - elapsed).clamp(0, 60);
  }

  /// Create a copy with updated fields
  AuthState copyWith({
    AuthStatus? status,
    User? user,
    Session? session,
    String? errorMessage,
    bool? biometricsAvailable,
    bool? biometricsEnabled,
    String? pendingEmail,
    DateTime? lastOtpSentAt,
    bool clearError = false,
    bool clearUser = false,
    bool clearPendingEmail = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      session: clearUser ? null : (session ?? this.session),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      biometricsAvailable: biometricsAvailable ?? this.biometricsAvailable,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      pendingEmail:
          clearPendingEmail ? null : (pendingEmail ?? this.pendingEmail),
      lastOtpSentAt: lastOtpSentAt ?? this.lastOtpSentAt,
    );
  }

  @override
  List<Object?> get props => [
        status,
        user?.id,
        session?.accessToken,
        errorMessage,
        biometricsAvailable,
        biometricsEnabled,
        pendingEmail,
        lastOtpSentAt,
      ];

  @override
  String toString() => 'AuthState(status: $status, userId: ${user?.id})';
}
