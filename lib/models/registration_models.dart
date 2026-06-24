/// Registration models for multi-tenant company onboarding flow.
///
/// REGISTRATION FLOW:
/// Step 1 → /register/company-id (country, tax ID, business type)
/// Step 2 → /register/company-details (legal name, trade name, city, currency, timezone)
/// Step 3 → /register/user-account (full name, email, password, ROLE SELECTION)
///
/// ROLE FORK at Step 3:
///   Owner  → creates company + company_users(owner, active) → /dashboard
///   Manager → joins company via invite code → company_users(manager, inactive) → /pending-approval
///
/// ALL Supabase writes happen ONLY in Step 3.
library;

/// Registration step enum tracking progress through the flow
enum RegistrationStep {
  companyId,
  companyDetails,
  userAccount,
  emailVerification,
  pendingApproval,
  complete;

  bool get isComplete => this == RegistrationStep.complete;

  double get progress {
    switch (this) {
      case RegistrationStep.companyId:
        return 1 / 3;
      case RegistrationStep.companyDetails:
        return 2 / 3;
      case RegistrationStep.userAccount:
        return 1.0;
      case RegistrationStep.emailVerification:
        return 1.0;
      case RegistrationStep.pendingApproval:
        return 1.0;
      case RegistrationStep.complete:
        return 1.0;
    }
  }

  String get label {
    switch (this) {
      case RegistrationStep.companyId:
        return 'Step 1 of 3';
      case RegistrationStep.companyDetails:
        return 'Step 2 of 3';
      case RegistrationStep.userAccount:
        return 'Step 3 of 3';
      case RegistrationStep.emailVerification:
        return 'Verify email';
      case RegistrationStep.pendingApproval:
        return 'Pending';
      case RegistrationStep.complete:
        return 'Complete';
    }
  }

  String get subtitle {
    switch (this) {
      case RegistrationStep.companyId:
        return 'COMPANY ID';
      case RegistrationStep.companyDetails:
        return 'COMPANY DETAILS';
      case RegistrationStep.userAccount:
        return 'YOUR ACCOUNT';
      case RegistrationStep.emailVerification:
        return 'EMAIL VERIFICATION';
      case RegistrationStep.pendingApproval:
        return 'PENDING APPROVAL';
      case RegistrationStep.complete:
        return 'COMPLETE';
    }
  }
}

/// Business type enum (matches companies.business_type CHECK constraint)
enum BusinessType {
  restaurant,
  bar,
  cafe,
  bakery,
  other;

  String get displayName {
    switch (this) {
      case BusinessType.restaurant:
        return 'Restaurant';
      case BusinessType.bar:
        return 'Bar';
      case BusinessType.cafe:
        return 'Café';
      case BusinessType.bakery:
        return 'Bakery';
      case BusinessType.other:
        return 'Other';
    }
  }

  String get emoji {
    switch (this) {
      case BusinessType.restaurant:
        return '🍽';
      case BusinessType.bar:
        return '🍺';
      case BusinessType.cafe:
        return '☕';
      case BusinessType.bakery:
        return '🥐';
      case BusinessType.other:
        return '🏪';
    }
  }

  static BusinessType fromString(String? value) {
    if (value == null) return BusinessType.restaurant;
    return BusinessType.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => BusinessType.restaurant,
    );
  }
}

/// @Deprecated('Use BusinessType instead')
typedef VenueType = BusinessType;

/// User role — only owner and manager are self-registration roles.
/// Staff is added by owners later from the team management screen.
enum UserRole {
  owner,
  manager;

  String get displayName {
    switch (this) {
      case UserRole.owner:
        return 'Owner';
      case UserRole.manager:
        return 'Manager';
    }
  }

  String get description {
    switch (this) {
      case UserRole.owner:
        return 'I\'m registering my business';
      case UserRole.manager:
        return 'I\'m joining an existing business';
    }
  }

  String get detailText {
    switch (this) {
      case UserRole.owner:
        return 'Full access to all features';
      case UserRole.manager:
        return 'I need an invite code from my owner';
    }
  }

  static UserRole fromString(String? value) {
    if (value == null) return UserRole.owner;
    return UserRole.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => UserRole.owner,
    );
  }
}

