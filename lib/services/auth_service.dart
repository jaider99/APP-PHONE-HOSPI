import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/models/auth_result.dart';

// ============================================================================
// SUPABASE SCHEMA NOTE - Run in Supabase SQL Editor:
//
// -- Table: profiles
// CREATE TABLE public.profiles (
//   id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
//   full_name TEXT,
//   avatar_url TEXT,
//   created_at TIMESTAMPTZ DEFAULT NOW(),
//   updated_at TIMESTAMPTZ DEFAULT NOW()
// );
//
// -- Enable RLS
// ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
//
// -- RLS Policies
// CREATE POLICY "Users can view own profile" ON public.profiles
//   FOR SELECT USING (auth.uid() = id);
// CREATE POLICY "Users can insert own profile" ON public.profiles
//   FOR INSERT WITH CHECK (auth.uid() = id);
// CREATE POLICY "Users can update own profile" ON public.profiles
//   FOR UPDATE USING (auth.uid() = id);
//
// -- Auto-create profile trigger
// CREATE OR REPLACE FUNCTION public.handle_new_user()
// RETURNS trigger AS $$
// BEGIN
//   INSERT INTO public.profiles (id, full_name)
//   VALUES (new.id, new.raw_user_meta_data->>'full_name');
//   RETURN new;
// END;
// $$ LANGUAGE plpgsql SECURITY DEFINER;
//
// CREATE TRIGGER on_auth_user_created
//   AFTER INSERT ON auth.users
//   FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
// ============================================================================

/// Storage keys for authentication data
abstract class _AuthStorageKeys {
  static const String refreshToken = 'auth_refresh_token';
  static const String rememberMe = 'auth_remember_me';
  static const String lastEmail = 'auth_last_email';
  static const String lastOtpSent = 'auth_last_otp_sent';
}

/// Deep link redirect URLs for OAuth
abstract class _AuthRedirects {
  static const String loginCallback = 'io.hospidash.app://login-callback';
  static const String resetPassword = 'io.hospidash.app://reset-password';
}

/// Pure Dart authentication service - no Riverpod dependencies
/// Handles all Supabase auth operations and secure token storage
class AuthService {
  AuthService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _secureStorage;
  SharedPreferences? _prefs;

  /// Get Supabase client
  SupabaseClient get _supabase => SupabaseService.client;

  /// Lazily initialize SharedPreferences
  Future<SharedPreferences> get _sharedPrefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Stream of auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Current user
  User? get currentUser => _supabase.auth.currentUser;

  /// Current session
  Session? get currentSession => _supabase.auth.currentSession;

  /// Check if user is authenticated
  bool get isAuthenticated => currentUser != null;

  // ===========================================================================
  // EMAIL/PASSWORD SIGN IN
  // ===========================================================================

