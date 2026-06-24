import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/config/env_config.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/utils/app_logger.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

/// Provider for StorageService
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

// =============================================================================
// RESULT TYPES
// =============================================================================

enum StorageFailureReason {
  authRequired,
  bucketNotFound,
  permissionDenied,
  fileTooLarge,
  invalidFileType,
  conflict,
  network,
  timeout,
  noCompany,
  unknown,
}

enum StorageHealthStatus {
  ok,
  skipped,
  timedOut,
  unauthenticated,
  networkUnavailable,
  permissionDenied,
  bucketUnavailable,
  unknownError,
}

class StorageHealthResult {
  final StorageHealthStatus status;
  final String? message;
  final Object? error;
  final String? stage;

  const StorageHealthResult({
    required this.status,
    this.message,
    this.error,
    this.stage,
  });

  bool get ok => status == StorageHealthStatus.ok;
}

sealed class StorageUploadResult {
  const StorageUploadResult();
}

class StorageUploadSuccess extends StorageUploadResult {
  final String url;
  final String path;
  final String documentId;
  final String mimeType;
  const StorageUploadSuccess({
    required this.url,
    required this.path,
    required this.documentId,
    required this.mimeType,
  });
}

class StorageUploadFailure extends StorageUploadResult {
  final String message;
  final StorageFailureReason reason;
  const StorageUploadFailure(this.message, this.reason);
}

class StorageAuthRequiredException implements Exception {
  const StorageAuthRequiredException();

  @override
  String toString() => 'Authenticated session required for document storage.';
}

// =============================================================================
// SERVICE
// =============================================================================

/// Service for managing document file uploads to Supabase Storage
class StorageService {
  static const String _bucket = 'documents';
  static const String _salesImportsBucket = 'sales-imports';
  static const int _maxFileSizeBytes = 10 * 1024 * 1024; // 10MB
  static const int _maxImageSizeBytes = 4 * 1024 * 1024; // 4MB before compress
  static const int _maxImageDimension = 2400;
  static const int _imageQuality = 92;
  static const Duration _authRefreshTimeout = Duration(seconds: 8);
  static const Duration _storageReadTimeout = Duration(seconds: 20);
  static const Duration _storageUploadTimeout = Duration(seconds: 90);

  static const Set<String> _allowedMimes = {
    'image/jpeg', 'image/png', 'image/webp',
    'image/heic', 'application/pdf',
  };

  static const Set<String> _allowedSalesImportMimes = {
    'image/jpeg', 'image/png', 'image/webp', 'application/pdf', 'text/csv',
  };

  final _supabase = SupabaseService.client;
  final _uuid = const Uuid();

  Future<String> _resolveAccessToken() async {
    var session = _supabase.auth.currentSession;
    if (session == null) {
      throw const StorageAuthRequiredException();
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
      final refreshed = await _supabase.auth
          .refreshSession()
          .timeout(_authRefreshTimeout);
      session = refreshed.session;
      if (session != null) {
        AppLogger.debug('[StorageService] Refreshed expired/near-expiry auth token');
        return session.accessToken;
      }
    } catch (e) {
      AppLogger.warning('[StorageService] Token refresh failed', error: e);
    }

    throw const StorageAuthRequiredException();
  }

  /// Upload a document file to Supabase Storage
  Future<StorageUploadResult> uploadDocument({
    required String companyId,
    required String fileName,
    required Uint8List fileBytes,
    required String mimeType,
    String? documentId,
    void Function(double progress)? onProgress,
  }) async {
    // ── Precondition guards ─────────────────────────────
    if (companyId.isEmpty) {
      return const StorageUploadFailure(
        'No active company. Please sign in again.',
        StorageFailureReason.noCompany,
      );
    }

    if (fileBytes.length > _maxFileSizeBytes) {
      return const StorageUploadFailure(
        'File is too large. Maximum size is 10 MB.',
        StorageFailureReason.fileTooLarge,
      );
    }

    if (!_allowedMimes.contains(mimeType)) {
      return StorageUploadFailure(
        'File type "$mimeType" not supported. Use JPG, PNG, WebP, HEIC, or PDF.',
        StorageFailureReason.invalidFileType,
      );
    }

    // ── Generate path ───────────────────────────────────
    final resolvedDocumentId = documentId ?? _uuid.v4();
    final sanitizedFileName = _sanitizeFileName(fileName);
    final storagePath = '$companyId/$resolvedDocumentId/$sanitizedFileName';

    AppLogger.debug(
      '[StorageService] uploadDocument START bucket=$_bucket '
      'mimeType=$mimeType fileSize=${fileBytes.length} '
      'hasSession=${_supabase.auth.currentSession != null}',
    );

    // ── Compress image if needed ────────────────────────
    Uint8List bytesToUpload = fileBytes;
    String finalMimeType = mimeType;

    if (_isImage(mimeType) && fileBytes.length > _maxImageSizeBytes) {
      final compressed = await _compressImage(fileBytes, mimeType);
      if (compressed != null) {
        bytesToUpload = compressed;
        finalMimeType = 'image/jpeg';
        AppLogger.debug('[StorageService] compressed image bytes=${bytesToUpload.length}');
      }
    }

    // ── Upload (direct HTTP to bypass storage_client URL transform) ───
    // storage_client 2.5.0 transforms *.supabase.co/storage/v1 to
    // *.storage.supabase.co/v1 which may not exist for all projects.
    try {
      final accessToken = await _resolveAccessToken();
      final storageUrl = '${EnvConfig.supabaseUrl}/storage/v1';
      final uploadUrl = '$storageUrl/object/$_bucket/$storagePath';

      AppLogger.debug('[StorageService] upload request prepared');

      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl))
        ..headers['Authorization'] = 'Bearer $accessToken'
        ..headers['apikey'] = EnvConfig.supabaseAnonKey
        ..headers['x-upsert'] = 'true'
        ..fields['cacheControl'] = '3600'
        ..files.add(http.MultipartFile.fromBytes(
          '',
          bytesToUpload,
          filename: sanitizedFileName,
          contentType: MediaType.parse(finalMimeType),
        ),);

