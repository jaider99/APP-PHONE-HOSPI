import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/providers/company_provider.dart';

import '../data/models/supplier_intelligence_model.dart';

// ─── Supplier list ────────────────────────────────────────────────────────────

/// Search query for the supplier intelligence list.
final supplierSearchQueryProvider = StateProvider.autoDispose<String>(
  (ref) => '',
);

/// All suppliers with aggregated intelligence metrics.
/// Reads from the `v_supplier_intelligence` view, ordered by total_spent DESC.
/// Multi-tenant: always scoped to the current company_id.
final supplierIntelligenceListProvider =
    FutureProvider.autoDispose<List<SupplierIntelligence>>((ref) async {
  // All ref.watch() calls BEFORE the first await (Riverpod 2 rule).
  final search = ref.watch(supplierSearchQueryProvider);

  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];

  var query = SupabaseService.client
      .from('v_supplier_intelligence')
      .select()
      .eq('company_id', companyId)
      .eq('is_active', true);

  if (search.trim().isNotEmpty) {
    query = query.ilike('name', '%${search.trim()}%');
  }

  final response = await query.order('total_spent', ascending: false);

  return (response as List)
      .map((j) => SupplierIntelligence.fromJson(j as Map<String, dynamic>))
      .toList();
});

// ─── Supplier detail ──────────────────────────────────────────────────────────

/// Single supplier with aggregated metrics (from the intelligence view).
final supplierDetailProvider = FutureProvider.autoDispose
    .family<SupplierIntelligence?, String>((ref, supplierId) async {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return null;

  final response = await SupabaseService.client
      .from('v_supplier_intelligence')
      .select()
      .eq('id', supplierId)
      .eq('company_id', companyId)
      .maybeSingle();

  if (response == null) return null;
  return SupplierIntelligence.fromJson(response as Map<String, dynamic>);
});

// ─── Category breakdown ───────────────────────────────────────────────────────

/// Spend breakdown by expense category for a given supplier.
/// Two-step: first fetches document IDs, then queries expenses for categories.
final supplierCategoryBreakdownProvider = FutureProvider.autoDispose
    .family<List<SupplierCategoryBreakdown>, String>((ref, supplierId) async {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];

  // Step 1: all completed document IDs for this supplier
  final docRows = await SupabaseService.client
      .from('documents')
      .select('id')
      .eq('company_id', companyId)
      .eq('provider_id', supplierId)
      .eq('status', 'completed')
      .eq('is_duplicate', false)
      .neq('merge_status', 'merged')
      .isFilter('deleted_at', null);

  final docIds = (docRows as List).map((d) => d['id'] as String).toList();
  if (docIds.isEmpty) return [];

  // Step 2: expenses linked to those documents → category join
  final expRows = await SupabaseService.client
      .from('expenses')
      .select('total_amount, categories(name)')
      .eq('company_id', companyId)
      .inFilter('document_id', docIds)
      .not('total_amount', 'is', null);

  // Group client-side
  final Map<String, _CategoryAccum> accum = {};
  for (final row in (expRows as List)) {
    final amount = (row['total_amount'] as num?)?.toDouble() ?? 0.0;
    final cat = row['categories'] as Map<String, dynamic>?;
    final name = cat?['name'] as String? ?? 'Other';
    final entry = accum.putIfAbsent(
      name,
      () => _CategoryAccum(name: name),
    );
    entry.total += amount;
    entry.count++;
  }

  final list = accum.values
      .map(
        (e) => SupplierCategoryBreakdown(
          categoryName: e.name,
          totalSpent: e.total,
          orderCount: e.count,
        ),
      )
      .toList()
    ..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));

  return list;
});

class _CategoryAccum {
  _CategoryAccum({required this.name});
  final String name;
  double total = 0;
  int count = 0;
}

// ─── Monthly spend ────────────────────────────────────────────────────────────

/// Monthly spending breakdown for a supplier (last 12 months).
/// Used for the trend bar chart in the detail screen.
final supplierMonthlySpendProvider = FutureProvider.autoDispose
    .family<List<SupplierMonthlySpend>, String>((ref, supplierId) async {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];

  final cutoff = DateTime.now().subtract(const Duration(days: 365));

  final rows = await SupabaseService.client
      .from('documents')
      .select('document_date, total_amount')
      .eq('company_id', companyId)
      .eq('provider_id', supplierId)
      .eq('status', 'completed')
      .eq('is_duplicate', false)
      .neq('merge_status', 'merged')
      .not('document_date', 'is', null)
      .not('total_amount', 'is', null)
      .gte('document_date', cutoff.toIso8601String().split('T')[0])
      .order('document_date', ascending: true);

  // Group by year-month client-side
  final Map<String, _MonthAccum> accum = {};
  for (final row in (rows as List)) {
    final date = DateTime.tryParse(row['document_date'] as String);
    if (date == null) continue;
    final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    final entry = accum.putIfAbsent(
      key,
      () => _MonthAccum(year: date.year, month: date.month),
    );
    entry.total += (row['total_amount'] as num?)?.toDouble() ?? 0.0;
    entry.count++;
  }

  final sorted = accum.values.toList()
    ..sort((a, b) {
      final cmp = a.year.compareTo(b.year);
      return cmp != 0 ? cmp : a.month.compareTo(b.month);
    });

  return sorted
      .map(
        (e) => SupplierMonthlySpend(
          year: e.year,
          month: e.month,
          totalSpent: e.total,
          orderCount: e.count,
        ),
      )
      .toList();
});

class _MonthAccum {
  _MonthAccum({required this.year, required this.month});
  final int year;
  final int month;
  double total = 0;
  int count = 0;
}

// ─── Recent documents ─────────────────────────────────────────────────────────

/// Last 10 completed documents linked to a supplier.
final supplierRecentDocumentsProvider = FutureProvider.autoDispose
    .family<List<SupplierDocument>, String>((ref, supplierId) async {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];

  final rows = await SupabaseService.client
      .from('documents')
      .select('id, document_type, document_number, document_date, total_amount, currency')
      .eq('company_id', companyId)
      .eq('provider_id', supplierId)
      .eq('status', 'completed')
      .eq('is_duplicate', false)
      .neq('merge_status', 'merged')
      .isFilter('deleted_at', null)
      .order('document_date', ascending: false)
      .limit(10);

  return (rows as List)
      .map((j) => SupplierDocument.fromJson(j as Map<String, dynamic>))
      .toList();
});
