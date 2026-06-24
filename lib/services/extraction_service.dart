import 'dart:async';
import 'dart:convert';

import 'package:hospi_dash/core/utils/app_logger.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class ExtractionInvocationException implements Exception {
  final String message;
  final String? errorCode;
  final String? debugPreview;
  final bool remoteFlagged;

  const ExtractionInvocationException({
    required this.message,
    this.errorCode,
    this.debugPreview,
    this.remoteFlagged = true,
  });

  @override
  String toString() => message;
}

enum ExtractionInvocationResult { accepted, completed }

/// Client-side extraction trigger service.
///
/// This service intentionally keeps each request isolated and stateless.
class ExtractionService {
  const ExtractionService();

  Future<ExtractionInvocationResult> invokeProcessDocument({
    required SupabaseClient supabase,
    required String documentId,
    String? companyId,
    String? imageUrl,
    String? currency,
    String? fileName,
  }) async {
    final documentRow = await supabase
        .from('documents')
        .select('company_id')
        .eq('id', documentId)
        .maybeSingle();

    final resolvedCompanyId =
        companyId ?? documentRow?['company_id'] as String?;
    final safeFileName = (fileName != null && fileName.trim().isNotEmpty)
        ? fileName
        : 'document';

    if (resolvedCompanyId == null || resolvedCompanyId.isEmpty) {
      throw Exception('Missing companyId for document $documentId');
    }

    AppLogger.debug(
      '[Extraction][doc=$documentId][file=$safeFileName] invoke process-document',
    );
    AppLogger.debug('[LineItems][doc=$documentId] extraction pipeline started');

    final response = await _invokeWithDetails(
      supabase: supabase,
      functionName: 'process-document',
      body: {
        'documentId': documentId,
      },
      documentId: documentId,
    );

    if (response.status == 202) {
      AppLogger.debug(
        '[Extraction][doc=$documentId] process-document accepted for background processing',
      );
      return ExtractionInvocationResult.accepted;
    }

    if (response.status != 200) {
      throw _buildInvocationException(
        details: response.data,
        status: response.status,
        reasonPhrase: 'Function returned non-200',
        functionName: 'process-document',
        documentId: documentId,
      );
    }

    await _finalizeDocumentType(
      supabase: supabase,
      documentId: documentId,
      companyId: resolvedCompanyId,
    );

    // Fire-and-forget product recognition — matches/creates products and
    // records price history for each line item in the document.
    unawaited(
      supabase.functions
          .invoke(
            'recognize-products',
            body: {'document_id': documentId},
          )
          .then(
            (_) =>
                AppLogger.debug('[ProductMatching][doc=$documentId] invoked'),
          )
          .catchError(
            (e) => AppLogger.warning(
              '[ProductMatching][doc=$documentId] invoke error (non-fatal)',
              error: e,
            ),
          ),
    );

    return ExtractionInvocationResult.completed;
  }