        final streamedResponse = await request.send().timeout(_storageUploadTimeout);
        final response = await http.Response
          .fromStream(streamedResponse)
          .timeout(_storageReadTimeout);

      AppLogger.debug('[StorageService] upload response status=${response.statusCode}');

      if (response.statusCode < 200 || response.statusCode > 299) {
        final code = response.statusCode;
        String message;
        StorageFailureReason reason;

        if (code == 404) {
          message = 'Storage bucket not found. Contact support.';
          reason = StorageFailureReason.bucketNotFound;
        } else if (code == 403 || code == 401) {
          message = 'Upload permission denied. Check your account access.';
          reason = StorageFailureReason.permissionDenied;
        } else if (code == 409) {
          message = 'A file with this name already exists.';
          reason = StorageFailureReason.conflict;
        } else {
          message = 'Upload failed ($code). Please try again.';
          reason = StorageFailureReason.unknown;
        }

        AppLogger.warning('[StorageService] Upload failed status=$code reason=$reason');
        return StorageUploadFailure(message, reason);
      }

      // Generate a long-lived signed URL (1 year) so previews work instantly
      // without a separate on-demand fetch. The bucket is private, so public
      // URLs are inaccessible.
      final signedUrl = await getSignedUrl(storagePath, expiresIn: 31536000);
      final previewUrl = signedUrl ?? '${EnvConfig.supabaseUrl}/storage/v1/object/public/$_bucket/$storagePath';

      AppLogger.info('[StorageService] uploadDocument SUCCESS');