/// @Deprecated('Use UserRole instead')
typedef VenueRole = UserRole;

/// Error types for registration failures
enum RegistrationError {
  duplicateTaxId,
  invalidInviteCode,
  companyInactive,
  authFailed,
  emailAlreadyExists,
  permissionDenied,
  networkError,
  validationError,
  unknown;

  String get defaultMessage {
    switch (this) {
      case RegistrationError.duplicateTaxId:
        return 'A business with this tax ID already exists. '
            'If you work there, register as Manager instead.';
      case RegistrationError.invalidInviteCode:
        return 'Invalid invite code. Check with your owner and try again.';
      case RegistrationError.companyInactive:
        return 'This business account is not active.';
      case RegistrationError.authFailed:
        return 'Account creation failed. Please try again.';
      case RegistrationError.emailAlreadyExists:
        return 'An account with this email already exists.';
      case RegistrationError.permissionDenied:
        return 'You do not have permission to perform this action.';
      case RegistrationError.networkError:
        return 'Network error. Please check your connection and try again.';
      case RegistrationError.validationError:
        return 'Please check your input and try again.';
      case RegistrationError.unknown:
        return 'An unexpected error occurred. Please try again.';
    }
  }
}

/// Result type for registration operations — three possible outcomes
sealed class RegistrationResult {
  const RegistrationResult();

  /// Owner completed — company created — go to /dashboard
  const factory RegistrationResult.ownerSuccess(CompanyModel company) =
      OwnerRegistrationSuccess;

  /// Manager submitted — waiting for owner approval — go to /pending-approval
  const factory RegistrationResult.managerPending({
    required String companyName,
  }) = ManagerPendingApproval;

  /// Auth user was created but email verification/session activation is pending.
  const factory RegistrationResult.emailVerificationPending({
    required String email,
    required UserRole role,
  }) = RegistrationEmailVerificationPending;

  /// Something went wrong
  const factory RegistrationResult.failure(
    RegistrationError error,
    String message,
  ) = RegistrationFailure;

  /// Pattern match on the result
  R when<R>({
    required R Function(CompanyModel company) ownerSuccess,
    required R Function(String companyName) managerPending,
    required R Function(String email, UserRole role) emailVerificationPending,
    required R Function(RegistrationError error, String message) failure,
  });

  bool get isSuccess => this is OwnerRegistrationSuccess;
  bool get isPending => this is ManagerPendingApproval;
  bool get isVerificationPending =>
      this is RegistrationEmailVerificationPending;
  bool get isFailure => this is RegistrationFailure;
}

/// Owner registration completed successfully
final class OwnerRegistrationSuccess extends RegistrationResult {
  final CompanyModel company;
  const OwnerRegistrationSuccess(this.company);

  @override
  R when<R>({
    required R Function(CompanyModel company) ownerSuccess,
    required R Function(String companyName) managerPending,
    required R Function(String email, UserRole role) emailVerificationPending,
    required R Function(RegistrationError error, String message) failure,
  }) =>
      ownerSuccess(company);
}

/// Manager registration pending owner approval
final class ManagerPendingApproval extends RegistrationResult {
  final String companyName;
  const ManagerPendingApproval({required this.companyName});

  @override
  R when<R>({
    required R Function(CompanyModel company) ownerSuccess,
    required R Function(String companyName) managerPending,
    required R Function(String email, UserRole role) emailVerificationPending,
    required R Function(RegistrationError error, String message) failure,
  }) =>
      managerPending(companyName);
}

/// Email verification is required before company setup can be completed.
final class RegistrationEmailVerificationPending extends RegistrationResult {
  final String email;
  final UserRole role;
  const RegistrationEmailVerificationPending({
    required this.email,
    required this.role,
  });

  @override
  R when<R>({
    required R Function(CompanyModel company) ownerSuccess,
    required R Function(String companyName) managerPending,
    required R Function(String email, UserRole role) emailVerificationPending,
    required R Function(RegistrationError error, String message) failure,
  }) =>
      emailVerificationPending(email, role);
}

/// Registration failed
final class RegistrationFailure extends RegistrationResult {
  final RegistrationError error;
  final String message;
  const RegistrationFailure(this.error, this.message);