  /// Sign in with email and password
  /// Optionally persists session if [rememberMe] is true
  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.session == null) {
        return const AuthResult.failure('Sign in failed. Please try again.');
      }

      // Store preferences
      final prefs = await _sharedPrefs;
      await prefs.setBool(_AuthStorageKeys.rememberMe, rememberMe);

      if (rememberMe) {
        await prefs.setString(_AuthStorageKeys.lastEmail, email);
      }

      // Store refresh token securely for biometric re-auth
      if (response.session!.refreshToken != null) {
        await _secureStorage.write(
          key: _AuthStorageKeys.refreshToken,
          value: response.session!.refreshToken,
        );
      }

      return AuthResult.success(response.session!);
    } on AuthException catch (e) {
      return AuthResult.failure(e.userFriendlyMessage);
    } catch (e) {
      debugPrint('Sign in error: $e');
      return const AuthResult.failure('Sign in failed. Please try again.');
    }
  }

  // ===========================================================================
  // EMAIL/PASSWORD SIGN UP
  // ===========================================================================

  /// Sign up with email and password
  /// Returns pending verification status on success
  Future<AuthResult> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name},
      );

      // Check if user needs email confirmation
      if (response.user != null && response.session == null) {
        // User created but needs email verification
        await _recordOtpSent(email);
        return AuthResult.pendingVerification(email);
      }

      // If session exists, user is auto-confirmed (e.g., development mode)
      if (response.session != null) {
        return AuthResult.success(response.session!);
      }

      return AuthResult.pendingVerification(email);
    } on AuthException catch (e) {
      return AuthResult.failure(e.userFriendlyMessage);
    } catch (e) {
      debugPrint('Sign up error: $e');
      return const AuthResult.failure('Sign up failed. Please try again.');
    }
  }

  // ===========================================================================
  // OTP VERIFICATION
  // ===========================================================================

  /// Verify OTP code sent to email
  Future<AuthResult> verifyOtp({
    required String email,
    required String token,
  }) async {
    try {
      final response = await _supabase.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.email,
      );

      if (response.session == null) {
        return const AuthResult.failure('Invalid verification code.');
      }

      // Upsert profile (trigger should handle this, but ensure it exists)
      await _ensureProfileExists(response.user!);

      return AuthResult.success(response.session!);
    } on AuthException catch (e) {
      return AuthResult.failure(e.userFriendlyMessage);
    } catch (e) {
      debugPrint('OTP verification error: $e');
      return const AuthResult.failure('Verification failed. Please try again.');
    }
  }

  /// Resend OTP to email
  /// Enforces 60 second cooldown
  Future<AuthResult> resendOtp(String email) async {
    // Check cooldown
    final canResend = await _canResendOtp();
    if (!canResend) {
      return const AuthResult.failure(
        'Please wait before requesting another code.',
      );
    }

    try {
      await _supabase.auth.resend(
        type: OtpType.email,
        email: email,
      );

      await _recordOtpSent(email);
      return AuthResult.pendingVerification(email);
    } on AuthException catch (e) {
      return AuthResult.failure(e.userFriendlyMessage);
    } catch (e) {
      debugPrint('Resend OTP error: $e');
      return const AuthResult.failure('Failed to resend code. Please try again.');
    }
  }

  Future<bool> _canResendOtp() async {
    final prefs = await _sharedPrefs;
    final lastSent = prefs.getInt(_AuthStorageKeys.lastOtpSent) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - lastSent) >= 60000; // 60 seconds
  }

  Future<void> _recordOtpSent(String email) async {
    final prefs = await _sharedPrefs;
    await prefs.setInt(
      _AuthStorageKeys.lastOtpSent,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Get last OTP sent timestamp
  Future<DateTime?> getLastOtpSentAt() async {
    final prefs = await _sharedPrefs;
    final timestamp = prefs.getInt(_AuthStorageKeys.lastOtpSent);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  // ===========================================================================
  // OAUTH PROVIDERS
  // ===========================================================================

  /// Sign in with Google OAuth
  Future<AuthResult> signInWithGoogle() async {
    try {
      final success = await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _AuthRedirects.loginCallback,
      );

      if (!success) {
        return const AuthResult.failure('Google sign in was cancelled.');
      }

      // OAuth flow continues in browser/webview
      // Session will be available via authStateChanges stream
      // Return a pending state - actual auth is async
      return const AuthResult.failure('OAuth in progress...');
    } on AuthException catch (e) {
      return AuthResult.failure(e.userFriendlyMessage);
    } catch (e) {
      debugPrint('Google sign in error: $e');
      return const AuthResult.failure('Google sign in failed.');
    }
  }

  /// Sign in with Apple OAuth
  Future<AuthResult> signInWithApple() async {
    try {
      final success = await _supabase.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: _AuthRedirects.loginCallback,
      );

      if (!success) {
        return const AuthResult.failure('Apple sign in was cancelled.');
      }

      return const AuthResult.failure('OAuth in progress...');
    } on AuthException catch (e) {
      return AuthResult.failure(e.userFriendlyMessage);
    } catch (e) {
      debugPrint('Apple sign in error: $e');
      return const AuthResult.failure('Apple sign in failed.');
    }
  }

  // ===========================================================================
  // PASSWORD RESET
  // ===========================================================================

  /// Send password reset email
  Future<AuthResult> sendPasswordReset(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: _AuthRedirects.resetPassword,
      );

      await _recordOtpSent(email);
      return AuthResult.pendingVerification(email);
    } on AuthException catch (e) {
      return AuthResult.failure(e.userFriendlyMessage);
    } catch (e) {
      debugPrint('Password reset error: $e');
      return const AuthResult.failure('Failed to send reset email.');
    }
  }

  // ===========================================================================
  // SIGN OUT
  // ===========================================================================

  /// Sign out and clear all stored data
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
    }

    // Clear stored tokens
    await _secureStorage.delete(key: _AuthStorageKeys.refreshToken);

    // Clear remember me preference (keep last email for convenience)
    final prefs = await _sharedPrefs;
    await prefs.setBool(_AuthStorageKeys.rememberMe, false);
  }

  // ===========================================================================
  // SESSION MANAGEMENT
  // ===========================================================================

  /// Restore session from refresh token
  Future<AuthResult> restoreSession(String refreshToken) async {
    try {
      final response = await _supabase.auth.setSession(refreshToken);

      if (response.session == null) {
        return const AuthResult.failure('Session could not be restored.');
      }

      return AuthResult.success(response.session!);
    } on AuthException catch (e) {
      return AuthResult.failure(e.userFriendlyMessage);
    } catch (e) {
      debugPrint('Restore session error: $e');
      return const AuthResult.failure('Session restore failed.');
    }
  }

  /// Refresh current session
  Future<AuthResult> refreshSession() async {
    try {
      final response = await _supabase.auth.refreshSession();

      if (response.session == null) {
        return const AuthResult.failure('Session refresh failed.');
      }

      // Update stored refresh token
      if (response.session!.refreshToken != null) {
        await _secureStorage.write(
          key: _AuthStorageKeys.refreshToken,
          value: response.session!.refreshToken,
        );
      }

      return AuthResult.success(response.session!);
    } on AuthException catch (e) {
      return AuthResult.failure(e.userFriendlyMessage);
    } catch (e) {
      debugPrint('Refresh session error: $e');
      return const AuthResult.failure('Session refresh failed.');
    }
  }

  /// Get stored refresh token
  Future<String?> getStoredRefreshToken() async {
    return _secureStorage.read(key: _AuthStorageKeys.refreshToken);
  }

  /// Get remembered email
  Future<String?> getRememberedEmail() async {
    final prefs = await _sharedPrefs;
    final rememberMe = prefs.getBool(_AuthStorageKeys.rememberMe) ?? false;
    if (!rememberMe) return null;
    return prefs.getString(_AuthStorageKeys.lastEmail);
  }

  // ===========================================================================
  // PROFILE MANAGEMENT
  // ===========================================================================

  /// Ensure user profile exists in public.profiles table
  Future<void> _ensureProfileExists(User user) async {
    try {
      // Try to upsert profile
      await _supabase.from('profiles').upsert(
        {
          'id': user.id,
          'full_name': user.userMetadata?['full_name'] ?? '',
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'id',
      );
    } catch (e) {
      // Profile might already exist via trigger, ignore errors
      debugPrint('Profile upsert note: $e');
    }
  }

  /// Get current user profile
  Future<Map<String, dynamic>?> getCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('Get profile error: $e');
      return null;
    }
  }

  /// Update user profile
  Future<bool> updateProfile({
    String? fullName,
    String? avatarUrl,
  }) async {
    final user = currentUser;
    if (user == null) return false;

    try {
      await _supabase.from('profiles').update({
        if (fullName != null) 'full_name': fullName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);

      return true;
    } catch (e) {
      debugPrint('Update profile error: $e');
      return false;
    }
  }
}