      return StorageUploadSuccess(
        url: previewUrl,
        path: storagePath,
        documentId: resolvedDocumentId,
        mimeType: finalMimeType,
      );
    } on StorageAuthRequiredException {
      AppLogger.warning('[StorageService] Upload blocked without authenticated session');
      return const StorageUploadFailure(
        'Your session expired. Please sign in again.',
        StorageFailureReason.authRequired,
      );
    } on SocketException {
      AppLogger.warning('[StorageService] Network error during upload');
      return const StorageUploadFailure(
        'No internet connection. Check your network.',
        StorageFailureReason.network,
      );
    } on TimeoutException {
      AppLogger.warning('[StorageService] Upload timed out');
      return const StorageUploadFailure(
        'Upload timed out. Try again on a better connection.',
        StorageFailureReason.timeout,
      );
    } catch (e) {
      AppLogger.error('[StorageService] Unexpected upload error', error: e);
      return StorageUploadFailure(
        'Unexpected error during upload: ${e.runtimeType}',
        StorageFailureReason.unknown,
      );
    }
  }

  Future<StorageUploadResult> uploadSalesImport({
    required String companyId,
    required String importId,
    required String fileName,
    required Uint8List fileBytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    if (companyId.isEmpty) {
      return const StorageUploadFailure(
        'No active company. Please sign in again.',
        StorageFailureReason.noCompany,
      );
    }

    if (fileBytes.length > _maxFileSizeBytes) {
      return const StorageUploadFailure(
        'File is too large. Maximum size is 10 MB.',
        StorageFailureReason.fileTooLarge,
      );
    }

    if (!_allowedSalesImportMimes.contains(mimeType)) {
      return StorageUploadFailure(
        'File type "$mimeType" not supported. Use JPG, PNG, WebP, PDF, or CSV.',
        StorageFailureReason.invalidFileType,
      );
    }

    try {
      final accessToken = await _resolveAccessToken();
      final sanitizedFileName = _sanitizeFileName(fileName);
      final storagePath = '$companyId/$importId/$sanitizedFileName';
      final storageUrl = '${EnvConfig.supabaseUrl}/storage/v1';
      final uploadUrl = '$storageUrl/object/$_salesImportsBucket/$storagePath';

      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl))
        ..headers['Authorization'] = 'Bearer $accessToken'
        ..headers['apikey'] = EnvConfig.supabaseAnonKey
        ..headers['x-upsert'] = 'true'
        ..fields['cacheControl'] = '3600'
        ..files.add(
          http.MultipartFile.fromBytes(
            '',
            fileBytes,
            filename: sanitizedFileName,
            contentType: MediaType.parse(mimeType),
          ),
        );

      onProgress?.call(0.35);
        final streamedResponse = await request.send().timeout(_storageUploadTimeout);
        final response = await http.Response
          .fromStream(streamedResponse)
          .timeout(_storageReadTimeout);
      onProgress?.call(1);

      if (response.statusCode < 200 || response.statusCode > 299) {
        return StorageUploadFailure(
          'Sales report upload failed (${response.statusCode}). Please try again.',
          response.statusCode == 401 || response.statusCode == 403
              ? StorageFailureReason.permissionDenied
              : StorageFailureReason.unknown,
        );
      }

      return StorageUploadSuccess(
        url: '',
        path: storagePath,
        documentId: importId,
        mimeType: mimeType,
      );
    } on StorageAuthRequiredException {
      return const StorageUploadFailure(
        'Your session expired. Please sign in again.',
        StorageFailureReason.authRequired,
      );
    } on SocketException {
      return const StorageUploadFailure(
        'No internet connection. Check your network.',
        StorageFailureReason.network,
      );
    } on TimeoutException {
      return const StorageUploadFailure(
        'Sales report upload timed out. Try again on a better connection.',
        StorageFailureReason.timeout,
      );
    } catch (e) {
      AppLogger.error('[StorageService] Sales import upload error', error: e);
      return const StorageUploadFailure(
        'Unexpected error during sales report upload.',
        StorageFailureReason.unknown,
      );
    }
  }

  /// Delete a document from Supabase Storage (direct HTTP)
  Future<bool> deleteDocument(String path) async {
    try {
      final accessToken = await _resolveAccessToken();
      final storageUrl = '${EnvConfig.supabaseUrl}/storage/v1';
      final deleteUrl = '$storageUrl/object/$_bucket/$path';

      final response = await http
          .delete(
            Uri.parse(deleteUrl),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'apikey': EnvConfig.supabaseAnonKey,
            },
          )
          .timeout(_storageReadTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        AppLogger.info('[StorageService] Deleted document object');
        return true;
      }
      await _recordAuditEvent(
        companyId: _companyIdFromStoragePath(path),
        action: 'security.storage.delete',
        outcome: response.statusCode == 401 || response.statusCode == 403
            ? 'denied'
            : 'failure',
        metadata: {
          'bucket': _bucket,
          'status_code': response.statusCode,
        },
      );
      AppLogger.warning('[StorageService] Delete failed status=${response.statusCode}');
      return false;
    } on StorageAuthRequiredException {
      AppLogger.warning('[StorageService] Delete blocked without authenticated session');
      return false;
    } catch (e) {
      AppLogger.warning('[StorageService] Delete failed (non-fatal)', error: e);
      return false;
    }
  }

  /// Get a signed URL for temporary access (useful for private buckets)
  Future<String?> getSignedUrl(String path, {int expiresIn = 3600}) async {
    try {
      final accessToken = await _resolveAccessToken();
      final storageUrl = '${EnvConfig.supabaseUrl}/storage/v1';
      final signUrl = '$storageUrl/object/sign/$_bucket/$path';

      final response = await http
          .post(
            Uri.parse(signUrl),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'apikey': EnvConfig.supabaseAnonKey,
              'Content-Type': 'application/json',
            },
            body: json.encode({'expiresIn': expiresIn}),
          )
          .timeout(_storageReadTimeout);

      AppLogger.debug('[StorageService] getSignedUrl response status=${response.statusCode}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // API may return 'signedURL' (v1) or 'signedUrl' (v2) — check both
        final signedUrl = (data['signedURL'] ?? data['signedUrl']) as String?;
        if (signedUrl != null && signedUrl.isNotEmpty) {
          await _recordAuditEvent(
            companyId: _companyIdFromStoragePath(path),
            action: 'security.storage.signed_url',
            outcome: 'success',
            metadata: {
              'bucket': _bucket,
              'expires_in_seconds': expiresIn,
            },
          );
          // Handle both relative (/object/sign/...) and absolute (https://...) URLs
          if (signedUrl.startsWith('http')) return signedUrl;
          return '$storageUrl$signedUrl';
        }
      }
      await _recordAuditEvent(
        companyId: _companyIdFromStoragePath(path),
        action: 'security.storage.signed_url',
        outcome: response.statusCode == 401 || response.statusCode == 403
            ? 'denied'
            : 'failure',
        metadata: {
          'bucket': _bucket,
          'status_code': response.statusCode,
          'expires_in_seconds': expiresIn,
        },
      );
      AppLogger.warning('[StorageService] getSignedUrl failed status=${response.statusCode}');
      return null;
    } on StorageAuthRequiredException {
      AppLogger.warning('[StorageService] getSignedUrl blocked without authenticated session');
      return null;
    } catch (e) {
      AppLogger.warning('[StorageService] getSignedUrl error', error: e);
      return null;
    }
  }

  /// Call in debug mode to verify storage config without affecting startup.
  Future<StorageHealthResult> verifyStorageConfig() async {
    if (!kDebugMode) {
      return const StorageHealthResult(
        status: StorageHealthStatus.skipped,
        message: 'Storage health check is disabled outside debug mode.',
        stage: 'start',
      );
    }

    AppLogger.debug('[StorageVerify] stage=start');

    final session = _supabase.auth.currentSession;
    AppLogger.debug(
      '[StorageService] Auth: ${session != null ? "session exists" : "NO SESSION (pre-login)"}',
    );

    if (session == null) {
      AppLogger.debug('[StorageVerify] stage=complete');
      return const StorageHealthResult(
        status: StorageHealthStatus.unauthenticated,
        message: 'Storage health check skipped without authenticated session.',
        stage: 'complete',
      );
    }

    AppLogger.debug('[StorageVerify] stage=check_policy');
    AppLogger.debug('[StorageVerify] stage=complete');
    AppLogger.debug(
      '[StorageService] Startup bucket listing skipped; uploads validate storage on demand.',
    );

    return const StorageHealthResult(
      status: StorageHealthStatus.skipped,
      message: 'Startup bucket listing skipped; uploads validate storage on demand.',
      stage: 'complete',
    );
  }

  // ── Private helpers ─────────────────────────────────────

  Future<Uint8List?> _compressImage(Uint8List bytes, String mimeType) async {
    try {
      return await compute(_compressImageIsolate, _CompressParams(
        bytes: bytes,
        maxDimension: _maxImageDimension,
        quality: _imageQuality,
      ),);
    } catch (e) {
      AppLogger.warning('Image compression failed', error: e);
      return null;
    }
  }

  bool _isImage(String mimeType) => mimeType.startsWith('image/');

  String _sanitizeFileName(String fileName) {
    final sanitized = fileName
        .replaceAll(RegExp(r'[^\w\s\-\.]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
    return sanitized.substring(0, sanitized.length.clamp(0, 100));
  }

  String? _companyIdFromStoragePath(String path) {
    final parts = path.split('/');
    if (parts.isEmpty || parts.first.trim().isEmpty) return null;
    return parts.first;
  }

  Future<void> _recordAuditEvent({
    required String? companyId,
    required String action,
    required String outcome,
    Map<String, dynamic> metadata = const {},
  }) async {
    if (companyId == null || companyId.isEmpty) return;

    try {
      await SupabaseService.client.rpc(
        'record_security_audit_event',
        params: {
          'p_company_id': companyId,
          'p_action': action,
          'p_entity_type': 'storage_object',
          'p_entity_id': null,
          'p_outcome': outcome,
          'p_correlation_id': null,
          'p_metadata': metadata,
        },
      );
    } catch (error) {
      AppLogger.debug('[StorageService] audit event skipped: ${error.runtimeType}');
    }
  }
}

/// Parameters for image compression isolate
class _CompressParams {
  final Uint8List bytes;
  final int maxDimension;
  final int quality;

  const _CompressParams({
    required this.bytes,
    required this.maxDimension,
    required this.quality,
  });
}

/// Image compression function that runs in isolate
Uint8List? _compressImageIsolate(_CompressParams params) {
  try {
    final image = img.decodeImage(params.bytes);
    if (image == null) return null;

    // Resize if larger than max dimension
    img.Image resized = image;
    if (image.width > params.maxDimension || image.height > params.maxDimension) {
      if (image.width > image.height) {
        resized = img.copyResize(image, width: params.maxDimension);
      } else {
        resized = img.copyResize(image, height: params.maxDimension);
      }
    }

    // Encode as JPEG with specified quality
    return Uint8List.fromList(img.encodeJpg(resized, quality: params.quality));
  } catch (e) {
    return null;
  }
}


