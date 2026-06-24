import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/features/expenses/data/models/expense_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final categoryAiServiceProvider = Provider<CategoryAiService>((ref) {
  return CategoryAiService(SupabaseService.client);
});

enum CategorySuggestionState {
  none,
  autoApplied,
  suggested,
  needsReview,
}

@immutable
class LearningSignal {
  final String? supplierName;
  final String? normalizedSupplier;
  final List<String> keywords;
  final String? predictedCategoryId;
  final String? confirmedCategoryId;
  final double confidenceScore;
  final DateTime? createdAt;

  const LearningSignal({
    this.supplierName,
    this.normalizedSupplier,
    this.keywords = const [],
    this.predictedCategoryId,
    this.confirmedCategoryId,
    this.confidenceScore = 0,
    this.createdAt,
  });

  factory LearningSignal.fromJson(Map<String, dynamic> json) {
    return LearningSignal(
      supplierName: json['supplier_name'] as String?,
      normalizedSupplier: json['normalized_supplier'] as String?,
      keywords: (json['keywords'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      predictedCategoryId: json['predicted_category_id'] as String?,
      confirmedCategoryId: json['confirmed_category_id'] as String?,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }
}

@immutable
class CategoryPrediction {
  final String? categoryId;
  final String? categoryName;
  final double confidence;
  final CategorySuggestionState state;
  final String source;

  const CategoryPrediction({
    this.categoryId,
    this.categoryName,
    this.confidence = 0,
    this.state = CategorySuggestionState.none,
    this.source = 'none',
  });
}

class CategoryAiService {
  final SupabaseClient _supabase;

  const CategoryAiService(this._supabase);

  Future<List<LearningSignal>> fetchHistory({
    required String companyId,
    String? supplier,
    List<String> keywords = const [],
  }) async {
    final normalizedSupplier = _normalize(supplier);
    final query = await _supabase
        .from('category_learning')
        .select(
          'supplier_name, normalized_supplier, keywords, predicted_category_id, confirmed_category_id, confidence_score, created_at',
        )
        .eq('company_id', companyId)
        .order('created_at', ascending: false)
        .limit(30);

    final rows = (query as List)
        .map((row) => LearningSignal.fromJson(row as Map<String, dynamic>))
        .where((signal) {
      final matchesSupplier = normalizedSupplier != null &&
          signal.normalizedSupplier == normalizedSupplier;
      final matchesKeyword = keywords.isNotEmpty &&
          signal.keywords.any(keywords.contains);
      return matchesSupplier || matchesKeyword ||
          (normalizedSupplier == null && keywords.isEmpty);
    }).toList();

    return rows;
  }

  Future<CategoryPrediction> classify({
    required String supplier,
    required String description,
    required List<ExpenseCategory> categories,
    required List<LearningSignal> history,
  }) async {
    if (categories.isEmpty) {
      return const CategoryPrediction();
    }

    final normalizedSupplier = _normalize(supplier);
    final supplierMatch = history.firstWhere(
      (signal) => signal.normalizedSupplier != null &&
          signal.normalizedSupplier == normalizedSupplier &&
          signal.confirmedCategoryId != null,
      orElse: () => const LearningSignal(),
    );

    if (supplierMatch.confirmedCategoryId != null) {
      return CategoryPrediction(
        categoryId: supplierMatch.confirmedCategoryId,
        categoryName: resolveCategoryName(categories, supplierMatch.confirmedCategoryId),
        confidence: 0.94,
        state: CategorySuggestionState.autoApplied,
        source: 'supplier_history',
      );
    }

    final tokens = _extractKeywords('$supplier $description');
    final votes = <String, double>{};
    for (final signal in history) {
      final categoryId = signal.confirmedCategoryId;
      if (categoryId == null) continue;

      final overlap = signal.keywords.where(tokens.contains).length;
      if (overlap == 0) continue;

      votes[categoryId] =
          (votes[categoryId] ?? 0) + overlap + signal.confidenceScore;
    }

    if (votes.isEmpty) {
      return const CategoryPrediction();
    }

    final winner = votes.entries.reduce(
      (left, right) => left.value >= right.value ? left : right,
    );
    final confidence = (0.5 + (winner.value / 10)).clamp(0.5, 0.84).toDouble();

    return CategoryPrediction(
      categoryId: winner.key,
      categoryName: resolveCategoryName(categories, winner.key),
      confidence: confidence,
      state: CategorySuggestionState.suggested,
      source: 'keyword_history',
    );
  }

  CategorySuggestionState suggestionState({
    required String? categoryId,
    required String? aiCategoryId,
    required double confidence,
  }) {
    if (aiCategoryId == null) return CategorySuggestionState.none;
    if (categoryId != null && categoryId == aiCategoryId && confidence >= 0.85) {
      return CategorySuggestionState.autoApplied;
    }
    if (categoryId == null && confidence >= 0.5) {
      return CategorySuggestionState.suggested;
    }
    if (categoryId == null) {
      return CategorySuggestionState.needsReview;
    }
    return CategorySuggestionState.none;
  }

  String? resolveCategoryName(List<ExpenseCategory> categories, String? categoryId) {
    if (categoryId == null) return null;
    for (final category in categories) {
      if (category.id == categoryId) return category.name;
    }
    return null;
  }

  String? _normalize(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.isEmpty ? null : normalized;
  }

  List<String> _extractKeywords(String value) {
    final tokens = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 3)
        .toSet()
        .toList();
    tokens.sort();
    return tokens;
  }
}