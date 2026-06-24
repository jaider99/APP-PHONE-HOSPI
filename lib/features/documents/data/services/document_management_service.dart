import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/providers/documents_provider.dart';
import 'package:hospi_dash/services/extraction_service.dart';

final documentManagementServiceProvider = Provider<DocumentManagementService>((ref) {
  return DocumentManagementService(ref);
});

class DocumentManagementService {
  final Ref _ref;

  DocumentManagementService(this._ref);

  Future<bool> reExtractDocument(String documentId) async {
    final companyId = await _ref.read(companyIdProvider.future);
    if (companyId == null) return false;

    final supabase = SupabaseService.client;

    try {
      await supabase
          .from('documents')
          .update({
            'status': 'processing',
            'notes': null,
            'extraction_started_at': null,
          })
          .eq('id', documentId)
          .eq('company_id', companyId);

      _ref.invalidate(documentsProvider);
      _ref.invalidate(documentCountsProvider);
      _ref.invalidate(documentDetailProvider(documentId));

      await const ExtractionService().invokeProcessDocument(
        supabase: supabase,
        documentId: documentId,
      );

      return true;
    } catch (e) {
      debugPrint('DocumentManagementService.reExtractDocument error: $e');
      return false;
    }
  }
}