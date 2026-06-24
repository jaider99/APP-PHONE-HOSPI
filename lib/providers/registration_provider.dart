import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/models/registration_models.dart';
import 'package:hospi_dash/services/registration_service.dart';
import 'package:hospi_dash/utils/locale_defaults.dart';

/// Provider for the registration service (singleton)
final registrationServiceProvider = Provider<RegistrationService>((ref) {
  return RegistrationService();
});

/// Notifier for managing registration state across the 3-step flow.
///
/// Steps:
/// 1. Company ID: country, tax ID, business type (NO Supabase writes)
/// 2. Company Details: legal name, trade name, city, currency, timezone (NO Supabase writes)
/// 3. User Account: full name, email, password, role (ALL Supabase writes happen here)
///
/// OWNER → completeStep3 → registerAsOwner → /dashboard
/// MANAGER → completeStep3 → registerAsManager → /pending-approval
///
/// Data is preserved when navigating back. Password is NEVER stored in state.
class RegistrationNotifier extends Notifier<RegistrationState> {
  late final RegistrationService _service;

  @override
  RegistrationState build() {
    _service = ref.watch(registrationServiceProvider);
    return const RegistrationState();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP COMPLETION METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Complete Step 1: Company ID
  void completeStep1({
    required String country,
    required String taxId,
    required BusinessType businessType,
  }) {
    final defaultCurrency = getDefaultCurrency(country);
    final defaultTimezone = getDefaultTimezone(country);

    state = state.copyWith(
      detectedCountry: country,
      verifiedTaxId: taxId,
      businessType: businessType,
      currency: defaultCurrency,
      timezone: defaultTimezone,
      step: RegistrationStep.companyDetails,
      clearError: true,
    );

    debugPrint(
        'RegistrationProvider: Step 1 complete - $country / $taxId / ${businessType.name}');
  }

  /// Complete Step 2: Company Details
  void completeStep2({
    required String legalName,
    String? tradeName,
    required String city,
    required String currency,
    required String timezone,
  }) {
    state = state.copyWith(
      legalName: legalName,
      tradeName: tradeName,
      city: city,
      currency: currency,
      timezone: timezone,
      step: RegistrationStep.userAccount,
      clearError: true,
    );

    debugPrint('RegistrationProvider: Step 2 complete - $legalName in $city');
  }

  /// Complete Step 3: User Account (FINAL STEP)
  ///
  /// Forks based on selectedRole:
  /// - OWNER → registerAsOwner → owner success, or email verification pending
  /// - MANAGER → registerAsManager → manager pending, or email verification pending
  ///
  /// [password] is passed through to service but NEVER stored in state.
  Future<RegistrationResult> completeStep3({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    // Update state with user data (NOT password)
    state = state.copyWith(
      fullName: fullName,
      email: email,
      selectedRole: role,
      isLoading: true,
      clearError: true,
    );

    late final RegistrationResult result;

    if (role == UserRole.manager) {
      // ─── MANAGER PATH ─────────────────────────────────────────────────
      final inviteCode = state.inviteCode;
      if (inviteCode == null || inviteCode.trim().isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: RegistrationError.invalidInviteCode,
          errorMessage: 'Please enter the invite code from your owner.',
        );
        return const RegistrationResult.failure(
          RegistrationError.invalidInviteCode,
          'Please enter the invite code from your owner.',
        );
      }

      debugPrint(
          'RegistrationProvider: Step 3 (MANAGER) - calling registerAsManager()');

      result = await _service.registerAsManager(
        fullName: fullName,
        email: email,
        password: password,
        inviteCode: inviteCode,
      );
    } else {
      // ─── OWNER PATH ───────────────────────────────────────────────────
      if (!_validateOwnerSteps()) {
        state = state.copyWith(
          isLoading: false,
          error: RegistrationError.validationError,
          errorMessage: 'Please complete all registration steps.',
        );
        return const RegistrationResult.failure(
          RegistrationError.validationError,
          'Please complete all registration steps.',
        );
      }

      debugPrint(
          'RegistrationProvider: Step 3 (OWNER) - calling registerAsOwner()');

      result = await _service.registerAsOwner(
        state: state,
        password: password,
      );
    }

    _applyRegistrationResult(result);

    return result;
  }

  /// Complete the preserved registration intent after email verification/login
  /// has created an authenticated Supabase session.
  Future<RegistrationResult> completePendingSetup() async {
    state = state.copyWith(isLoading: true, clearError: true);

    late final RegistrationResult result;

    if (state.selectedRole == UserRole.manager) {
      final inviteCode = state.inviteCode;
      if (inviteCode == null || inviteCode.trim().isEmpty) {
        result = const RegistrationResult.failure(
          RegistrationError.invalidInviteCode,
          'Please enter the invite code from your owner.',
        );
      } else {
        result = await _service.completeManagerSetupForCurrentUser(
          fullName: state.fullName ?? '',
          email: state.email ?? '',
          inviteCode: inviteCode,
        );
      }
    } else {
      if (!_validateOwnerSteps()) {
        result = const RegistrationResult.failure(
          RegistrationError.validationError,
          'Please complete all registration steps.',
        );
      } else {
        result = await _service.completeOwnerSetupForCurrentUser(state: state);
      }
    }

    _applyRegistrationResult(result);

    return result;
  }

  void _applyRegistrationResult(RegistrationResult result) {
    // Update state based on registration outcome
    result.when(
      ownerSuccess: (company) {
        state = state.copyWith(
          isLoading: false,
          createdCompany: company,
          step: RegistrationStep.complete,
          clearError: true,
        );
        debugPrint(
            'RegistrationProvider: Owner registration complete - company ${company.id}');
      },
      managerPending: (companyName) {
        state = state.copyWith(
          isLoading: false,
          targetCompanyName: companyName,
          step: RegistrationStep.pendingApproval,
          clearError: true,
        );
        debugPrint(
            'RegistrationProvider: Manager pending approval for $companyName');
      },
      emailVerificationPending: (email, role) {
        state = state.copyWith(
          isLoading: false,
          email: email,
          selectedRole: role,
          step: RegistrationStep.emailVerification,
          clearError: true,
        );
        debugPrint(
            'RegistrationProvider: Email verification pending for registration');
      },
      failure: (error, message) {
        state = state.copyWith(
          isLoading: false,
          error: error,
          errorMessage: message,
        );
        debugPrint(
            'RegistrationProvider: Registration failed - $error: $message');
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NAVIGATION METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  void goBackTo(RegistrationStep targetStep) {
    if (targetStep.index >= state.step.index) return;

    state = state.copyWith(
      step: targetStep,
      clearError: true,
    );

    debugPrint('RegistrationProvider: Navigated back to $targetStep');
  }

  void goBack() {
    switch (state.step) {
      case RegistrationStep.companyDetails:
        goBackTo(RegistrationStep.companyId);
        break;
      case RegistrationStep.userAccount:
        goBackTo(RegistrationStep.companyDetails);
        break;
      case RegistrationStep.emailVerification:
        goBackTo(RegistrationStep.userAccount);
        break;
      case RegistrationStep.companyId:
      case RegistrationStep.pendingApproval:
      case RegistrationStep.complete:
        break;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FIELD UPDATE METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  void updateStep1Fields({
    String? country,
    String? taxId,
    BusinessType? businessType,
  }) {
    state = state.copyWith(
      detectedCountry: country ?? state.detectedCountry,
      verifiedTaxId: taxId ?? state.verifiedTaxId,
      businessType: businessType ?? state.businessType,
      clearError: true,
    );
  }

  void updateStep2Fields({
    String? legalName,
    String? tradeName,
    String? city,
    String? currency,
    String? timezone,
  }) {
    state = state.copyWith(
      legalName: legalName ?? state.legalName,
      tradeName: tradeName ?? state.tradeName,
      city: city ?? state.city,
      currency: currency ?? state.currency,
      timezone: timezone ?? state.timezone,
      clearError: true,
    );
  }

  void updateStep3Fields({
    String? fullName,
    String? email,
    UserRole? role,
    String? inviteCode,
  }) {
    state = state.copyWith(
      fullName: fullName ?? state.fullName,
      email: email ?? state.email,
      selectedRole: role ?? state.selectedRole,
      inviteCode: inviteCode ?? state.inviteCode,
      clearError: true,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  void reset() {
    state = const RegistrationState();
    debugPrint('RegistrationProvider: State reset');
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Validate all required data for OWNER path only.
  bool _validateOwnerSteps() {
    if (state.detectedCountry == null || state.detectedCountry!.isEmpty) {
      return false;
    }
    if (state.verifiedTaxId == null || state.verifiedTaxId!.isEmpty) {
      return false;
    }
    if (state.businessType == null) return false;
    if (state.legalName == null || state.legalName!.trim().length < 2) {
      return false;
    }
    if (state.city == null || state.city!.trim().length < 2) {
      return false;
    }
    if (state.currency == null || state.currency!.isEmpty) return false;
    if (state.timezone == null || state.timezone!.isEmpty) return false;
    if (state.fullName == null || state.fullName!.trim().length < 2) {
      return false;
    }
    if (state.email == null || state.email!.isEmpty) return false;
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP VALIDATION HELPERS (for route guards)
  // ═══════════════════════════════════════════════════════════════════════════

  bool get isStep1Complete {
    return state.detectedCountry != null &&
        state.detectedCountry!.isNotEmpty &&
        state.verifiedTaxId != null &&
        state.verifiedTaxId!.isNotEmpty &&
        state.businessType != null;
  }

  bool get isStep2Complete {
    return isStep1Complete &&
        state.legalName != null &&
        state.legalName!.trim().length >= 2 &&
        state.city != null &&
        state.city!.trim().length >= 2 &&
        state.currency != null &&
        state.timezone != null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

final registrationProvider =
    NotifierProvider<RegistrationNotifier, RegistrationState>(
  RegistrationNotifier.new,
);

final isRegistrationLoadingProvider = Provider<bool>((ref) {
  return ref.watch(registrationProvider.select((s) => s.isLoading));
});

final isRegistrationCompleteProvider = Provider<bool>((ref) {
  final state = ref.watch(registrationProvider);
  return state.step == RegistrationStep.complete &&
      state.createdCompany != null;
});

/// Provider for current registration step
final currentRegistrationStepProvider = Provider<RegistrationStep>((ref) {
  return ref.watch(registrationProvider.select((s) => s.step));
});

/// Provider for registration progress (0.0 to 1.0)
final registrationProgressProvider = Provider<double>((ref) {
  final step = ref.watch(currentRegistrationStepProvider);
  switch (step) {
    case RegistrationStep.companyId:
      return 0.0; // 0%
    case RegistrationStep.companyDetails:
      return 0.33; // 33%
    case RegistrationStep.userAccount:
      return 0.66; // 66%
    case RegistrationStep.emailVerification:
      return 0.85; // 85%
    case RegistrationStep.pendingApproval:
      return 0.85; // 85%
    case RegistrationStep.complete:
      return 1.0; // 100%
  }
});

/// Provider for the created company after registration
final createdCompanyProvider = Provider<CompanyModel?>((ref) {
  return ref.watch(registrationProvider.select((s) => s.createdCompany));
});

// Legacy alias
final createdVenueProvider = createdCompanyProvider;

/// Provider for checking if user can access Step 2
final canAccessStep2Provider = Provider<bool>((ref) {
  return ref.read(registrationProvider.notifier).isStep1Complete;
});

/// Provider for checking if user can access Step 3
final canAccessStep3Provider = Provider<bool>((ref) {
  return ref.read(registrationProvider.notifier).isStep2Complete;
});
