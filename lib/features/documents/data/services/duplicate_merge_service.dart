import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/config/env_config.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/models/document_model.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

final duplicateMergeServiceProvider = Provider<DuplicateMergeService>((ref) {
  return DuplicateMergeService(SupabaseService.client);
});

class MergeDecisionResult {
  const MergeDecisionResult({
    required this.status,
    required this.confidence,
    required this.method,
    required this.reason,
    required this.breakdown,
    this.targetDocumentId,
    this.aiConfidence,
  });

  final DocumentMergeStatus status;
  final double confidence;
  final String method;
  final String reason;
  final Map<String, double> breakdown;
  final String? targetDocumentId;
  final double? aiConfidence;
}

class DuplicateMergeService {
  DuplicateMergeService(this._supabase);

  final SupabaseClient _supabase;
  static const String _openRouterUrl = 'https://openrouter.ai/api/v1/chat/completions';
  static const String _textModel = 'nvidia/nemotron-3-super-120b-a12b:free';
  static const double _aiMinScore = 0.6;
  static const double _aiMaxScore = 0.85;
  static const double _reviewThreshold = 0.75;
  static const double _mergeThreshold = 0.9;

  Future<MergeDecisionResult> evaluate({
    required DocumentModel a,
    required DocumentModel b,
    required String companyId,
  }) async {
    if (a.companyId != companyId || b.companyId != companyId) {
      throw ArgumentError('Cross-company merge evaluation is not allowed.');
    }

    final breakdown = <String, double>{
      'document_number': _scoreDocumentNumber(a, b),
      'supplier': _stringSimilarity(a.supplierName, b.supplierName),
      'amount': _scoreAmount(a.totalAmount, b.totalAmount),
      'date': _scoreDate(a.documentDate, b.documentDate),
      'items': _scoreItems(a.lineItems, b.lineItems),
    };

    final heuristicScore =
        0.35 * breakdown['document_number']! +
        0.25 * breakdown['supplier']! +
        0.20 * breakdown['amount']! +
        0.10 * breakdown['date']! +
        0.10 * breakdown['items']!;

    var finalScore = heuristicScore;
    var method = breakdown['document_number'] == 1 && breakdown['supplier'] == 1
        ? 'deterministic'
        : 'heuristic';
    var reason = 'Heuristic merge score computed from document metadata.';
    double? aiConfidence;

    if (heuristicScore >= _aiMinScore && heuristicScore <= _aiMaxScore) {
      final aiResult = await _validateWithAi(a, b);
      if (aiResult != null) {
        aiConfidence = aiResult.$1;
        final sameDocument = aiResult.$2;
        finalScore = (heuristicScore * 0.7) + (aiConfidence * 0.3);
        method = 'ai';
        reason = aiResult.$3;
        if (!sameDocument) {
          finalScore = min(finalScore, 0.74);
        }
      }
    }

    final status = finalScore >= _mergeThreshold
        ? DocumentMergeStatus.merged
        : finalScore >= _reviewThreshold
            ? DocumentMergeStatus.review
            : DocumentMergeStatus.none;

    return MergeDecisionResult(
      status: status,
      confidence: finalScore,
      method: method,
      reason: reason,
      breakdown: breakdown,
      targetDocumentId: b.id,
      aiConfidence: aiConfidence,
    );
  }

  Future<void> mergeDocuments({
    required String companyId,
    required String sourceDocumentId,
    required String targetDocumentId,
    required double confidence,
    required String method,
    required String reason,
  }) async {
    await _supabase.rpc(
      'merge_documents_for_company',
      params: {
        'p_company_id': companyId,
        'p_source_document_id': sourceDocumentId,
        'p_target_document_id': targetDocumentId,
        'p_confidence': confidence,
        'p_method': method,
        'p_reason': reason,
      },
    );
  }

  Future<void> keepSeparate({
    required String companyId,
    required String documentId,
  }) async {
    await _supabase.rpc(
      'keep_document_separate',
      params: {
        'p_company_id': companyId,
        'p_document_id': documentId,
      },
    );
  }

  double _scoreDocumentNumber(DocumentModel a, DocumentModel b) {
    final left = _normalizeDocNumber(a.documentNumber);
    final right = _normalizeDocNumber(b.documentNumber);
    if (left.isEmpty || right.isEmpty) return 0;
    return left == right ? 1 : 0;
  }

