import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:hospi_dash/models/auth_result.dart';
import 'package:hospi_dash/models/auth_state.dart';
import 'package:hospi_dash/services/auth_service.dart';
import 'package:hospi_dash/services/biometric_service.dart';

const _biometricStartupTimeout = Duration(seconds: 3);

/// Provider for AuthService (singleton)
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// Provider for BiometricService (singleton)
final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

/// Provider for auth state notifier
final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// Convenience provider for checking authentication status
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authNotifierProvider);
  return authState.valueOrNull?.isAuthenticated ?? false;
});

/// Convenience provider for current user
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authNotifierProvider);
  return authState.valueOrNull?.user;
});

/// AsyncNotifier for managing authentication state
/// Handles all auth operations and updates state reactively
class AuthNotifier extends AsyncNotifier<AuthState> {
  late final AuthService _authService;
  late final BiometricService _biometricService;
  StreamSubscription<dynamic>? _authSubscription;

  @override
  Future<AuthState> build() async {
    _authService = ref.read(authServiceProvider);
    _biometricService = ref.read(biometricServiceProvider);

    // Subscribe to Supabase auth state changes
    _authSubscription = _authService.authStateChanges.listen(
      _handleAuthStateChange,
      onError: (error) {
        debugPrint('Auth state stream error: $error');
      },
    );

    // Clean up subscription when provider is disposed
    ref.onDispose(() {
      _authSubscription?.cancel();
    });

    // Check biometric availability
    final biometricsAvailable = await _biometricService
      .isBiometricAvailable()
      .timeout(_biometricStartupTimeout, onTimeout: () => false);
    final biometricsEnabled = await _biometricService
      .isBiometricsEnabled()
      .timeout(_biometricStartupTimeout, onTimeout: () => false);

    // Check current session
    final session = _authService.currentSession;
    final user = _authService.currentUser;

    if (session != null && user != null) {
      return AuthState.authenticated(
        user: user,
        session: session,
        biometricsAvailable: biometricsAvailable,
        biometricsEnabled: biometricsEnabled,
      );
    }

    return AuthState.unauthenticated(
      biometricsAvailable: biometricsAvailable,
      biometricsEnabled: biometricsEnabled,
    );
  }

  /// Handle Supabase auth state changes
  ///
  /// IMPORTANT: State must be set SYNCHRONOUSLY so that GoRouter's redirect
  /// (triggered by the same stream event) sees the correct auth state.
  /// Biometric info is updated asynchronously afterward.
  void _handleAuthStateChange(dynamic event) {
    final supabaseAuthState = event as dynamic;
    final session = supabaseAuthState.session as Session?;

    if (session != null) {
      state = AsyncData(AuthState.authenticated(
        user: session.user,
        session: session,
      ),);
    } else {
      state = AsyncData(AuthState.unauthenticated());
    }

    // Update biometric info in the background (non-blocking)
    _refreshBiometricState();
  }

  /// Refresh biometric availability/enabled state without blocking auth transitions
  Future<void> _refreshBiometricState() async {
    try {
        final biometricsAvailable = await _biometricService
          .isBiometricAvailable()
          .timeout(_biometricStartupTimeout, onTimeout: () => false);
        final biometricsEnabled = await _biometricService
          .isBiometricsEnabled()
          .timeout(_biometricStartupTimeout, onTimeout: () => false);
      final current = state.valueOrNull;
      if (current != null) {
        state = AsyncData(current.copyWith(
          biometricsAvailable: biometricsAvailable,
          biometricsEnabled: biometricsEnabled,
        ),);
      }
    } catch (_) {
      // Biometric check failure is non-critical
    }
  }

  // ===========================================================================
  // SIGN IN
  // ===========================================================================

  /// Sign in with email and password
  ///
  /// Sets state SYNCHRONOUSLY on success so GoRouter redirect works immediately.
  Future<AuthResult> signIn({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    state = const AsyncLoading();

    final result = await _authService.signInWithEmail(
      email: email,
      password: password,
      rememberMe: rememberMe,
    );

    switch (result) {
      case AuthSuccess(session: final session):
        state = AsyncData(AuthState.authenticated(
          user: session.user,
          session: session,
        ),);
        _refreshBiometricState();
      case AuthFailure(message: final message):
        state = AsyncData(AuthState.error(message));
      case AuthPendingVerification(email: final email):
        state = AsyncData(AuthState.pendingOtp(email: email));
    }

    return result;
  }

  /// Sign in with biometrics
  Future<AuthResult> signInWithBiometrics() async {
    state = const AsyncLoading();

    final result = await _biometricService.loginWithBiometrics();

    switch (result) {
      case AuthSuccess(session: final session):
        state = AsyncData(AuthState.authenticated(
          user: session.user,
          session: session,
          biometricsEnabled: true,
        ),);
        _refreshBiometricState();
      case AuthFailure(message: final message):
        state = AsyncData(AuthState.unauthenticated().copyWith(
          status: AuthStatus.error,
          errorMessage: message,
        ),);
        _refreshBiometricState();
      case AuthPendingVerification():
        break;
    }

    return result;
  }

  /// Sign in with Google OAuth
  Future<AuthResult> signInWithGoogle() async {
    state = const AsyncLoading();
    final result = await _authService.signInWithGoogle();
    // OAuth redirects to browser, session comes via stream
    return result;
  }

  /// Sign in with Apple OAuth
  Future<AuthResult> signInWithApple() async {
    state = const AsyncLoading();
    final result = await _authService.signInWithApple();
    // OAuth redirects to browser, session comes via stream
    return result;
  }

  // ===========================================================================
  // SIGN UP
  // ===========================================================================

  /// Sign up with email and password
  Future<AuthResult> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();

    final result = await _authService.signUpWithEmail(
      name: name,
      email: email,
      password: password,
    );

    final lastOtpSent = await _authService.getLastOtpSentAt();

    switch (result) {
      case AuthSuccess(session: final session):
        state = AsyncData(AuthState.authenticated(
          user: session.user,
          session: session,
        ),);
        _refreshBiometricState();
      case AuthFailure(message: final message):
        state = AsyncData(AuthState.error(message));
      case AuthPendingVerification(email: final pendingEmail):
        state = AsyncData(AuthState.pendingOtp(
          email: pendingEmail,
          lastOtpSentAt: lastOtpSent,
        ),);
    }

    return result;
  }

