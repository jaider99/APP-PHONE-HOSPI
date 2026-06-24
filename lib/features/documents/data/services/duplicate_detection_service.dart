import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/utils/document_duplicate_normalizer.dart';

class DuplicateResult {
  const DuplicateResult._({
    required this.isDuplicate,
    this.existingDocumentId,
    this.normalizedDocumentNumber,
    this.normalizedSupplier,
  });

  final bool isDuplicate;
  final String? existingDocumentId;
  final String? normalizedDocumentNumber;
  final String? normalizedSupplier;

  factory DuplicateResult.unique({
    required String normalizedDocumentNumber,
    required String normalizedSupplier,
  }) {
    return DuplicateResult._(
      isDuplicate: false,
      normalizedDocumentNumber: normalizedDocumentNumber,
      normalizedSupplier: normalizedSupplier,
    );
  }

  factory DuplicateResult.duplicate(
    String existingDocumentId, {
    required String normalizedDocumentNumber,
    required String normalizedSupplier,
  }) {
    return DuplicateResult._(
      isDuplicate: true,
      existingDocumentId: existingDocumentId,
      normalizedDocumentNumber: normalizedDocumentNumber,
      normalizedSupplier: normalizedSupplier,
    );
  }
}

class DuplicateDetectionService {
  Future<DuplicateResult> checkDuplicate({
    required String companyId,
    required String? documentNumber,
    required String? supplierName,
    double? totalAmount,
    DateTime? documentDate,
    String? excludeDocumentId,
  }) async {
    final normalizedSupplier = normalizeSupplierName(supplierName);
    final normalizedDocumentNumber = buildNormalizedDuplicateKey(
      documentNumber: documentNumber,
      totalAmount: totalAmount,
      documentDate: documentDate,
      supplierName: supplierName,
    );

    if (normalizedSupplier.isEmpty || normalizedDocumentNumber.isEmpty) {
      return DuplicateResult.unique(
        normalizedDocumentNumber: normalizedDocumentNumber,
        normalizedSupplier: normalizedSupplier,
      );
    }

    final existing = await SupabaseService.client
        .from('documents')
        .select('id')
        .eq('company_id', companyId)
        .eq('normalized_document_number', normalizedDocumentNumber)
        .eq('normalized_supplier', normalizedSupplier)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: true);

    final matches = (existing as List)
        .whereType<Map<String, dynamic>>()
        .where((row) => row['id'] != excludeDocumentId)
        .toList();

    if (matches.isNotEmpty) {
      return DuplicateResult.duplicate(
        matches.first['id'] as String,
        normalizedDocumentNumber: normalizedDocumentNumber,
        normalizedSupplier: normalizedSupplier,
      );
    }

    return DuplicateResult.unique(
      normalizedDocumentNumber: normalizedDocumentNumber,
      normalizedSupplier: normalizedSupplier,
    );
  }
}