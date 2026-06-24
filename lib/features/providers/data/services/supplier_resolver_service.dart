import 'package:hospi_dash/core/services/supabase_service.dart';

/// Client-side Dart wrapper around the `resolve_supplier` Postgres RPC.
///
/// Primary use: manually re-link a document to a different supplier, or
/// pre-resolve a supplier name before creating a document record.
///
/// The happy-path (OCR → documents.status = 'completed') is handled entirely
/// server-side by the `auto_resolve_supplier` Postgres trigger, so Flutter
/// only needs this service for manual overrides.
class SupplierResolverService {
  const SupplierResolverService();

  /// Resolves [rawName] to a canonical provider ID for [companyId].
  ///
  /// Internally calls the `resolve_supplier` Postgres RPC which:
  ///   1. Checks the alias cache (O(1) lookup for repeated raw names)
  ///   2. Tries fuzzy trgm matching ≥ 85 % similarity
  ///   3. Auto-creates a new provider if no match found
  ///
  /// Returns the `provider_id` UUID string, or `null` on error/empty name.
  Future<String?> resolve(
    String companyId,
    String rawName, {
    String? taxId,
  }) async {
    if (rawName.trim().isEmpty) return null;

    try {
      final result = await SupabaseService.client.rpc(
        'resolve_supplier',
        params: {
          'p_company_id': companyId,
          'p_raw_name':   rawName.trim(),
          if (taxId != null && taxId.trim().isNotEmpty) 'p_tax_id': taxId.trim(),
        },
      );
      return result as String?;
    } catch (e) {
      return null;
    }
  }

  /// Re-links [documentId] to the canonical provider for [rawSupplierName].
  ///
  /// Useful when a user wants to override an incorrect automatic match.
  Future<bool> relinkDocument({
    required String companyId,
    required String documentId,
    required String rawSupplierName,
    String? taxId,
  }) async {
    final providerId = await resolve(companyId, rawSupplierName, taxId: taxId);
    if (providerId == null) return false;

    try {
      await SupabaseService.client
          .from('documents')
          .update({'provider_id': providerId})
          .eq('id', documentId)
          .eq('company_id', companyId);
      return true;
    } catch (_) {
      return false;
    }
  }
}