  // ===========================================================================
  // OTP VERIFICATION
  // ===========================================================================

  /// Verify OTP code
  Future<AuthResult> verifyOtp({
    required String email,
    required String token,
  }) async {
    state = const AsyncLoading();

    final result = await _authService.verifyOtp(
      email: email,
      token: token,
    );

    switch (result) {
      case AuthSuccess(session: final session):
        state = AsyncData(AuthState.authenticated(
          user: session.user,
          session: session,
        ),);
        _refreshBiometricState();
      case AuthFailure(message: final message):
        final currentState = state.valueOrNull;
        state = AsyncData(AuthState.pendingOtp(
          email: email,
          lastOtpSentAt: currentState?.lastOtpSentAt,
        ).copyWith(
          status: AuthStatus.error,
          errorMessage: message,
        ),);
      case AuthPendingVerification():
        break;
    }

    return result;
  }

  /// Resend OTP code
  Future<AuthResult> resendOtp(String email) async {
    final result = await _authService.resendOtp(email);
    final lastOtpSent = await _authService.getLastOtpSentAt();

    result.when(
      success: (_) {},
      failure: (message) {
        // Update state with error but keep pending OTP status
        state = AsyncData(AuthState.pendingOtp(
          email: email,
          lastOtpSentAt: lastOtpSent,
        ).copyWith(
          status: AuthStatus.error,
          errorMessage: message,
        ),);
      },
      pendingVerification: (_) {
        state = AsyncData(AuthState.pendingOtp(
          email: email,
          lastOtpSentAt: lastOtpSent,
        ),);
      },
    );

    return result;
  }

  // ===========================================================================
  // PASSWORD RESET
  // ===========================================================================

  /// Send password reset email
  Future<AuthResult> sendPasswordReset(String email) async {
    state = const AsyncLoading();

    final result = await _authService.sendPasswordReset(email);
    final lastOtpSent = await _authService.getLastOtpSentAt();

    result.when(
      success: (_) {},
      failure: (message) {
        state = AsyncData(AuthState.error(message));
      },
      pendingVerification: (email) {
        state = AsyncData(AuthState.pendingOtp(
          email: email,
          lastOtpSentAt: lastOtpSent,
        ),);
      },
    );

    return result;
  }

  // ===========================================================================
  // SIGN OUT
  // ===========================================================================

  /// Sign out
  Future<void> signOut() async {
    await _authService.signOut();
    await _biometricService.clearBiometricData();

    final biometricsAvailable = await _biometricService.isBiometricAvailable();

    state = AsyncData(AuthState.unauthenticated(
      biometricsAvailable: biometricsAvailable,
    ),);
  }

  // ===========================================================================
  // BIOMETRICS
  // ===========================================================================

  /// Enable biometric login
  Future<void> enableBiometrics() async {
    final currentState = state.valueOrNull;
    if (currentState?.session == null) return;

    await _biometricService.enableBiometrics(currentState!.session!);

    state = AsyncData(currentState.copyWith(biometricsEnabled: true));
  }

  /// Disable biometric login
  Future<void> disableBiometrics() async {
    await _biometricService.disableBiometrics();

    final currentState = state.valueOrNull;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(biometricsEnabled: false));
    }
  }

  /// Check if biometric prompt should be shown
  Future<bool> shouldShowBiometricPrompt() async {
    return _biometricService.shouldShowBiometricPrompt();
  }

  /// Check if biometrics are available
  Future<bool> isBiometricAvailable() async {
    return _biometricService.isBiometricAvailable();
  }

  /// Get biometric label (Face ID / Touch ID / Fingerprint)
  Future<String> getBiometricLabel() async {
    return _biometricService.getBiometricLabel();
  }

  // ===========================================================================
  // UTILITIES
  // ===========================================================================

  /// Clear any error state
  void clearError() {
    final currentState = state.valueOrNull;
    if (currentState != null && currentState.hasError) {
      state = AsyncData(currentState.copyWith(
        status: currentState.isPendingOtp
            ? AuthStatus.pendingOtp
            : AuthStatus.unauthenticated,
        clearError: true,
      ),);
    }
  }

  /// Get remembered email for auto-fill
  Future<String?> getRememberedEmail() async {
    return _authService.getRememberedEmail();
  }
}
