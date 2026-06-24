import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/auth_service.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/utils/app_logger.dart';
import 'package:hospi_dash/data/models/provider.dart' as models;

/// Provider for ProvidersRepository
final providersRepositoryProvider = Provider<ProvidersRepository>((ref) {
  final authService = ref.watch(authServiceProvider);
  return ProvidersRepository(authService: authService);
});

/// Repository for provider/supplier data operations
/// Multi-tenant: All queries filtered by company_id via RLS
class ProvidersRepository {
  final AuthService _authService;
  final _supabase = SupabaseService.client;

  ProvidersRepository({required AuthService authService})
      : _authService = authService;

  String? get _companyId => _authService.currentCompanyId;

  /// Get all active providers
  Future<List<models.Provider>> getActiveProviders() async {
    if (_companyId == null) return [];

    try {
      final response = await _supabase
          .from('providers')
          .select()
          .eq('company_id', _companyId!)
          .eq('is_active', true)
          .order('name', ascending: true);

      return (response as List)
          .map((json) => models.Provider.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch providers', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Get top providers by spending over the rolling dashboard window.
  Future<List<models.ProviderSpending>> getTopProvidersBySpending({int limit = 5}) async {
    if (_companyId == null) return [];

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final startDate = today.subtract(const Duration(days: 29));

      // Get completed, non-deleted documents with totals grouped by provider
      final response = await _supabase
          .from('documents')
          .select('provider_id, total_amount, provider:providers(id, name, category)')
          .eq('company_id', _companyId!)
          .eq('status', 'completed')
          .eq('is_duplicate', false)
          .neq('merge_status', 'merged')
          .isFilter('deleted_at', null)
          .gte('document_date', startDate.toIso8601String().split('T')[0])
          .lte('document_date', today.toIso8601String().split('T')[0]);

      // Group by provider and sum amounts
      final Map<String, Map<String, dynamic>> providerTotals = {};
      
      for (final doc in (response as List)) {
        final providerId = doc['provider_id'] as String?;
        if (providerId == null) continue;
        
        final amount = (doc['total_amount'] as num).toDouble();
        final provider = doc['provider'] as Map<String, dynamic>?;
        
        if (providerTotals.containsKey(providerId)) {
          providerTotals[providerId]!['total'] = 
              (providerTotals[providerId]!['total'] as double) + amount;
        } else {
          providerTotals[providerId] = {
            'id': providerId,
            'name': provider?['name'] ?? 'Unknown',
            'category': provider?['category'],
            'total': amount,
          };
        }
      }

      // Sort by total and take top N
      final sortedProviders = providerTotals.values.toList()
        ..sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));

      return sortedProviders
          .take(limit)
          .map(
            (p) => models.ProviderSpending(
                id: p['id'] as String,
                name: p['name'] as String,
                category: p['category'] as String?,
                totalSpent: p['total'] as double,
              ),
          )
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch top providers', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Get provider by ID — always scoped to current company (multi-tenant safety).
  Future<models.Provider?> getProviderById(String id) async {
    if (_companyId == null) return null;

    try {
      final response = await _supabase
          .from('providers')
          .select()
          .eq('id', id)
          .eq('company_id', _companyId!)
          .maybeSingle();

      if (response == null) return null;
      return models.Provider.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch provider', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Create a new provider
  Future<models.Provider?> createProvider({
    required String name,
    String? taxId,
    String? email,
    String? phone,
    String? address,
    String? category,
  }) async {
    if (_companyId == null) return null;

    try {
      final response = await _supabase.from('providers').insert({
        'company_id': _companyId,
        'name': name,
        'tax_id': taxId,
        'email': email,
        'phone': phone,
        'address': address,
        'category': category,
      }).select().single();

      return models.Provider.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create provider', error: e, stackTrace: stackTrace);
      return null;
    }
  }
}
