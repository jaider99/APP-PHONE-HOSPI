import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/utils/result.dart';
import 'package:hospi_dash/data/models/user_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider for AuthService
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// Provider for current auth state
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// Provider for current user profile
final currentUserProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final authState = await ref.watch(authStateProvider.future);
  if (authState.session == null) return null;

  final authService = ref.watch(authServiceProvider);
  return authService.getCurrentUserProfile();
});

/// Provider for current company ID
final currentCompanyIdProvider = FutureProvider<String?>((ref) async {
  final authState = await ref.watch(authStateProvider.future);
  if (authState.session == null) return null;

  final authService = ref.watch(authServiceProvider);
  return authService.getCurrentCompanyId();
});

/// Authentication service handling all auth operations
/// Multi-tenant aware - stores company_id in user metadata
class AuthService {
  final _supabase = SupabaseService.client;
  
  /// Cached company ID (set after login/profile load)
  String? _cachedCompanyId;

  /// Stream of auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Current user
  User? get currentUser => _supabase.auth.currentUser;

  /// Current session
  Session? get currentSession => _supabase.auth.currentSession;

  /// Check if user is authenticated
  bool get isAuthenticated => currentUser != null;
  
  /// Sync access to cached company ID
  /// Call refreshCompanyId() first to ensure it's loaded
  String? get currentCompanyId => _cachedCompanyId;

  /// Get current user's company_id (multi-tenant)
  /// Fetched from profiles table (more reliable than JWT metadata)
  Future<String?> getCurrentCompanyId() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final response = await _supabase
          .from('profiles')
          .select('current_company_id')
          .eq('id', user.id)
          .single();

      _cachedCompanyId = response['current_company_id'] as String?;
      return _cachedCompanyId;
    } catch (e) {
      return null;
    }
  }

  /// Sign up with email and password
  /// Note: Profile is auto-created via database trigger
  Future<Result<User>> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
        },
      );

      if (response.user == null) {
        return Result.failure(AuthException('Sign up failed'));
      }

      return Result.success(response.user!);
    } on AuthException catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Sign in with email and password
  Future<Result<User>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        return Result.failure(AuthException('Sign in failed'));
      }

      return Result.success(response.user!);
    } on AuthException catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Sign in with OAuth provider
  Future<Result<void>> signInWithOAuth(OAuthProvider provider) async {
    try {
      await _supabase.auth.signInWithOAuth(
        provider,
        redirectTo: 'com.hospidash.app://login-callback',
      );
      return const Result.success(null);
    } on AuthException catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Sign out
  Future<Result<void>> signOut() async {
    try {
      await _supabase.auth.signOut();
      return const Result.success(null);
    } on AuthException catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Send password reset email
  Future<Result<void>> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
      return const Result.success(null);
    } on AuthException catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Update user password
  Future<Result<void>> updatePassword(String newPassword) async {
    try {
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      return const Result.success(null);
    } on AuthException catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Get current user profile from database
  Future<UserProfile?> getCurrentUserProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      return UserProfile.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  /// Get full user context including company info
  Future<Map<String, dynamic>?> getUserContext() async {
    if (currentUser == null) return null;

    try {
      final response = await _supabase.rpc('get_user_context');
      return response as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }

  /// Update user profile
  Future<Result<void>> updateUserProfile({
    String? fullName,
    String? avatarUrl,
  }) async {
    final user = currentUser;
    if (user == null) {
      return Result.failure(AuthException('Not authenticated'));
    }

    try {
      await _supabase.from('profiles').update({
        if (fullName != null) 'full_name': fullName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);

      return const Result.success(null);
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Refresh session
  Future<Result<Session>> refreshSession() async {
    try {
      final response = await _supabase.auth.refreshSession();
      if (response.session == null) {
        return Result.failure(AuthException('Session refresh failed'));
      }
      return Result.success(response.session!);
    } on AuthException catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }
}
