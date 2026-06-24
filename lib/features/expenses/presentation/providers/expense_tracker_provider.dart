import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/features/expenses/data/models/expense_model.dart';
import 'package:hospi_dash/features/expenses/data/services/expense_service.dart';
import 'package:hospi_dash/providers/company_provider.dart';

// =============================================================================
// EXPENSE TRACKER PROVIDERS
// =============================================================================

/// Provides category breakdown derived from completed documents.
///
/// Returns an empty list when:
///   - The company ID is not yet resolved.
///   - No completed documents exist for the current month.
///
/// Supports realtime invalidation via `ref.invalidate(expenseSummaryProvider)`.
final expenseSummaryProvider =
    FutureProvider.autoDispose<List<CategorySummary>>((ref) async {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];

  final service = ref.read(expenseServiceProvider);
  return service.fetchDocumentCategorySummaries(companyId: companyId);
});

/// Convenience provider: total expenses for the current month derived from
/// the summary data (avoids a second Supabase round-trip).
final totalDocumentExpensesProvider =
    FutureProvider.autoDispose<double>((ref) async {
  final summaries = await ref.watch(expenseSummaryProvider.future);
  return summaries.fold<double>(0.0, (sum, s) => sum + s.total);
});
