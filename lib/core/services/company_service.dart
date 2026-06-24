import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/utils/result.dart';
import 'package:hospi_dash/services/step_up_auth_service.dart';

/// Provider for CompanyService
final companyServiceProvider = Provider<CompanyService>((ref) {
  return CompanyService(
      stepUpAuthService: ref.watch(stepUpAuthServiceProvider));
});

/// Provider for current company
final currentCompanyProvider = FutureProvider<Company?>((ref) async {
  final companyService = ref.watch(companyServiceProvider);
  return companyService.getCurrentCompany();
});

/// Provider for user's companies list
final userCompaniesProvider = FutureProvider<List<UserCompany>>((ref) async {
  final companyService = ref.watch(companyServiceProvider);
  return companyService.getUserCompanies();
});

/// Company model
class Company {
  final String id;
  final String name;
  final String? legalName;
  final String? taxId;
  final String? address;
  final String? city;
  final String? postalCode;
  final String? country;
  final String? phone;
  final String? email;
  final String? logoUrl;
  final String subscriptionPlan;
  final String subscriptionStatus;
  final DateTime? trialEndsAt;
  final Map<String, dynamic> settings;
  final DateTime createdAt;
  final DateTime updatedAt;

  Company({
    required this.id,
    required this.name,
    this.legalName,
    this.taxId,
    this.address,
    this.city,
    this.postalCode,
    this.country,
    this.phone,
    this.email,
    this.logoUrl,
    this.subscriptionPlan = 'free',
    this.subscriptionStatus = 'active',
    this.trialEndsAt,
    this.settings = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id'] as String,
      name: json['name'] as String,
      legalName: json['legal_name'] as String?,
      taxId: json['tax_id'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      postalCode: json['postal_code'] as String?,
      country: json['country'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      logoUrl: json['logo_url'] as String?,
      subscriptionPlan: json['subscription_plan'] as String? ?? 'free',
      subscriptionStatus: json['subscription_status'] as String? ?? 'active',
      trialEndsAt: json['trial_ends_at'] != null
          ? DateTime.parse(json['trial_ends_at'] as String)
          : null,
      settings: json['settings'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'legal_name': legalName,
      'tax_id': taxId,
      'address': address,
      'city': city,
      'postal_code': postalCode,
      'country': country,
      'phone': phone,
      'email': email,
      'logo_url': logoUrl,
      'subscription_plan': subscriptionPlan,
      'subscription_status': subscriptionStatus,
      'trial_ends_at': trialEndsAt?.toIso8601String(),
      'settings': settings,
    };
  }
}

/// User's company membership with role info
class UserCompany {
  final String companyId;
  final String companyName;
  final String role;
  final bool isCurrent;

  UserCompany({
    required this.companyId,
    required this.companyName,
    required this.role,
    required this.isCurrent,
  });

  factory UserCompany.fromJson(Map<String, dynamic> json) {
    return UserCompany(
      companyId: json['company_id'] as String,
      companyName: json['company_name'] as String,
      role: json['role'] as String,
      isCurrent: json['is_current'] as bool,
    );
  }
}

/// Company member model
class CompanyMember {
  final String id;
  final String userId;
  final String companyId;
  final String role;
  final String? email;
  final String? fullName;
  final String? avatarUrl;
  final bool isActive;
  final DateTime? joinedAt;

  CompanyMember({
    required this.id,
    required this.userId,
    required this.companyId,
    required this.role,
    this.email,
    this.fullName,
    this.avatarUrl,
    this.isActive = true,
    this.joinedAt,
  });

  factory CompanyMember.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return CompanyMember(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      companyId: json['company_id'] as String,
      role: json['role'] as String,
      email: profile?['email'] as String?,
      fullName: profile?['full_name'] as String?,
      avatarUrl: profile?['avatar_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : null,
    );
  }
}

/// Service for managing companies and multi-tenant operations
class CompanyService {
  CompanyService({StepUpAuthService? stepUpAuthService})
      : _stepUpAuthService = stepUpAuthService;

  final _supabase = SupabaseService.client;
  final StepUpAuthService? _stepUpAuthService;

  /// Create a new company and set current user as owner
  Future<Result<String>> createCompany({
    required String name,
    String? legalName,
    String? taxId,
  }) async {
    try {
      final response =
          await _supabase.rpc('create_company_with_owner', params: {
        'p_company_name': name,
        'p_legal_name': legalName,
        'p_tax_id': taxId,
      });

      if (response is Map && response['company_id'] is String) {
        return Result.success(response['company_id'] as String);
      }

      return Result.failure(
        Exception('Company setup returned an unexpected response.'),
      );
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Get current company details
  Future<Company?> getCurrentCompany() async {
    try {
      // First get user's current company ID
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final profileResponse = await _supabase
          .from('profiles')
          .select('current_company_id')
          .eq('id', userId)
          .single();

      final companyId = profileResponse['current_company_id'] as String?;
      if (companyId == null) return null;

      final companyResponse = await _supabase
          .from('companies')
          .select()
          .eq('id', companyId)
          .single();

      return Company.fromJson(companyResponse);
    } catch (e) {
      return null;
    }
  }

  /// Get all companies the user belongs to
  Future<List<UserCompany>> getUserCompanies() async {
    try {
      final response = await _supabase.rpc('get_user_companies');
      final list = response as List<dynamic>;
      return list
          .map((e) => UserCompany.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Switch to a different company
  Future<Result<void>> switchCompany(String companyId) async {
    try {
      await _supabase.rpc('switch_company', params: {
        'p_company_id': companyId,
      });
      return const Result.success(null);
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Update company details
  Future<Result<void>> updateCompany({
    required String companyId,
    String? name,
    String? legalName,
    String? taxId,
    String? address,
    String? city,
    String? postalCode,
    String? phone,
    String? email,
    String? logoUrl,
  }) async {
    try {
      await _stepUpAuthService?.requireStepUp(
        action: StepUpAction.changeCompanySettings,
      );

      await _supabase.from('companies').update({
        if (name != null) 'name': name,
        if (legalName != null) 'legal_name': legalName,
        if (taxId != null) 'tax_id': taxId,
        if (address != null) 'address': address,
        if (city != null) 'city': city,
        if (postalCode != null) 'postal_code': postalCode,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (logoUrl != null) 'logo_url': logoUrl,
      }).eq('id', companyId);

      return const Result.success(null);
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Get company members
  Future<List<CompanyMember>> getCompanyMembers(String companyId) async {
    try {
      final response = await _supabase
          .from('company_users')
          .select('*, profiles!inner(email, full_name, avatar_url)')
          .eq('company_id', companyId)
          .eq('is_active', true)
          .order('role');

      final list = response as List<dynamic>;
      return list
          .map((e) => CompanyMember.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Invite user to company
  Future<Result<String?>> inviteUser({
    required String email,
    required String companyId,
    String role = 'member',
  }) async {
    try {
      await _stepUpAuthService?.requireStepUp(action: StepUpAction.inviteUser);

      final response = await _supabase.rpc('invite_user_to_company', params: {
        'p_email': email,
        'p_company_id': companyId,
        'p_role': role,
      });

      // Returns null if user doesn't exist yet (needs to sign up first)
      return Result.success(response as String?);
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Update member role
  Future<Result<void>> updateMemberRole({
    required String companyUserId,
    required String newRole,
  }) async {
    try {
      await _stepUpAuthService?.requireStepUp(
        action: StepUpAction.changeMemberRole,
      );

      await _supabase
          .from('company_users')
          .update({'role': newRole}).eq('id', companyUserId);

      return const Result.success(null);
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Remove member from company
  Future<Result<void>> removeMember(String companyUserId) async {
    try {
      await _stepUpAuthService?.requireStepUp(
          action: StepUpAction.removeMember);

      await _supabase
          .from('company_users')
          .update({'is_active': false}).eq('id', companyUserId);

      return const Result.success(null);
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Check if user is admin of current company
  Future<bool> isCurrentUserAdmin() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final context = await _supabase.rpc('get_user_context');
      final role = context?['role'] as String?;
      return role == 'owner' || role == 'admin';
    } catch (e) {
      return false;
    }
  }

  /// Get user's role in current company
  Future<String?> getCurrentUserRole() async {
    try {
      final context = await _supabase.rpc('get_user_context');
      return context?['role'] as String?;
    } catch (e) {
      return null;
    }
  }
}
