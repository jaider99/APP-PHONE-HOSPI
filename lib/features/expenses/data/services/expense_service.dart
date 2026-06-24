import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/features/expenses/data/models/expense_model.dart';
import 'package:postgrest/postgrest.dart';

/// Provider for expense service operations
final expenseServiceProvider = Provider<ExpenseService>((ref) {
  return ExpenseService();
});

/// Supabase-backed expense service — all queries scoped by company_id
class ExpenseService {
  /// Create an expense and link the document in a single flow.
  ///
  /// Returns the created expense row (with server-generated id).
  /// Both writes are scoped to [companyId] for tenant isolation.
  Future<Map<String, dynamic>> createExpenseAndLinkDocument({
    required String companyId,
    required String documentId,
    required ExpenseModel expense,
  }) async {
    final supabase = SupabaseService.client;

    // 1. Insert the expense
    final expenseRow = await supabase
        .from('expenses')
        .insert(expense.toInsertJson())
        .select()
        .single();

    final expenseId = expenseRow['id'] as String;

    // 2. Link the document to this expense
    await supabase
        .from('documents')
        .update({
          'expense_id': expenseId,
          'status': 'linked',
        })
        .eq('id', documentId)
        .eq('company_id', companyId);

    return expenseRow;
  }

  /// Fetch categories for this company (future-safe: categories table).
  ///
  /// Falls back to an empty list if the table doesn't exist yet.
  Future<List<ExpenseCategory>> fetchCategories(String companyId) async {
    final supabase = SupabaseService.client;

    try {
      final response = await supabase
          .from('categories')
          .select('id, name, icon, color_hex, parent_id, sort_order, is_active')
          .eq('company_id', companyId)
          .eq('is_active', true)
          .order('sort_order')
          .order('name');

      return (response as List)
          .map((json) =>
              ExpenseCategory.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      // Table may not exist yet — graceful degradation without noisy logs.
      if (e.code == 'PGRST205') {
        return [];
      }
      debugPrint('ExpenseService.fetchCategories: $e');
      return [];
    } catch (e) {
      debugPrint('ExpenseService.fetchCategories: $e');
      return [];
    }
  }

  /// Read grouped expense totals by category for tracker UIs.
  Future<List<ExpenseCategorySummary>> fetchCategorySummaries(
    String companyId,
  ) async {
    final supabase = SupabaseService.client;

    try {
      final response = await supabase
          .from('expenses')
          .select('category_id, total_amount, categories(name, color_hex)')
          .eq('company_id', companyId)
          .not('category_id', 'is', null);

      final grouped = <String, ExpenseCategorySummary>{};
      for (final row in (response as List)) {
        final json = row as Map<String, dynamic>;
        final categoryId = json['category_id'] as String?;
        if (categoryId == null) continue;

        final category = json['categories'] as Map<String, dynamic>?;
        final amount = (json['total_amount'] as num?)?.toDouble() ?? 0;

        final existing = grouped[categoryId];
        if (existing == null) {
          grouped[categoryId] = ExpenseCategorySummary(
            categoryId: categoryId,
            categoryName: category?['name'] as String? ?? 'Uncategorized',
            colorHex: category?['color_hex'] as String?,
            expenseCount: 1,
            totalAmount: amount,
          );
        } else {
          grouped[categoryId] = ExpenseCategorySummary(
            categoryId: existing.categoryId,
            categoryName: existing.categoryName,
            colorHex: existing.colorHex,
            expenseCount: existing.expenseCount + 1,
            totalAmount: existing.totalAmount + amount,
          );
        }
      }

      final result = grouped.values.toList()
        ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
      return result;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205') {
        return [];
      }
      debugPrint('ExpenseService.fetchCategorySummaries: $e');
      return [];
    } catch (e) {
      debugPrint('ExpenseService.fetchCategorySummaries: $e');
      return [];
    }
  }

  /// Fetch a single document by ID (to get extraction results for prefill).
  Future<Map<String, dynamic>?> fetchDocument({
    required String documentId,
    required String companyId,
  }) async {
    final supabase = SupabaseService.client;

    final response = await supabase
        .from('documents')
        .select('*')
        .eq('id', documentId)
        .eq('company_id', companyId)
        .maybeSingle();

    return response;
  }

