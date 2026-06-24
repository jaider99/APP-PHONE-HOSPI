import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hospi_dash/core/utils/app_logger.dart';
import 'package:hospi_dash/models/registration_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for completing multi-tenant registration.
///
/// Uses Supabase RPC functions (SECURITY DEFINER) for ATOMIC operations.
/// This eliminates the RLS chicken-and-egg problem where INSERT into companies
/// needs a company_users row that doesn't exist yet.
///
/// TWO COMPLETELY SEPARATE PATHS:
///
/// OWNER PATH (registerAsOwner):
///   1. auth.signUp → 2. ensure session → 3. RPC create_company_with_owner
///
/// MANAGER PATH (registerAsManager):
///   1. auth.signUp → 2. ensure session → 3. RPC join_company_as_manager
class RegistrationService {
  final SupabaseClient _supabase;

  RegistrationService({SupabaseClient? supabaseClient})
      : _supabase = supabaseClient ?? Supabase.instance.client;

  // ═══════════════════════════════════════════════════════════════════════════
  // OWNER PATH — creates company + user via RPC
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register as Owner: creates auth user, then calls RPC to atomically
  /// create company + company_users + user_preferences + profile.
  Future<RegistrationResult> registerAsOwner({
    required RegistrationState state,
    required String password,
  }) async {
    // Guard: all required fields
    if (state.verifiedTaxId == null ||
        state.detectedCountry == null ||
        state.legalName == null ||
        state.city == null ||
        state.fullName == null ||
        state.email == null) {
      return const RegistrationResult.failure(
        RegistrationError.validationError,
        'Please complete all required fields.',
      );
    }

    try {
      // ─────────────────────────────────────────────────────────────────────
      // STEP 1: Create auth user
      // ─────────────────────────────────────────────────────────────────────
      debugPrint('RegistrationService: OWNER Step 1 - auth.signUp');
      final authResponse = await _supabase.auth.signUp(
        email: state.email!.trim(),
        password: password,
        data: {'full_name': state.fullName!.trim(), 'role': 'owner'},
      );

      final user = authResponse.user;
      if (user == null) {
        return const RegistrationResult.failure(
          RegistrationError.authFailed,
          'Could not create account. Please try again.',
        );
      }
      debugPrint('RegistrationService: auth user created: ${user.id}');
      _logSignupSessionState(user.id, authResponse.session);

      if (!await _ensureAuthenticatedSession(authResponse.session)) {
        AppLogger.info(
            '[Registration] owner setup paused for email verification');
        return RegistrationResult.emailVerificationPending(
          email: state.email!.trim(),
          role: UserRole.owner,
        );
      }

      return completeOwnerSetupForCurrentUser(state: state);
    } on AuthException catch (e) {
      debugPrint('RegistrationService: Auth error - ${e.message}');

      if (_isEmailRateLimitError(e.message)) {
        return const RegistrationResult.failure(
          RegistrationError.authFailed,
          'Too many attempts. Please wait a few minutes before trying again.',
        );
      }

      if (e.message.toLowerCase().contains('already registered') ||
          e.message.toLowerCase().contains('already exists')) {
        return const RegistrationResult.failure(
          RegistrationError.emailAlreadyExists,
          'An account with this email already exists.',
        );
      }

      return RegistrationResult.failure(
        RegistrationError.authFailed,
        e.message.isNotEmpty ? e.message : 'Account creation failed.',
      );
    } on PostgrestException catch (e) {
      debugPrint('RegistrationService: RPC DB error - ${e.code}: ${e.message}');
      return RegistrationResult.failure(
        _mapRpcError(e),
        _getRpcErrorMessage(e),
      );
    } on SocketException catch (_) {
      return const RegistrationResult.failure(
        RegistrationError.networkError,
        'Network error. Please check your connection and try again.',
      );
    } catch (e) {
      debugPrint(
          'RegistrationService: Unexpected error - ${e.runtimeType}: $e');
      return const RegistrationResult.failure(
        RegistrationError.unknown,
        'Registration failed. Please try again.',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MANAGER PATH — joins existing company via RPC
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register as Manager: creates auth user, then calls RPC to atomically
  /// create company_users (pending) + profile + activity log.
  Future<RegistrationResult> registerAsManager({
    required String fullName,
    required String email,
    required String password,
    required String inviteCode,
  }) async {
    try {
      // ─────────────────────────────────────────────────────────────────────
      // STEP 1: Create auth user
      // ─────────────────────────────────────────────────────────────────────
      debugPrint('RegistrationService: MANAGER Step 1 - auth.signUp');
      final authResponse = await _supabase.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': fullName.trim(), 'role': 'manager'},
      );

      final user = authResponse.user;
      if (user == null) {
        return const RegistrationResult.failure(
          RegistrationError.authFailed,
          'Could not create account. Please try again.',
        );
      }
      debugPrint('RegistrationService: auth user created: ${user.id}');
      _logSignupSessionState(user.id, authResponse.session);

      if (!await _ensureAuthenticatedSession(authResponse.session)) {
        AppLogger.info(
            '[Registration] manager setup paused for email verification');
        return RegistrationResult.emailVerificationPending(
          email: email.trim(),
          role: UserRole.manager,
        );
      }

      return completeManagerSetupForCurrentUser(
        fullName: fullName,
        email: email,
        inviteCode: inviteCode,
      );
    } on AuthException catch (e) {
      debugPrint('RegistrationService: Auth error (manager) - ${e.message}');

      if (_isEmailRateLimitError(e.message)) {
        return const RegistrationResult.failure(
          RegistrationError.authFailed,
          'Too many attempts. Please wait a few minutes before trying again.',
        );
      }

      if (e.message.toLowerCase().contains('already registered') ||
          e.message.toLowerCase().contains('already exists')) {
        return const RegistrationResult.failure(
          RegistrationError.emailAlreadyExists,
          'An account with this email already exists.',
        );
      }

      return RegistrationResult.failure(
        RegistrationError.authFailed,
        e.message.isNotEmpty ? e.message : 'Account creation failed.',
      );
    } on PostgrestException catch (e) {
      debugPrint(
          'RegistrationService: RPC DB error (manager) - ${e.code}: ${e.message}');
      return RegistrationResult.failure(
        _mapRpcError(e),
        _getRpcErrorMessage(e),
      );
    } on SocketException catch (_) {
      return const RegistrationResult.failure(
        RegistrationError.networkError,
        'Network error. Please check your connection and try again.',
      );
    } catch (e) {
      debugPrint(
          'RegistrationService: Unexpected error (manager) - ${e.runtimeType}: $e');
      return const RegistrationResult.failure(
        RegistrationError.unknown,
        'Could not complete registration. Please try again.',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<RegistrationResult> completeOwnerSetupForCurrentUser({
    required RegistrationState state,
  }) async {
    final user = _supabase.auth.currentUser;
    if (!_hasCurrentSession || user == null) {
      return const RegistrationResult.failure(
        RegistrationError.authFailed,
        'Your account was created, but your session is not active yet. '
        'Please verify your email or sign in again to finish company setup.',
      );
    }

    try {
      return await _createCompanyForCurrentUser(state, ownerId: user.id);
    } on PostgrestException catch (e) {
      debugPrint('RegistrationService: RPC DB error - ${e.code}: ${e.message}');
      return RegistrationResult.failure(
        _mapRpcError(e),
        _getRpcErrorMessage(e),
      );
    } on SocketException catch (_) {
      return const RegistrationResult.failure(
        RegistrationError.networkError,
        'Network error. Please check your connection and try again.',
      );
    } catch (e) {
      debugPrint(
          'RegistrationService: Unexpected owner setup error - ${e.runtimeType}: $e');
      return const RegistrationResult.failure(
        RegistrationError.unknown,
        'Registration failed. Please try again.',
      );
    }
  }

  Future<RegistrationResult> completeManagerSetupForCurrentUser({
    required String fullName,
    required String email,
    required String inviteCode,
  }) async {
    if (!_hasCurrentSession || _supabase.auth.currentUser == null) {
      return const RegistrationResult.failure(
        RegistrationError.authFailed,
        'Your account was created, but your session is not active yet. '
        'Please verify your email or sign in again to finish company setup.',
      );
    }

    try {
      debugPrint(
          'RegistrationService: MANAGER Step 2 - RPC join_company_as_manager');
      final rpcResult = await _supabase.rpc('join_company_as_manager', params: {
        'p_invite_code': inviteCode.toUpperCase().trim(),
        'p_full_name': fullName.trim(),
        'p_email': email.trim(),
      });

      debugPrint('RegistrationService: RPC result = $rpcResult');

      final companyName = rpcResult['company_name'] as String;

      debugPrint(
          'RegistrationService: Manager path completed, pending approval for $companyName');
      return RegistrationResult.managerPending(companyName: companyName);
    } on PostgrestException catch (e) {
      debugPrint(
          'RegistrationService: RPC DB error (manager) - ${e.code}: ${e.message}');
      return RegistrationResult.failure(
        _mapRpcError(e),
        _getRpcErrorMessage(e),
      );
    } on SocketException catch (_) {
      return const RegistrationResult.failure(
        RegistrationError.networkError,
        'Network error. Please check your connection and try again.',
      );
    } catch (e) {
      debugPrint(
          'RegistrationService: Unexpected manager setup error - ${e.runtimeType}: $e');
      return const RegistrationResult.failure(
        RegistrationError.unknown,
        'Could not complete registration. Please try again.',
      );
    }
  }

  Future<RegistrationResult> _createCompanyForCurrentUser(
    RegistrationState state, {
    required String ownerId,
  }) async {
    final sanitizedLegalName = _sanitizeInput(state.legalName!);
    final sanitizedTradeName = state.tradeName?.trim().isNotEmpty == true
        ? _sanitizeInput(state.tradeName!)
        : null;
    final companyName = sanitizedTradeName?.isNotEmpty == true
        ? sanitizedTradeName!
        : sanitizedLegalName;

    debugPrint(
        'RegistrationService: OWNER Step 2 - RPC create_company_with_owner');
    final rpcResult = await _supabase.rpc('create_company_with_owner', params: {
      'p_company_name': companyName,
      'p_legal_name': sanitizedLegalName,
      'p_tax_id': state.verifiedTaxId!,
      'p_city': _sanitizeInput(state.city!),
      'p_country': state.detectedCountry!,
      'p_currency': state.currency,
      'p_timezone': state.timezone,
      'p_business_type': state.businessType?.name ?? 'restaurant',
      'p_full_name': state.fullName!.trim(),
      'p_email': state.email!.trim(),
    });

    debugPrint('RegistrationService: RPC result = $rpcResult');

    final companyId = rpcResult['company_id'] as String;
    final inviteCode = rpcResult['invite_code'] as String?;

    final company = CompanyModel(
      id: companyId,
      name: companyName,
      legalName: sanitizedLegalName,
      taxId: state.verifiedTaxId!,
      country: state.detectedCountry!,
      city: _sanitizeInput(state.city!),
      currency: state.currency,
      timezone: state.timezone,
      businessType: state.businessType?.name ?? 'restaurant',
      ownerId: ownerId,
      inviteCode: inviteCode,
      isActive: true,
      createdAt: DateTime.now(),
    );

    debugPrint(
        'RegistrationService: Owner path completed - company $companyId');
    return RegistrationResult.ownerSuccess(company);
  }

  bool get _hasCurrentSession =>
      _supabase.auth.currentUser != null &&
      _supabase.auth.currentSession?.accessToken != null;

  Future<bool> _ensureAuthenticatedSession(Session? signupSession) async {
    if (signupSession == null) return false;
    if (_hasCurrentSession) return true;

    try {
      final refreshed = await _supabase.auth.refreshSession();
      return refreshed.session?.accessToken != null &&
          _supabase.auth.currentUser != null;
    } catch (e) {
      AppLogger.warning('[Registration] session refresh after signup failed',
          error: e);
      return false;
    }
  }

  void _logSignupSessionState(String userId, Session? session) {
    AppLogger.debug('[Registration] auth user id: $userId');
    AppLogger.debug('[Registration] session exists: ${session != null}');
    AppLogger.debug(
      '[Registration] current user exists: ${_supabase.auth.currentUser != null}',
    );
    AppLogger.debug(
      '[Registration] access token exists: '
      '${_supabase.auth.currentSession?.accessToken != null}',
    );
  }

  String _sanitizeInput(String input) {
    return input.trim().replaceAll(RegExp(r'<[^>]*>'), '');
  }

  bool _isEmailRateLimitError(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('rate limit') ||
        normalized.contains('too many requests') ||
        normalized.contains('over_email_send_rate_limit') ||
        normalized.contains('email rate limit exceeded');
  }

  /// Map RPC exceptions to RegistrationError.
  /// RPC functions raise exceptions with prefixed messages like
  /// "DUPLICATE_TAX_ID: A business with tax ID ... already exists"
  RegistrationError _mapRpcError(PostgrestException e) {
    final msg = e.message.toUpperCase();

    if (msg.contains('DUPLICATE_TAX_ID') || e.code == '23505') {
      return RegistrationError.duplicateTaxId;
    }
    if (msg.contains('INVALID_INVITE_CODE')) {
      return RegistrationError.invalidInviteCode;
    }
    if (msg.contains('COMPANY_INACTIVE')) {
      return RegistrationError.companyInactive;
    }
    if (msg.contains('ALREADY_MEMBER')) {
      return RegistrationError.validationError;
    }
    if (msg == 'UNAUTHORIZED' ||
        e.code == 'P0001' && msg.contains('UNAUTHORIZED')) {
      return RegistrationError.authFailed;
    }
    if (e.code == '42501') {
      return RegistrationError.permissionDenied;
    }

    return RegistrationError.unknown;
  }

  /// Extract user-friendly message from RPC exception.
  String _getRpcErrorMessage(PostgrestException e) {
    final msg = e.message;

    // RPC errors come as "RAISE EXCEPTION" messages via PostgREST
    // Format: "DUPLICATE_TAX_ID: A business with tax ID X already exists"
    if (msg.contains('DUPLICATE_TAX_ID')) {
      return 'A business with this tax ID already exists. '
          'If you work there, register as Manager instead.';
    }
    if (msg.contains('INVALID_INVITE_CODE')) {
      return 'Invalid invite code. Check with your owner and try again.';
    }
    if (msg.contains('COMPANY_INACTIVE')) {
      return 'This business account is not active.';
    }
    if (msg.contains('ALREADY_MEMBER')) {
      return 'You are already a member of this company.';
    }
    if (msg == 'Unauthorized' || msg.contains('Unauthorized')) {
      return 'Your account was created, but your session is not active yet. '
          'Please verify your email or sign in again to finish company setup.';
    }

    if (e.code == '42501') {
      return 'You do not have permission to perform this action.';
    }

    return msg.isNotEmpty
        ? msg
        : 'An unexpected error occurred. Please try again.';
  }
}
