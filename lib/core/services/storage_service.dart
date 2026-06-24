import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/auth_service.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/utils/app_logger.dart';
import 'package:hospi_dash/core/utils/result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Provider for storage service
final storageServiceProvider = Provider<StorageService>((ref) {
  final authService = ref.watch(authServiceProvider);
  return StorageService(authService: authService);
});

/// Storage bucket types
enum StorageBucket {
  documents('documents'),
  invoices('invoices'),
  avatars('avatars'),
  companyAssets('company-assets');

  const StorageBucket(this.name);
  final String name;
}

/// Storage service for Supabase Storage operations
/// Multi-tenant aware - organizes files by company_id
class StorageService {
  final AuthService _authService;
  final _supabase = SupabaseService.client;
  final _uuid = const Uuid();

  StorageService({required AuthService authService})
      : _authService = authService;

  /// Get the storage path prefix for current company (multi-tenant)
  String get _companyPrefix {
    final companyId = _authService.currentCompanyId;
    if (companyId == null) {
      throw StateError('No company_id available. User must be authenticated.');
    }
    return companyId;
  }

  /// Upload a file to storage
  /// Returns the public URL of the uploaded file
  Future<Result<String>> uploadFile({
    required File file,
    required StorageBucket bucket,
    String? customPath,
    String? fileName,
  }) async {
    try {
      final extension = file.path.split('.').last;
      final name = fileName ?? '${_uuid.v4()}.$extension';
      final path = customPath != null
          ? '$_companyPrefix/$customPath/$name'
          : '$_companyPrefix/$name';

      await _supabase.storage.from(bucket.name).upload(
            path,
            file,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: false,
            ),
          );

      final publicUrl = _supabase.storage.from(bucket.name).getPublicUrl(path);

      AppLogger.info('File uploaded: $publicUrl');
      return Result.success(publicUrl);
    } on StorageException catch (e) {
      AppLogger.error('Storage upload error', error: e);
      return Result.failure(Exception(e.message));
    } catch (e) {
      AppLogger.error('Upload error', error: e);
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Upload file from bytes
  Future<Result<String>> uploadBytes({
    required List<int> bytes,
    required StorageBucket bucket,
    required String fileName,
    String? customPath,
    String? contentType,
  }) async {
    try {
      final path = customPath != null
          ? '$_companyPrefix/$customPath/$fileName'
          : '$_companyPrefix/$fileName';

      await _supabase.storage.from(bucket.name).uploadBinary(
            path,
            bytes as dynamic,
            fileOptions: FileOptions(
              cacheControl: '3600',
              upsert: false,
              contentType: contentType,
            ),
          );

      final publicUrl = _supabase.storage.from(bucket.name).getPublicUrl(path);

      AppLogger.info('File uploaded: $publicUrl');
      return Result.success(publicUrl);
    } on StorageException catch (e) {
      AppLogger.error('Storage upload error', error: e);
      return Result.failure(Exception(e.message));
    } catch (e) {
      AppLogger.error('Upload error', error: e);
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Delete a file from storage
  Future<Result<void>> deleteFile({
    required StorageBucket bucket,
    required String path,
  }) async {
    try {
      final fullPath = '$_companyPrefix/$path';
      await _supabase.storage.from(bucket.name).remove([fullPath]);

      AppLogger.info('File deleted: $fullPath');
      return const Result.success(null);
    } on StorageException catch (e) {
      AppLogger.error('Storage delete error', error: e);
      return Result.failure(Exception(e.message));
    } catch (e) {
      AppLogger.error('Delete error', error: e);
      return Result.failure(Exception(e.toString()));
    }
  }

  /// List files in a directory
  Future<Result<List<FileObject>>> listFiles({
    required StorageBucket bucket,
    String? path,
  }) async {
    try {
      final fullPath = path != null ? '$_companyPrefix/$path' : _companyPrefix;
      final files = await _supabase.storage.from(bucket.name).list(path: fullPath);

      return Result.success(files);
    } on StorageException catch (e) {
      AppLogger.error('Storage list error', error: e);
      return Result.failure(Exception(e.message));
    } catch (e) {
      AppLogger.error('List error', error: e);
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Get a signed URL for temporary access to a private file
  Future<Result<String>> getSignedUrl({
    required StorageBucket bucket,
    required String path,
    Duration expiresIn = const Duration(hours: 1),
  }) async {
    try {
      final fullPath = '$_companyPrefix/$path';
      final signedUrl = await _supabase.storage
          .from(bucket.name)
          .createSignedUrl(fullPath, expiresIn.inSeconds);

      await _recordAuditEvent(
        action: 'security.storage.signed_url',
        outcome: 'success',
        metadata: {
          'bucket': bucket.name,
          'expires_in_seconds': expiresIn.inSeconds,
        },
      );

      return Result.success(signedUrl);
    } on StorageException catch (e) {
      await _recordAuditEvent(
        action: 'security.storage.signed_url',
        outcome: e.statusCode == '401' || e.statusCode == '403'
            ? 'denied'
            : 'failure',
        metadata: {
          'bucket': bucket.name,
          'status_code': e.statusCode,
          'expires_in_seconds': expiresIn.inSeconds,
        },
      );
      AppLogger.error('Storage signed URL error', error: e);
      return Result.failure(Exception(e.message));
    } catch (e) {
      AppLogger.error('Signed URL error', error: e);
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Download a file as bytes
  Future<Result<List<int>>> downloadFile({
    required StorageBucket bucket,
    required String path,
  }) async {
    try {
      final fullPath = '$_companyPrefix/$path';
      final bytes = await _supabase.storage.from(bucket.name).download(fullPath);

      return Result.success(bytes);
    } on StorageException catch (e) {
      AppLogger.error('Storage download error', error: e);
      return Result.failure(Exception(e.message));
    } catch (e) {
      AppLogger.error('Download error', error: e);
      return Result.failure(Exception(e.toString()));
    }
  }

  Future<void> _recordAuditEvent({
    required String action,
    required String outcome,
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      await _supabase.rpc(
        'record_security_audit_event',
        params: {
          'p_company_id': _companyPrefix,
          'p_action': action,
          'p_entity_type': 'storage_object',
          'p_entity_id': null,
          'p_outcome': outcome,
          'p_correlation_id': null,
          'p_metadata': metadata,
        },
      );
    } catch (error) {
      AppLogger.debug('Storage audit event skipped: ${error.runtimeType}');
    }
  }
}