  // ===========================================================================
  // EXPENSE TRACKER — category breakdown from the documents table
  // ===========================================================================

  /// Fetch per-category expense breakdown from completed documents.
  ///
  /// **Two round-trips, no N+1:**
  ///   1. All completed documents (current month) for [companyId].
  ///   2. Category names + colors for the found category IDs.
  ///
  /// Documents with a null `category_id` are grouped as "Uncategorized".
  /// Returns an empty list when [companyId] is null or no documents exist.
  Future<List<CategorySummary>> fetchDocumentCategorySummaries({
    required String companyId,
  }) async {
    final supabase = SupabaseService.client;
    final now = DateTime.now();
    final startOfMonth =
        DateTime(now.year, now.month, 1).toIso8601String().split('T')[0];

    try {
      // Completed documents for the current month, filtered strictly by
      // `document_date` (the AI-extracted invoice date).
      // Documents without `document_date` are intentionally excluded —
      // using `created_at` as a fallback would place a January invoice
      // uploaded today into the current month, distorting the breakdown.
      //
      // We join the linked expense to prefer expenses.category_id (the
      // user's explicit selection) and fall back to documents.category_id
      // (AI-detected). This ensures old documents uploaded before the
      // documents.category_id fix also display their correct category.
      final docs = await supabase
          .from('documents')
          .select('total_amount, category_id, expenses!expense_id(category_id)')
          .eq('company_id', companyId)
          .eq('status', 'completed')
          .neq('merge_status', 'merged')
          .not('total_amount', 'is', null)
          .not('document_date', 'is', null)
          .isFilter('deleted_at', null)
          .gte('document_date', startOfMonth);

      if ((docs as List).isEmpty) return [];

      double totalExpenses = 0;
      final Map<String?, double> categoryTotals = {};

      for (final doc in docs) {
        final amount = (doc['total_amount'] as num).toDouble();
        // Prefer the expense's category (user-selected) over the document's
        // category (AI-detected). Both should be equal for new uploads; the
        // fallback handles pre-fix rows where documents.category_id was null.
        final expenseObj = doc['expenses'] as Map<String, dynamic>?;
        final categoryId =
            (expenseObj?['category_id'] as String?) ?? (doc['category_id'] as String?);
        totalExpenses += amount;
        categoryTotals[categoryId] =
            (categoryTotals[categoryId] ?? 0) + amount;
      }

      if (totalExpenses == 0) return [];

      // Round-trip 2: names + colors for the categories we found.
      final categoryIds =
          categoryTotals.keys.whereType<String>().toList();
      final Map<String, Map<String, dynamic>> categoryData = {};

      if (categoryIds.isNotEmpty) {
        final cats = await supabase
            .from('categories')
            .select('id, name, color_hex')
            .eq('company_id', companyId)
            .inFilter('id', categoryIds);

        for (final c in (cats as List)) {
          final m = c as Map<String, dynamic>;
          categoryData[m['id'] as String] = m;
        }
      }

      final result = <CategorySummary>[];
      for (final entry in categoryTotals.entries) {
        final categoryId = entry.key;
        final total = entry.value;
        final percentage = total / totalExpenses;

        if (categoryId == null) {
          result.add(CategorySummary(
            categoryId: 'uncategorized',
            name: 'Uncategorized',
            total: total,
            percentage: percentage,
            color: null,
          ));
        } else {
          final cat = categoryData[categoryId];
          result.add(CategorySummary(
            categoryId: categoryId,
            name: cat?['name'] as String? ?? 'Unknown',
            total: total,
            percentage: percentage,
            color: cat?['color_hex'] as String?,
          ));
        }
      }

      result.sort((a, b) => b.total.compareTo(a.total));
      return result;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205') return [];
      debugPrint('ExpenseService.fetchDocumentCategorySummaries: $e');
      return [];
    } catch (e) {
      debugPrint('ExpenseService.fetchDocumentCategorySummaries: $e');
      return [];
    }
  }
}