  double _scoreAmount(double? left, double? right) {
    if (left == null || right == null) return 0;
    final delta = (left - right).abs();
    if (delta == 0) return 1;
    if (delta < 1) return 0.9;
    if (delta < 5) return 0.7;
    return 0;
  }

  double _scoreDate(DateTime? left, DateTime? right) {
    if (left == null || right == null) return 0;
    final days = left.difference(right).inDays.abs();
    if (days == 0) return 1;
    if (days <= 2) return 0.8;
    if (days < 7) return 0.5;
    return 0;
  }

  double _scoreItems(List<DocumentLineItem> left, List<DocumentLineItem> right) {
    if (left.isEmpty || right.isEmpty) return 0;
    final leftKeys = left
        .map((item) => '${_normalizeText(item.description)}:${item.lineTotal?.toStringAsFixed(2) ?? ''}')
        .where((value) => value != ':')
        .toSet();
    final rightKeys = right
        .map((item) => '${_normalizeText(item.description)}:${item.lineTotal?.toStringAsFixed(2) ?? ''}')
        .where((value) => value != ':')
        .toSet();
    if (leftKeys.isEmpty || rightKeys.isEmpty) return 0;
    final overlap = leftKeys.intersection(rightKeys).length;
    return overlap / max(leftKeys.length, rightKeys.length);
  }

  String _normalizeDocNumber(String? value) {
    return (value ?? '').trim().toUpperCase().replaceAll(RegExp(r'[\s\-/]'), '');
  }

  String _normalizeText(String? value) {
    return (value ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _stringSimilarity(String? left, String? right) {
    final a = _normalizeText(left);
    final b = _normalizeText(right);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final distance = _levenshtein(a, b);
    return max(0, 1 - distance / max(a.length, b.length));
  }

  int _levenshtein(String left, String right) {
    final rows = left.length + 1;
    final cols = right.length + 1;
    final matrix = List.generate(
      rows,
      (row) => List.generate(cols, (col) => row == 0 ? col : col == 0 ? row : 0),
    );

    for (var row = 1; row < rows; row++) {
      for (var col = 1; col < cols; col++) {
        final cost = left[row - 1] == right[col - 1] ? 0 : 1;
        matrix[row][col] = min(
          min(matrix[row - 1][col] + 1, matrix[row][col - 1] + 1),
          matrix[row - 1][col - 1] + cost,
        );
      }
    }

    return matrix[left.length][right.length];
  }

  Future<(double, bool, String)?> _validateWithAi(
    DocumentModel a,
    DocumentModel b,
  ) async {
    const apiKey = String.fromEnvironment('OPENROUTER_API_KEY');
    if (apiKey.isEmpty) return null;

    final response = await http.post(
      Uri.parse(_openRouterUrl),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': EnvConfig.apiBaseUrl,
        'X-Title': 'HospiDash Duplicate Merge Review',
      },
      body: jsonEncode({
        'model': _textModel,
        'temperature': 0,
        'messages': [
          {
            'role': 'system',
            'content': 'You are a financial document validator.'
          },
          {
            'role': 'user',
            'content': '''You are a financial document validator.

Determine if these two documents are the SAME invoice.

Return ONLY:
{
  "same_document": true/false,
  "confidence": 0-1,
  "reason": "short explanation"
}

${jsonEncode({'docA': _toAiPayload(a), 'docB': _toAiPayload(b)})}''',
          },
        ],
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = ((body['choices'] as List?)?.first as Map<String, dynamic>?)?['message']
        as Map<String, dynamic>?;
    final raw = content?['content'] as String?;
    if (raw == null || raw.isEmpty) return null;

    final parsed = _extractJson(raw);
    if (parsed == null) return null;

    final confidence = min(
      1.0,
      max(0.0, (parsed['confidence'] as num?)?.toDouble() ?? 0),
    );
    final sameDocument = parsed['same_document'] == true;
    final reason = parsed['reason'] as String? ?? 'AI validator did not explain the result.';
    return (confidence, sameDocument, reason);
  }

  Map<String, dynamic> _toAiPayload(DocumentModel document) {
    return {
      'id': document.id,
      'supplier_name': document.supplierName,
      'document_number': document.documentNumber,
      'document_date': document.documentDate?.toIso8601String().split('T').first,
      'total_amount': document.totalAmount,
      'currency': document.currency,
      'line_items': document.lineItems
          .map((item) => {
                'description': item.description,
                'quantity': item.quantity,
                'line_total': item.lineTotal,
              })
          .toList(),
    };
  }

  Map<String, dynamic>? _extractJson(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      return decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      return null;
    }
  }
}