import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/utils/locale_defaults.dart';

const _companyQueryTimeout = Duration(seconds: 8);

// =============================================================================
// COMPANY ID PROVIDER — single source of truth for tenant scoping
// =============================================================================

/// Resolves the current company_id for the authenticated user.
///
/// Fallback chain:
///   1. profiles.current_company_id  (fast path, no RLS recursion)
///   2. company_users.company_id     (active membership)
///   3. companies table              (last resort)
///
/// Every Supabase query in the app MUST use this to scope data.
final companyIdProvider = FutureProvider<String?>((ref) async {
  final user = SupabaseService.currentUser;
  if (user == null) {
    debugPrint('companyIdProvider: no authenticated user');
    return null;
  }

  debugPrint('companyIdProvider: resolving for user ${user.id}');
  final supabase = SupabaseService.client;

  try {
    // 1. Fast path: profiles.current_company_id
    final profile = await _withCompanyQueryTimeout(
      supabase
          .from('profiles')
          .select('current_company_id')
          .eq('id', user.id)
          .maybeSingle(),
      'profiles.current_company_id',
    );

    final companyId = profile?['current_company_id'] as String?;
    if (companyId != null) {
      debugPrint('companyIdProvider: found current_company_id=$companyId');
      return companyId;
    }
    debugPrint('companyIdProvider: no current_company_id in profile');

    // 2. Fallback: first active company from company_users
    try {
      var membership = await _withCompanyQueryTimeout(
        supabase
            .from('company_users')
            .select('company_id')
            .eq('user_id', user.id)
            .eq('is_active', true)
            .limit(1)
            .maybeSingle(),
        'company_users.active_membership',
      );

      // 2b. Try without is_active filter
      if (membership == null) {
        debugPrint('companyIdProvider: no active company_users, trying without filter');
        membership = await _withCompanyQueryTimeout(
          supabase
              .from('company_users')
              .select('company_id')
              .eq('user_id', user.id)
              .limit(1)
              .maybeSingle(),
          'company_users.any_membership',
        );
      }

      final fallbackId = membership?['company_id'] as String?;
      if (fallbackId != null) {
        debugPrint('companyIdProvider: fallback company_id=$fallbackId');
        // Persist so future queries hit the fast path
        await _withCompanyQueryTimeout(
          supabase
              .from('profiles')
              .update({'current_company_id': fallbackId})
              .eq('id', user.id),
          'profiles.persist_current_company_id',
        );
        return fallbackId;
      }
    } catch (e) {
      debugPrint('companyIdProvider: company_users query failed: $e');
    }

    // 3. Last resort: companies table directly
    debugPrint('companyIdProvider: trying companies table directly');
    try {
      final company = await _withCompanyQueryTimeout(
        supabase
            .from('companies')
            .select('id')
            .limit(1)
            .maybeSingle(),
        'companies.last_resort',
      );

      if (company != null) {
        final ownedId = company['id'] as String;
        debugPrint('companyIdProvider: found company=$ownedId, setting as current');
        await _withCompanyQueryTimeout(
          supabase
              .from('profiles')
              .update({'current_company_id': ownedId})
              .eq('id', user.id),
          'profiles.persist_owned_company_id',
        );
        return ownedId;
      }
    } catch (e) {
      debugPrint('companyIdProvider: companies query also failed: $e');
    }

    debugPrint('companyIdProvider: no company found for user ${user.id}');
    return null;
  } catch (e, stackTrace) {
    debugPrint('companyIdProvider error: $e');
    debugPrint('companyIdProvider stackTrace: $stackTrace');
    return null;
  }
});

/// Whether the current user has a pending (is_active=false) company membership
/// with no active membership. Used to redirect managers to pending-approval.
final isPendingApprovalProvider = FutureProvider<bool>((ref) async {
  final user = SupabaseService.currentUser;
  if (user == null) return false;

  final supabase = SupabaseService.client;

  try {
    // Check for any active membership first
    final active = await _withCompanyQueryTimeout(
      supabase
          .from('company_users')
          .select('id')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .limit(1)
          .maybeSingle(),
      'company_users.pending_check_active',
    );

    if (active != null) return false; // Has active membership

    // Check for pending membership
    final pending = await _withCompanyQueryTimeout(
      supabase
          .from('company_users')
          .select('id')
          .eq('user_id', user.id)
          .eq('is_active', false)
          .limit(1)
          .maybeSingle(),
      'company_users.pending_check_pending',
    );

    return pending != null;
  } catch (e) {
    debugPrint('isPendingApprovalProvider error: $e');
    return false;
  }
});

/// The company name for pending manager approvals (for the pending screen).
final pendingCompanyNameProvider = FutureProvider<String?>((ref) async {
  final user = SupabaseService.currentUser;
  if (user == null) return null;

  final supabase = SupabaseService.client;

  try {
    final row = await _withCompanyQueryTimeout(
      supabase
          .from('company_users')
          .select('company_id, companies(name)')
          .eq('user_id', user.id)
          .eq('is_active', false)
          .limit(1)
          .maybeSingle(),
      'company_users.pending_company_name',
    );

    if (row == null) return null;
    final companies = row['companies'];
    if (companies is Map) return companies['name'] as String?;
    return null;
  } catch (e) {
    debugPrint('pendingCompanyNameProvider error: $e');
    return null;
  }
});

// =============================================================================
// COMPANY CURRENCY PROVIDERS
// =============================================================================

/// Fetches the current company's currency code (ISO 4217, e.g. 'EUR', 'USD').
/// Falls back to 'EUR' when unauthenticated or on error.
final companyCurrencyProvider = FutureProvider<String>((ref) async {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return 'EUR';

  try {
    final row = await _withCompanyQueryTimeout(
      SupabaseService.client
          .from('companies')
          .select('currency')
          .eq('id', companyId)
          .maybeSingle(),
      'companies.currency',
    );
    final code = row?['currency'] as String?;
    return (code != null && code.isNotEmpty) ? code : 'EUR';
  } catch (e) {
    debugPrint('companyCurrencyProvider error: $e');
    return 'EUR';
  }
});

/// Resolves to the display symbol for the current company's currency
/// (e.g. '€', '\$', '£'). Falls back to '€'.
final currencySymbolProvider = FutureProvider<String>((ref) async {
  final code = await ref.watch(companyCurrencyProvider.future);
  return currencySymbolFromCode(code);
});

Future<T> _withCompanyQueryTimeout<T>(Future<T> future, String label) async {
  try {
    return await future.timeout(_companyQueryTimeout);
  } on TimeoutException {
    debugPrint('companyProvider: $label timed out');
    rethrow;
  }
}
