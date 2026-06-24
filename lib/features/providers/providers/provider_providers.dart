import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/data/models/provider.dart' as models;
import 'package:hospi_dash/providers/company_provider.dart';

/// Search query for the providers list.
final providerSearchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Selected category filter (null = All).
final providerCategoryFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

/// Fetches active providers for the current company.
/// Multi-tenant: scoped by company_id from [companyIdProvider].
final providersListProvider =
    FutureProvider.autoDispose<List<models.Provider>>((ref) async {
  // All synchronous reads BEFORE the first await (Riverpod 2 rule).
  final search = ref.watch(providerSearchQueryProvider);
  final category = ref.watch(providerCategoryFilterProvider);

  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];

  var query = SupabaseService.client
      .from('providers')
      .select()
      .eq('company_id', companyId)
      .eq('is_active', true);

  if (category != null) {
    query = query.eq('category', category);
  }

  if (search.trim().isNotEmpty) {
    query = query.ilike('name', '%${search.trim()}%');
  }

  final response = await query.order('name', ascending: true);

  return (response as List)
      .map((json) => models.Provider.fromJson(json as Map<String, dynamic>))
      .toList();
});

/// Distinct categories present for the current company's providers.
final providerCategoriesProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];

  final response = await SupabaseService.client
      .from('providers')
      .select('category')
      .eq('company_id', companyId)
      .eq('is_active', true)
      .not('category', 'is', null);

  final categories = (response as List)
      .map((r) => r['category'] as String?)
      .where((c) => c != null && c.isNotEmpty)
      .cast<String>()
      .toSet()
      .toList()
    ..sort();

  return categories;
});
