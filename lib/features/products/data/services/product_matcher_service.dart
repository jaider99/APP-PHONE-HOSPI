import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:hospi_dash/core/services/supabase_service.dart';

import 'product_normalizer.dart';

final productNormalizerProvider = Provider<ProductNormalizer>((ref) {
  return const ProductNormalizer();
});

final productMatcherServiceProvider = Provider<ProductMatcherService>((ref) {
  return ProductMatcherService(
    SupabaseService.client,
    ref.watch(productNormalizerProvider),
  );
});

class ProductMatchCandidate {
  final String productId;
  final String productName;
  final String? aliasName;
  final double score;
  final String source;

  const ProductMatchCandidate({
    required this.productId,
    required this.productName,
    required this.aliasName,
    required this.score,
    required this.source,
  });

  factory ProductMatchCandidate.fromJson(Map<String, dynamic> json) {
    return ProductMatchCandidate(
      productId: json['product_id'] as String,
      productName: json['product_name'] as String? ?? '',
      aliasName: json['alias_name'] as String?,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      source: json['match_source'] as String? ?? 'unknown',
    );
  }
}

class ProductMatcherService {
  const ProductMatcherService(this._supabase, this._normalizer);

  final SupabaseClient _supabase;
  final ProductNormalizer _normalizer;

  Future<ProductMatchCandidate?> exactAliasMatch(
    String companyId,
    String rawName,
  ) async {
    final normalized = _normalizer.normalizeKey(rawName);
    if (normalized.isEmpty) return null;

    final response = await _supabase.rpc(
      'find_product_alias_match',
      params: {
        'p_company_id': companyId,
        'p_normalized_name': normalized,
      },
    );

    final rows = response as List<dynamic>;
    if (rows.isEmpty) return null;

    return ProductMatchCandidate.fromJson({
      ...rows.first as Map<String, dynamic>,
      'score': 0.99,
      'match_source': 'alias',
    });
  }

  Future<List<ProductMatchCandidate>> fuzzyMatches(
    String companyId,
    String rawName,
  ) async {
    final normalized = _normalizer.normalizeKey(rawName);
    if (normalized.isEmpty) return const [];

    final response = await _supabase.rpc(
      'find_product_candidates',
      params: {
        'p_company_id': companyId,
        'p_normalized_name': normalized,
        'p_limit': 5,
      },
    );

    return (response as List<dynamic>)
        .map((row) => ProductMatchCandidate.fromJson(row as Map<String, dynamic>))
        .toList();
  }
}