  @override
  R when<R>({
    required R Function(CompanyModel company) ownerSuccess,
    required R Function(String companyName) managerPending,
    required R Function(String email, UserRole role) emailVerificationPending,
    required R Function(RegistrationError error, String message) failure,
  }) =>
      failure(error, message);
}

/// Immutable registration state holding all data across all steps.
///
/// Field ownership by step:
/// - Step 1 (companyId): detectedCountry, verifiedTaxId, businessType
/// - Step 2 (companyDetails): legalName, tradeName, city, currency, timezone
/// - Step 3 (userAccount): fullName, email, selectedRole, inviteCode (manager only)
///
/// Password is NEVER stored in state — only passed transiently to the service.
class RegistrationState {
  // ── Step 1 outputs ──────────────────────────────
  final String? detectedCountry;
  final String? verifiedTaxId;
  final BusinessType? businessType;

  // ── Step 2 outputs ──────────────────────────────
  final String? legalName;
  final String? tradeName;
  final String? city;
  final String currency;
  final String timezone;

  // ── Step 3 outputs ──────────────────────────────
  final String? fullName;
  final String? email;
  final UserRole selectedRole;

  // ── Manager path only ───────────────────────────
  final String? inviteCode;
  final String? targetCompanyId;
  final String? targetCompanyName;

  // ── Flow control ────────────────────────────────
  final RegistrationStep currentStep;
  final bool isLoading;
  final String? errorMessage;
  final RegistrationError? error;

  // ── Result ──────────────────────────────────────
  final CompanyModel? createdCompany;

  /// Alias for currentStep (for backwards compatibility)
  RegistrationStep get step => currentStep;

  /// Legacy alias
  BusinessType? get venueType => businessType;
  UserRole get role => selectedRole;
  CompanyModel? get createdVenue => createdCompany;

  const RegistrationState({
    this.detectedCountry,
    this.verifiedTaxId,
    this.businessType,
    this.legalName,
    this.tradeName,
    this.city,
    this.currency = 'EUR',
    this.timezone = 'Europe/Madrid',
    this.fullName,
    this.email,
    this.selectedRole = UserRole.owner,
    this.inviteCode,
    this.targetCompanyId,
    this.targetCompanyName,
    this.currentStep = RegistrationStep.companyId,
    this.isLoading = false,
    this.errorMessage,
    this.error,
    this.createdCompany,
  });

  /// Initial state for starting registration
  factory RegistrationState.initial() => const RegistrationState();

  /// Check if Step 1 data is complete
  bool get hasStep1Data =>
      detectedCountry != null && verifiedTaxId != null && businessType != null;

  /// Check if Step 2 data is complete
  bool get hasStep2Data =>
      legalName != null &&
      legalName!.isNotEmpty &&
      city != null &&
      city!.isNotEmpty;

  /// Check if Step 3 data is complete (excluding password)
  bool get hasStep3Data =>
      fullName != null &&
      fullName!.isNotEmpty &&
      email != null &&
      email!.isNotEmpty;

  /// Can navigate to Step 2
  bool get canAccessStep2 => hasStep1Data;

  /// Can navigate to Step 3
  bool get canAccessStep3 => hasStep1Data && hasStep2Data;

  /// Display name for the company (trade name or legal name)
  String get displayName =>
      tradeName?.isNotEmpty == true ? tradeName! : (legalName ?? '');

  /// Whether the manager path requires an invite code
  bool get needsInviteCode => selectedRole == UserRole.manager;