  Future<FunctionResponse> _invokeWithDetails({
    required SupabaseClient supabase,
    required String functionName,
    required Map<String, dynamic> body,
    required String documentId,
  }) async {
    const maxAttempts = 2;

    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        return await supabase.functions.invoke(functionName, body: body);
      } on FunctionException catch (e) {
        final exception = _buildInvocationException(
          details: e.details,
          status: e.status,
          reasonPhrase: e.reasonPhrase,
          functionName: functionName,
          documentId: documentId,
        );
        AppLogger.warning(
          '[Extraction][doc=$documentId] $functionName failed '
          'status=${e.status} reason=${e.reasonPhrase} '
          'code=${exception.errorCode ?? 'unknown'} details=${exception.message}',
        );
        if (exception.debugPreview != null &&
            exception.debugPreview!.isNotEmpty) {
          AppLogger.warning(
            '[Extraction][doc=$documentId] $functionName debugPreview=${exception.debugPreview}',
          );
        }
        throw exception;
      } catch (e, stackTrace) {
        if (!_isRetryableTransportError(e)) {
          Error.throwWithStackTrace(e, stackTrace);
        }

        if (attempt < maxAttempts) {
          AppLogger.warning(
            '[Extraction][doc=$documentId] $functionName transport error; retrying once',
            error: e,
            stackTrace: stackTrace,
          );
          await Future<void>.delayed(const Duration(milliseconds: 600));
          continue;
        }

        AppLogger.warning(
          '[Extraction][doc=$documentId] $functionName transport error after retry',
          error: e,
          stackTrace: stackTrace,
        );
        throw const ExtractionInvocationException(
          message:
              'Extraction request lost connection before the server responded. Tap Re-extract to retry.',
          errorCode: 'transport_connection_closed',
          remoteFlagged: false,
        );
      }
    }

    throw StateError('Unreachable extraction invocation retry state');
  }

  bool _isRetryableTransportError(Object error) {
    if (error is! http.ClientException) return false;

    final message = error.message.toLowerCase();
    return message.contains('connection closed before full header') ||
        message.contains('connection reset') ||
        message.contains('failed host lookup') ||
        message.contains('connection timed out');
  }

  ExtractionInvocationException _buildInvocationException({
    required dynamic details,
    required int? status,
    required String? reasonPhrase,
    required String functionName,
    required String documentId,
  }) {
    final detailsMap =
        details is Map ? Map<String, dynamic>.from(details) : null;
    final debugMap = detailsMap?['debug'] is Map
        ? Map<String, dynamic>.from(detailsMap!['debug'] as Map)
        : null;

    final errorCode = detailsMap?['error']?.toString();
    final debugPreview = debugMap?['responsePreview']?.toString();
    final message = detailsMap?['message']?.toString() ??
        detailsMap?['error']?.toString() ??
        details?.toString() ??
        reasonPhrase ??
        '$functionName returned status ${status ?? 'unknown'}';

    return ExtractionInvocationException(
      message: message,
      errorCode: errorCode,
      debugPreview: debugPreview,
    );
  }

  Future<void> _finalizeDocumentType({
    required SupabaseClient supabase,
    required String documentId,
    required String companyId,
  }) async {
    final row = await supabase
        .from('documents')
        .select('document_type, extraction_clean')
        .eq('id', documentId)
        .eq('company_id', companyId)
        .maybeSingle();

    final extractionClean = _parseJsonMap(row?['extraction_clean']);
    final aiType = _normalizeDocumentType(
      extractionClean?['ai_document_type'] ?? row?['document_type'],
    );
    final confidence = _normalizeConfidence(extractionClean?['confidence']);
    final rawText = (extractionClean?['raw_text'] as String?)?.trim() ?? '';

    var finalType = _detectDocumentType(aiType: aiType, rawText: rawText);

    AppLogger.debug('[TYPE] AI: $aiType');
    AppLogger.debug('[TYPE] FINAL: $finalType rawTextLength=${rawText.length}');

    if ((confidence == 'low' || finalType == 'unknown') && rawText.isNotEmpty) {
      final fallbackType = await _classifyDocumentTypeFromText(
        supabase: supabase,
        rawText: rawText,
        documentId: documentId,
      );
      finalType = _detectDocumentType(aiType: fallbackType, rawText: rawText);

      AppLogger.debug(
        '[TYPE] FINAL: $finalType rawTextLength=${rawText.length}',
      );
    }

    final safeType = finalType.isEmpty ? 'unknown' : finalType;

    await supabase
        .from('documents')
        .update({'document_type': safeType})
        .eq('id', documentId)
        .eq('company_id', companyId);
  }

  Map<String, dynamic>? _parseJsonMap(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      try {
        final decoded = const JsonDecoder().convert(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  String _detectDocumentType({
    required String? aiType,
    required String rawText,
  }) {
    final text = rawText
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');

    if (text.contains('albaran')) {
      return 'delivery_note';
    }

    if (text.contains('factura') || text.contains('invoice')) {
      return 'invoice';
    }

    if (text.contains('iva') &&
        text.contains('total') &&
        text.contains('base')) {
      return 'invoice';
    }

    if (text.contains('ticket') ||
        text.contains('efectivo') ||
        text.contains('tarjeta') ||
        text.contains('visa') ||
        text.contains('mastercard')) {
      return (aiType == null || aiType == 'unknown')
          ? 'expense_ticket'
          : aiType;
    }

    return _normalizeDocumentType(aiType);
  }

  String _normalizeDocumentType(dynamic value) {
    if (value is! String) return 'unknown';
    switch (value.trim().toLowerCase()) {
      case 'invoice':
      case 'delivery_note':
      case 'expense_ticket':
        return value.trim().toLowerCase();
      default:
        return 'unknown';
    }
  }

  String? _normalizeConfidence(dynamic value) {
    if (value is! String) return null;
    switch (value.trim().toLowerCase()) {
      case 'high':
      case 'medium':
      case 'low':
        return value.trim().toLowerCase();
      default:
        return null;
    }
  }

  Future<String> _classifyDocumentTypeFromText({
    required SupabaseClient supabase,
    required String rawText,
    required String documentId,
  }) async {
    try {
      final response = await _invokeWithDetails(
        supabase: supabase,
        functionName: 'classify-document-type',
        body: {'rawText': rawText},
        documentId: documentId,
      );

      final data = response.data;
      if (response.status == 200 && data is Map) {
        return _normalizeDocumentType(data['document_type']);
      }
    } catch (e) {
      AppLogger.warning('[TYPE] Fallback classifier failed', error: e);
    }

    return 'unknown';
  }
}
