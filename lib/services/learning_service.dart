import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final learningServiceProvider = Provider<LearningService>((ref) {
  return LearningService(SupabaseService.client);
});

@immutable
class CategoryAccuracy {
  final int totalPredictions;
  final int correctPredictions;
  final double accuracy;

  const CategoryAccuracy({
    this.totalPredictions = 0,
    this.correctPredictions = 0,
    this.accuracy = 0,
  });
}

class LearningService {
  final SupabaseClient _supabase;

  const LearningService(this._supabase);

  List<String> extractKeywords({
    String? supplierName,
    String? description,
    Iterable<String> lineItems = const [],
  }) {
    final buffer = <String>[
      if (supplierName != null) supplierName,
      if (description != null) description,
      ...lineItems,
    ].join(' ');

    return buffer
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 3)
        .toSet()
        .toList()
      ..sort();
  }

  Future<void> recordCorrection({
    required String documentId,
    required String? supplierName,
    required String confirmedCategoryId,
    String? predictedCategoryId,
    List<String> keywords = const [],
    double confidence = 0.2,
  }) async {
    await _supabase.rpc('record_category_learning', params: {
      'p_document_id': documentId,
      'p_supplier_name': supplierName,
      'p_keywords': keywords,
      'p_predicted_category_id': predictedCategoryId,
      'p_confirmed_category_id': confirmedCategoryId,
      'p_confidence_score': confidence,
    });
  }

  Future<CategoryAccuracy> fetchAccuracy({required String companyId}) async {
    final response = await _supabase.rpc(
      'get_category_accuracy',
      params: {'p_company_id': companyId},
    );

    final rows = response as List<dynamic>? ?? const [];
    if (rows.isEmpty) return const CategoryAccuracy();
    final row = rows.first as Map<String, dynamic>;

    return CategoryAccuracy(
      totalPredictions: (row['total_predictions'] as num?)?.toInt() ?? 0,
      correctPredictions: (row['correct_predictions'] as num?)?.toInt() ?? 0,
      accuracy: (row['accuracy'] as num?)?.toDouble() ?? 0,
    );
  }
}