  RegistrationState copyWith({
    String? detectedCountry,
    String? verifiedTaxId,
    BusinessType? businessType,
    BusinessType? venueType, // Legacy alias
    String? legalName,
    String? tradeName,
    String? city,
    String? currency,
    String? timezone,
    String? fullName,
    String? email,
    UserRole? selectedRole,
    UserRole? role, // Legacy alias
    String? inviteCode,
    String? targetCompanyId,
    String? targetCompanyName,
    RegistrationStep? currentStep,
    RegistrationStep? step, // Alias for currentStep
    bool? isLoading,
    String? errorMessage,
    RegistrationError? error,
    CompanyModel? createdCompany,
    CompanyModel? createdVenue, // Legacy alias
    bool clearError = false,
  }) {
    return RegistrationState(
      detectedCountry: detectedCountry ?? this.detectedCountry,
      verifiedTaxId: verifiedTaxId ?? this.verifiedTaxId,
      businessType: venueType ?? businessType ?? this.businessType,
      legalName: legalName ?? this.legalName,
      tradeName: tradeName ?? this.tradeName,
      city: city ?? this.city,
      currency: currency ?? this.currency,
      timezone: timezone ?? this.timezone,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      selectedRole: role ?? selectedRole ?? this.selectedRole,
      inviteCode: inviteCode ?? this.inviteCode,
      targetCompanyId: targetCompanyId ?? this.targetCompanyId,
      targetCompanyName: targetCompanyName ?? this.targetCompanyName,
      currentStep: step ?? currentStep ?? this.currentStep,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      error: clearError ? null : (error ?? this.error),
      createdCompany: createdVenue ?? createdCompany ?? this.createdCompany,
    );
  }

  @override
  String toString() => 'RegistrationState(step: $currentStep, '
      'country: $detectedCountry, taxId: $verifiedTaxId, type: $businessType, '
      'legalName: $legalName, city: $city, role: $selectedRole)';
}

/// Company model representing a registered business (the tenant root)
class CompanyModel {
  final String id;
  final String name;
  final String legalName;
  final String? tradeName;
  final String taxId;
  final String country;
  final String city;
  final String currency;
  final String timezone;
  final String businessType;
  final String ownerId;
  final String? inviteCode;
  final bool isActive;
  final DateTime createdAt;

  const CompanyModel({
    required this.id,
    required this.name,
    required this.legalName,
    this.tradeName,
    required this.taxId,
    required this.country,
    required this.city,
    required this.currency,
    required this.timezone,
    required this.businessType,
    required this.ownerId,
    this.inviteCode,
    required this.isActive,
    required this.createdAt,
  });

  factory CompanyModel.fromJson(Map<String, dynamic> json) {
    return CompanyModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['legal_name'] as String,
      legalName: json['legal_name'] as String? ?? json['name'] as String,
      tradeName: json['trade_name'] as String?,
      taxId: json['tax_id'] as String? ?? '',
      country: json['country'] as String? ?? 'ES',
      city: json['city'] as String? ?? '',
      currency: json['currency'] as String? ?? 'EUR',
      timezone: json['timezone'] as String? ?? 'Europe/Madrid',
      businessType: json['business_type'] as String? ?? 'restaurant',
      ownerId: json['owner_id'] as String? ?? '',
      inviteCode: json['invite_code'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'legal_name': legalName,
      'trade_name': tradeName,
      'tax_id': taxId,
      'country': country,
      'city': city,
      'currency': currency,
      'timezone': timezone,
      'business_type': businessType,
      'owner_id': ownerId,
      'invite_code': inviteCode,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  String toString() => 'CompanyModel(id: $id, name: $name)';
}

/// @Deprecated('Use CompanyModel instead')
typedef VenueModel = CompanyModel;

/// Company-user membership model
class CompanyUserModel {
  final String id;
  final String companyId;
  final String userId;
  final String role;
  final bool isActive;
  final DateTime joinedAt;

  const CompanyUserModel({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.role,
    required this.isActive,
    required this.joinedAt,
  });

  factory CompanyUserModel.fromJson(Map<String, dynamic> json) {
    return CompanyUserModel(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
      isActive: json['is_active'] as bool? ?? true,
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : DateTime.now(),
    );
  }
}

/// @Deprecated('Use CompanyUserModel instead')
typedef VenueMemberModel = CompanyUserModel;

/// Country tax configuration for tax ID validation
class CountryTaxConfig {
  final String code;
  final String name;
  final String flag;
  final String taxIdLabel;
  final RegExp validationRegex;
  final String placeholder;
  final String defaultCurrency;
  final String defaultTimezone;

  const CountryTaxConfig({
    required this.code,
    required this.name,
    required this.flag,
    required this.taxIdLabel,
    required this.validationRegex,
    required this.placeholder,
    required this.defaultCurrency,
    required this.defaultTimezone,
  });

  bool validate(String taxId) => validationRegex.hasMatch(taxId.toUpperCase());
}
