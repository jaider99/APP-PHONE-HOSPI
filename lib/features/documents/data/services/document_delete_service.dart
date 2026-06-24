import 'package:flutter/foundation.dart';
import 'package:hospi_dash/core/config/env_config.dart';
import 'package:hospi_dash/core/utils/app_logger.dart';
import 'package:hospi_dash/services/step_up_auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class DocumentDeleteException implements Exception {
  const DocumentDeleteException(
    this.message, {
    required this.stage,
    this.retryable = false,
  });

  final String message;
  final String stage;
  final bool retryable;

  @override
  String toString() => message;
}

class DocumentDeleteService {
  DocumentDeleteService(this.supabase,
      {required StepUpAuthService stepUpAuthService})
      : _stepUpAuthService = stepUpAuthService;

  final SupabaseClient supabase;
  final StepUpAuthService _stepUpAuthService;

  Future<void> deleteDocument({
    required String documentId,
    required String companyId,
    required String filePath,
  }) async {
    debugPrint('[DELETE] Starting local auth (optional)');
    await _stepUpAuthService.requireStepUp(
      action: StepUpAction.deleteDocument,
      required: false,
    );
    debugPrint('[DELETE] Local auth gate passed (success or skipped)');

    debugPrint('[DELETE] Verifying document ownership');
    final Map<String, dynamic>? doc;
    try {
      doc = await supabase
          .from('documents')
          .select('id, file_url, file_path, company_id, deleted_at')
          .eq('id', documentId)
          .eq('company_id', companyId)
          .isFilter('deleted_at', null)
          .maybeSingle();
    } on PostgrestException catch (e) {
      debugPrint('[DELETE ERROR] Supabase verify failed: ${e.code}');
      if (_isPermissionDenied(e)) {
        throw const DocumentDeleteException(
          'You do not have permission to delete this document.',
          stage: 'permission',
        );
      }
      throw const DocumentDeleteException(
        "We couldn't delete this document. Please try again.",
        stage: 'verify',
        retryable: true,
      );
    }

    if (doc == null) {
      throw const DocumentDeleteException(
        'You do not have permission to delete this document.',
        stage: 'verify',
      );
    }

    final resolvedPath = _resolveStoragePath(
      companyId: companyId,
      explicitFilePath: filePath,
      dbFilePath: doc['file_path'] as String?,
      fileUrl: doc['file_url'] as String?,
    );

    if (resolvedPath == null || resolvedPath.isEmpty) {
      throw const DocumentDeleteException(
        'Could not resolve the stored file path for this document.',
        stage: 'verify',
      );
    }

    debugPrint('[DELETE] Deleting storage file');
    await _deleteStorageFile(resolvedPath);
    debugPrint('[DELETE] Storage delete success');

    try {
      debugPrint('[DELETE] Calling Supabase delete');
      await supabase.rpc(
        'delete_document_cascade',
        params: {
          'p_document_id': documentId,
          'p_company_id': companyId,
        },
      );
      debugPrint('[DELETE] Supabase delete success');
    } on PostgrestException catch (e) {
      debugPrint('[DELETE ERROR] Supabase delete failed: ${e.code}');
      if (_isPermissionDenied(e)) {
        throw const DocumentDeleteException(
          'You do not have permission to delete this document.',
          stage: 'permission',
        );
      }
      throw const DocumentDeleteException(
        "We couldn't delete this document. Please try again.",
        stage: 'db_cleanup',
        retryable: true,
      );
    } catch (e) {
      debugPrint('[DELETE ERROR] Supabase delete failed: $e');
      throw const DocumentDeleteException(
        "We couldn't delete this document. Please try again.",
        stage: 'db_cleanup',
        retryable: true,
      );
    }
  }

  String extractStoragePath(String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    final index = segments.lastIndexOf('documents');
    if (index == -1 || index + 1 >= segments.length) {
      throw const DocumentDeleteException(
        'Invalid storage URL for this document.',
        stage: 'verify',
      );
    }
    return segments.sublist(index + 1).join('/');
  }

  String? _resolveStoragePath({
    required String companyId,
    required String explicitFilePath,
    required String? dbFilePath,
    required String? fileUrl,
  }) {
    final inlinePath = explicitFilePath.trim();
    final persistedPath = (dbFilePath ?? '').trim();

    final resolved = inlinePath.isNotEmpty
        ? inlinePath
        : persistedPath.isNotEmpty
            ? persistedPath
            : ((fileUrl != null && fileUrl.trim().isNotEmpty)
                ? extractStoragePath(fileUrl)
                : null);

    if (resolved == null || resolved.isEmpty) return null;
    if (!resolved.startsWith('$companyId/')) {
      throw const DocumentDeleteException(
        'Document path does not belong to the active company.',
        stage: 'verify',
      );
    }
    return resolved;
  }

  Future<String> _resolveAccessToken() async {
    var session = supabase.auth.currentSession;
    if (session == null) {
      throw const DocumentDeleteException(
        'Your session expired. Please sign in again.',
        stage: 'auth',
      );
    }

    final expiresAt = session.expiresAt;
    final expiresInSeconds = expiresAt == null
        ? 0
        : DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
            .difference(DateTime.now())
            .inSeconds;

    if (expiresInSeconds > 120) {
      return session.accessToken;
    }

    try {
      final refreshed = await supabase.auth.refreshSession();
      session = refreshed.session;
      if (session != null) {
        return session.accessToken;
      }
    } catch (e) {
      AppLogger.warning('[DocumentDeleteService] Token refresh failed',
          error: e);
    }

    throw const DocumentDeleteException(
      'Your session expired. Please sign in again.',
      stage: 'auth',
    );
  }

  Future<void> _deleteStorageFile(String path) async {
    final accessToken = await _resolveAccessToken();
    final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
    final response = await http.delete(
      Uri.parse(
          '${EnvConfig.supabaseUrl}/storage/v1/object/documents/$encodedPath'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'apikey': EnvConfig.supabaseAnonKey,
      },
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      debugPrint(
          '[DELETE ERROR] Storage delete denied: ${response.statusCode}');
      throw const DocumentDeleteException(
        'You do not have permission to delete this document.',
        stage: 'permission',
      );
    }

    final body = response.body.toLowerCase();
    if (response.statusCode == 404 ||
        body.contains('not found') ||
        body.contains('no such object')) {
      AppLogger.info('[DocumentDeleteService] Storage file already missing');
      return;
    }

    throw const DocumentDeleteException(
      "We couldn't delete this document. Please try again.",
      stage: 'storage',
      retryable: true,
    );
  }

  bool _isPermissionDenied(PostgrestException error) {
    final code = (error.code ?? '').toLowerCase();
    final message = error.message.toLowerCase();
    return code == '42501' ||
        message.contains('permission denied') ||
        message.contains('not authorized') ||
        message.contains('unauthorized');
  }
}
