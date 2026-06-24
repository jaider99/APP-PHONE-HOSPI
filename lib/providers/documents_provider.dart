// ARCHITECTURE: Flutter → Edge Function (process-document) → OpenRouter
// OpenRouter API key stays on the server. NEVER call OpenRouter from Flutter.
// Every DB write is scoped by company_id for multi-tenant isolation.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/utils/app_logger.dart';
import 'package:hospi_dash/features/documents/data/models/upload_document_result.dart';
import 'package:hospi_dash/models/document_model.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/services/background_extraction_service.dart';
import 'package:hospi_dash/services/document_image_preprocessor.dart';
import 'package:hospi_dash/services/learning_service.dart';
import 'package:hospi_dash/services/extraction_service.dart';
import 'package:hospi_dash/services/storage_service.dart';
import 'package:hospi_dash/services/step_up_auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

// Legacy alias — all consumers should migrate to companyIdProvider
final venueProvider = companyIdProvider;

// =============================================================================
// FILTER PROVIDER
// =============================================================================

/// Current document filter state
final documentFilterProvider = StateProvider<DocumentFilter>((ref) {
  return DocumentFilter.all;
});

// =============================================================================
// DOCUMENT COUNTS PROVIDER
// =============================================================================

/// Fetches document counts grouped by status
final documentCountsProvider =
    FutureProvider.autoDispose<DocumentCounts>((ref) async {
  final companyId = await ref.watch(companyIdProvider.future);

  if (companyId == null) {
    return const DocumentCounts();
  }

  final supabase = SupabaseService.client;

  try {
    // Fetch all documents and count client-side (Supabase doesn't support GROUP BY easily)
    final response = await supabase
        .from('documents')
        .select('status')
        .eq('company_id', companyId)
        .isFilter('deleted_at', null);

    final statusMap = <String, int>{};
    for (final row in response) {
      final status = row['status'] as String? ?? 'processing';
      statusMap[status] = (statusMap[status] ?? 0) + 1;
    }

    return DocumentCounts.fromStatusMap(statusMap);
  } catch (e) {
    debugPrint('documentCountsProvider error: $e');
    return const DocumentCounts();
  }
});

final documentMergeReviewQueueProvider =
    FutureProvider.autoDispose<List<DocumentModel>>((ref) async {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];

  final response = await SupabaseService.client
      .from('documents')
      .select('''
        *,
        providers(id, name),
        document_items(*)
      ''')
      .eq('company_id', companyId)
      .eq('merge_status', 'review')
      .isFilter('deleted_at', null)
      .order('merge_confidence', ascending: false)
      .order('created_at', ascending: false);

  return (response as List)
      .map((json) => DocumentModel.fromJson(json as Map<String, dynamic>))
      .toList();
});

final documentMergeReviewCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final reviewDocs = await ref.watch(documentMergeReviewQueueProvider.future);
  return reviewDocs.length;
});

// =============================================================================
// UPLOAD PROGRESS PROVIDER
// =============================================================================

/// Upload progress state (0.0 to 1.0, null when not uploading)
final uploadProgressProvider = StateProvider<double?>((ref) => null);

/// Currently processing document IDs (local state)
final processingDocumentsProvider = StateProvider<Set<String>>((ref) => {});

final documentsRealtimeListProvider =
    StreamProvider.autoDispose<List<DocumentModel>>((ref) async* {
  final companyId = await ref.watch(companyIdProvider.future);
  final filter = ref.watch(documentFilterProvider);
  if (companyId == null) {
    yield const [];
    return;
  }

  var stream = SupabaseService.client
      .from('documents')
      .stream(primaryKey: const ['id'])
      .eq('company_id', companyId)
      .order('created_at', ascending: false);

  yield* stream.map(
    (rows) => rows
        .where((row) => row['deleted_at'] == null)
        .where((row) {
          switch (filter) {
            case DocumentFilter.processing:
              return row['status'] == 'processing';
            case DocumentFilter.completed:
              return row['status'] == 'completed';
            case DocumentFilter.invoices:
              return row['document_type'] == 'invoice';
            case DocumentFilter.deliveryNotes:
              return row['document_type'] == 'delivery_note';
            case DocumentFilter.expenseTickets:
              return row['document_type'] == 'expense_ticket';
            case DocumentFilter.flagged:
              return row['status'] == 'flagged';
            case DocumentFilter.all:
              return true;
          }
        })
        .map((row) => DocumentModel.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false),
  );
});

final _documentItemsRealtimeProvider =
    StreamProvider.autoDispose<void>((ref) async* {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return;

  final controller = StreamController<void>();

  final channel = SupabaseService.client
      .channel('document-items-live-$companyId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'document_items',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'company_id',
          value: companyId,
        ),
        callback: (_) {
          if (!controller.isClosed) controller.add(null);
        },
      )
      .subscribe();

  ref.onDispose(() {
    channel.unsubscribe();
    controller.close();
  });

  yield* controller.stream;
});

/// In-memory signed URL cache. Persists for the entire app session so URLs
/// are never re-generated when the same document is opened multiple times.
final _signedUrlCache = <String, String>{};

/// Resolve a storage path into a signed URL using raw HTTP (avoids SDK URL transformation bug).
/// Results are stored in [_signedUrlCache] so repeated opens are instant.
final documentPreviewUrlProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, filePath) async {
  if (_signedUrlCache.containsKey(filePath)) {
    return _signedUrlCache[filePath];
  }
  final storage = ref.read(storageServiceProvider);
  AppLogger.debug('[DocumentPreview] signing document preview URL');
  final url = await storage.getSignedUrl(filePath);
  AppLogger.debug(
      '[DocumentPreview] signed URL ${url == null ? "missing" : "created"}');
  if (url != null) _signedUrlCache[filePath] = url;
  return url;
});

/// Download PDF raw bytes for the fullscreen PDF viewer.
final documentPdfBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, filePath) async {
  try {
    final url = await ref.read(documentPreviewUrlProvider(filePath).future);
    if (url == null || url.isEmpty) return null;
    final response = await http.get(Uri.parse(url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
          '[DocumentPreview] PDF download failed: ${response.statusCode}');
      return null;
    }
    return response.bodyBytes;
  } catch (e) {
    debugPrint('[DocumentPreview] PDF bytes error: $e');
    return null;
  }
});

// =============================================================================
// DOCUMENTS LIST PROVIDER
// =============================================================================

/// Main documents list provider with filtering
final documentsProvider =
    AsyncNotifierProvider.autoDispose<DocumentsNotifier, List<DocumentModel>>(
  () => DocumentsNotifier(),
);

/// Documents notifier handling list state and operations
class DocumentsNotifier extends AutoDisposeAsyncNotifier<List<DocumentModel>> {
  static const int _pageSize = 50;

  @override
  Future<List<DocumentModel>> build() async {
    // Read synchronous state BEFORE the first await (Riverpod 2 rule).
    final realtimeDocuments = ref.watch(documentsRealtimeListProvider);
    final filter = ref.watch(documentFilterProvider);

    return realtimeDocuments.when(
      data: (documents) => documents,
      loading: () => _fallbackBuild(filter),
      error: (_, __) => _fallbackBuild(filter),
    );
  }

  Future<List<DocumentModel>> _fallbackBuild(
    DocumentFilter filter,
  ) async {
    final companyId = await ref.watch(companyIdProvider.future);
    if (companyId == null) {
      return [];
    }
    return _fetchDocuments(companyId: companyId, filter: filter);
  }

  Future<List<DocumentModel>> _fetchDocuments({
    required String companyId,
    required DocumentFilter filter,
    String? cursor,
  }) async {
    final supabase = SupabaseService.client;

    try {
      var query = supabase.from('documents').select('''
            *,
            providers(id, name),
            document_items(*)
          ''').eq('company_id', companyId).isFilter('deleted_at', null);

      // Apply filter
      switch (filter) {
        case DocumentFilter.processing:
          query = query.eq('status', 'processing');
          break;
        case DocumentFilter.completed:
          query = query.eq('status', 'completed');
          break;
        case DocumentFilter.invoices:
          query = query.eq('document_type', 'invoice');
          break;
        case DocumentFilter.deliveryNotes:
          query = query.eq('document_type', 'delivery_note');
          break;
        case DocumentFilter.expenseTickets:
          query = query.eq('document_type', 'expense_ticket');
          break;
        case DocumentFilter.flagged:
          query = query.eq('status', 'flagged');
          break;
        case DocumentFilter.all:
          break;
      }

      // Apply cursor for pagination
      if (cursor != null) {
        query = query.lt('created_at', cursor);
      }

      // Order and limit
      final response =
          await query.order('created_at', ascending: false).limit(_pageSize);

      return (response as List)
          .map((json) => DocumentModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      debugPrint('DocumentsNotifier._fetchDocuments error: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Load more documents (pagination)
  Future<void> loadMore() async {
    final currentState = state.valueOrNull;
    if (currentState == null || currentState.isEmpty) return;

    final companyId = await ref.read(companyIdProvider.future);
    final filter = ref.read(documentFilterProvider);

    if (companyId == null) return;

    final lastDoc = currentState.last;
    final cursor = lastDoc.createdAt.toIso8601String();

    final moreDocuments = await _fetchDocuments(
      companyId: companyId,
      filter: filter,
      cursor: cursor,
    );

    if (moreDocuments.isNotEmpty) {
      state = AsyncData([...currentState, ...moreDocuments]);
    }
  }

  /// Add a document optimistically (before server confirms)
  void addOptimistic(DocumentModel document) {
    final currentState = state.valueOrNull;
    if (currentState != null) {
      state = AsyncData([document, ...currentState]);
    }
  }

  /// Update a document in the list
  void updateDocument(DocumentModel updated) {
    final currentState = state.valueOrNull;
    if (currentState != null) {
      final index = currentState.indexWhere((d) => d.id == updated.id);
      if (index != -1) {
        final newList = [...currentState];
        newList[index] = updated;
        state = AsyncData(newList);
      }
    }
  }

  /// Remove a document from the list
  void removeDocument(String documentId) {
    final currentState = state.valueOrNull;
    if (currentState != null) {
      state = AsyncData(
        currentState.where((d) => d.id != documentId).toList(),
      );
    }
  }

  /// Refresh the list
  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

// =============================================================================
// SINGLE DOCUMENT PROVIDER
// =============================================================================

/// Fetch a single document with full details
final documentDetailProvider =
    FutureProvider.autoDispose.family<DocumentModel?, String>(
  (ref, documentId) async {
    ref.watch(_documentItemsRealtimeProvider);
    final companyId = await ref.watch(companyIdProvider.future);

    if (companyId == null) return null;

    final supabase = SupabaseService.client;

    try {
      final response = await supabase.from('documents').select('''
            *,
            providers(id, name, tax_id, email, phone, address),
            document_items(*)
          ''').eq('id', documentId).eq('company_id', companyId).maybeSingle();

      if (response == null) return null;

      return DocumentModel.fromJson(response);
    } catch (e) {
      debugPrint('documentDetailProvider error: $e');
      return null;
    }
  },
);

// =============================================================================
// DOCUMENT UPLOAD SERVICE PROVIDER
// =============================================================================

/// Provider for document upload operations
final documentUploadServiceProvider = Provider<DocumentUploadService>((ref) {
  return DocumentUploadService(ref);
});

/// Service handling document upload and extraction workflow
class DocumentUploadService {
  final Ref _ref;

  DocumentUploadService(this._ref);

  /// Submit expense flow: upload file, create document, create expense,
  /// link both records, then run extraction asynchronously.
  Future<UploadDocumentResult> submitExpenseFlow({
    required String companyId,
    required String fileName,
    required Uint8List fileBytes,
    required String mimeType,
    required List<Uint8List> pages,
    String? categoryId,
    String? documentType,
    String? paymentMethod,
    String? purchaseOrderId,
    String? incident,
    required bool isPaid,
  }) async {
    final userId = SupabaseService.currentUser?.id;
    final storageService = _ref.read(storageServiceProvider);
    final supabase = SupabaseService.client;

    try {
      debugPrint('[UI] Upload start file=$fileName mime=$mimeType');
      _ref.read(uploadProgressProvider.notifier).state = 0.1;
      final documentId = const Uuid().v4();
      final companyCurrency = await _ref.read(companyCurrencyProvider.future);

      final payload = await _prepareExpenseUploadPayload(
        fileName: fileName,
        fileBytes: fileBytes,
        mimeType: mimeType,
        pages: pages,
      );

      final storageFileName = payload.mimeType == 'application/pdf'
          ? 'original.pdf'
          : payload.fileName;

      final uploadResult = await storageService.uploadDocument(
        companyId: companyId,
        documentId: documentId,
        fileName: storageFileName,
        fileBytes: payload.fileBytes,
        mimeType: payload.mimeType,
        onProgress: (progress) {
          _ref.read(uploadProgressProvider.notifier).state =
              0.1 + progress * 0.45;
        },
      );

      if (uploadResult is StorageUploadFailure) {
        _ref.read(uploadProgressProvider.notifier).state = null;
        return UploadDocumentResult(
            success: false, error: uploadResult.message);
      }

      final success = uploadResult as StorageUploadSuccess;
      final pageUploads = <StorageUploadSuccess>[success];

      for (var index = 1; index < payload.pageBytes.length; index++) {
        final pageUploadResult = await storageService.uploadDocument(
          companyId: companyId,
          documentId: documentId,
          fileName: 'page_${index + 1}.jpg',
          fileBytes: payload.pageBytes[index],
          mimeType: 'image/jpeg',
        );

        if (pageUploadResult is StorageUploadFailure) {
          _ref.read(uploadProgressProvider.notifier).state = null;
          return UploadDocumentResult(
            success: false,
            error: pageUploadResult.message,
          );
        }

        pageUploads.add(pageUploadResult as StorageUploadSuccess);
      }

      final actualMimeType = success.mimeType;
      final normalizedDocType = _normalizeDocumentType(documentType);
      final pageMetadata = pageUploads.length > 1
          ? {
              'source': 'flutter_multi_image_upload',
              'page_count': pageUploads.length,
              'pages': pageUploads.asMap().entries.map((entry) {
                final upload = entry.value;
                return {
                  'page_number': entry.key + 1,
                  'file_path': upload.path,
                  'mime_type': upload.mimeType,
                };
              }).toList(growable: false),
            }
          : null;

      _ref.read(uploadProgressProvider.notifier).state = 0.65;

      debugPrint('[CATEGORY] Upload category_id=$categoryId doc=$documentId');
      await supabase.from('documents').insert({
        'id': documentId,
        'company_id': companyId,
        'uploaded_by': userId,
        'file_path': success.path,
        'file_name': fileName,
        'file_type': actualMimeType,
        'status': 'processing',
        'document_type': normalizedDocType,
        'currency': companyCurrency,
        if (pageMetadata != null) 'ocr_raw_data': pageMetadata,
        if (categoryId != null) 'category_id': categoryId,
      });

      String? expenseId;
      try {
        final expenseInsert = <String, dynamic>{
          'company_id': companyId,
          'document_id': documentId,
          'status': 'processing',
          'currency': companyCurrency,
          'is_paid': isPaid,
          if (categoryId != null) 'category_id': categoryId,
          if (documentType != null) 'document_type': documentType,
          if (paymentMethod != null) 'payment_method': paymentMethod,
          if (purchaseOrderId != null && purchaseOrderId.isNotEmpty)
            'purchase_order_id': purchaseOrderId,
          if (incident != null) 'incident': incident,
        };

        final expenseRow = await supabase
            .from('expenses')
            .insert(expenseInsert)
            .select('id')
            .single();
        expenseId = expenseRow['id'] as String;

        await supabase
            .from('documents')
            .update({'expense_id': expenseId})
            .eq('id', documentId)
            .eq('company_id', companyId);
      } on PostgrestException catch (e) {
        // Backward compatibility for environments where expenses table
        // migration has not been applied yet.
        if (e.code != 'PGRST205') rethrow;
        debugPrint(
          'submitExpenseFlow: expenses table missing, continuing with document-only flow',
        );
      }

      final optimisticDoc = DocumentModel(
        id: documentId,
        companyId: companyId,
        createdAt: DateTime.now(),
        uploadedBy: userId,
        fileUrl: success.url,
        filePath: success.path,
        fileName: fileName,
        fileType: actualMimeType,
        status: DocumentStatus.processing,
        documentType: DocumentTypeExtension.fromString(normalizedDocType),
      );
      _ref.read(documentsProvider.notifier).addOptimistic(optimisticDoc);

      final processingSet = _ref.read(processingDocumentsProvider);
      _ref.read(processingDocumentsProvider.notifier).state = {
        ...processingSet,
        documentId,
      };

      final resolvedExpenseId = expenseId;
      if (resolvedExpenseId != null) {
        debugPrint('[UI] Navigate back doc=$documentId');
        unawaited(_processDocumentBackground(
          documentId: documentId,
          companyId: companyId,
          fileName: fileName,
          fileBytes: fileBytes,
          mimeType: mimeType,
          expenseId: resolvedExpenseId,
          companyCurrency: companyCurrency,
        ));
        _ref.read(uploadProgressProvider.notifier).state = null;
        return UploadDocumentResult(success: true, documentId: documentId);
      } else {
        debugPrint('[UI] Navigate back doc=$documentId');
        unawaited(_processDocumentBackground(
          documentId: documentId,
          companyId: companyId,
          fileName: fileName,
          fileBytes: fileBytes,
          mimeType: mimeType,
          companyCurrency: companyCurrency,
        ));
      }

      _ref.read(uploadProgressProvider.notifier).state = null;
      return UploadDocumentResult(success: true, documentId: documentId);
    } catch (e, stackTrace) {
      debugPrint('DocumentUploadService.submitExpenseFlow error: $e');
      debugPrint('Stack trace: $stackTrace');
      _ref.read(uploadProgressProvider.notifier).state = null;
      return UploadDocumentResult(success: false, error: e.toString());
    }
  }

  Future<_ExpenseUploadPayload> _prepareExpenseUploadPayload({
    required String fileName,
    required Uint8List fileBytes,
    required String mimeType,
    required List<Uint8List> pages,
  }) async {
    if (!mimeType.startsWith('image/')) {
      return _ExpenseUploadPayload(
        fileName: fileName,
        fileBytes: fileBytes,
        mimeType: mimeType,
      );
    }

    const preprocessor = DocumentImagePreprocessor();
    final sourcePages = pages.isNotEmpty ? pages : <Uint8List>[fileBytes];
    final processedPages = await preprocessor.preprocessPages(sourcePages);

    if (processedPages.isEmpty) {
      return _ExpenseUploadPayload(
        fileName: fileName,
        fileBytes: fileBytes,
        mimeType: mimeType,
      );
    }

    if (processedPages.length == 1) {
      return _ExpenseUploadPayload(
        fileName: _replaceFileExtension(fileName, 'jpg'),
        fileBytes: processedPages.first,
        mimeType: 'image/jpeg',
      );
    }

    return _ExpenseUploadPayload(
      fileName: 'page_1.jpg',
      fileBytes: processedPages.first,
      mimeType: 'image/jpeg',
      pageBytes: processedPages,
    );
  }

  String _replaceFileExtension(String fileName, String extension) {
    final normalizedExtension =
        extension.startsWith('.') ? extension.substring(1) : extension;
    if (!fileName.contains('.')) {
      return '$fileName.$normalizedExtension';
    }
    return fileName.replaceAll(RegExp(r'\.[^.]+$'), '.$normalizedExtension');
  }

  String _normalizeDocumentType(String? value) {
    if (value == null || value.isEmpty) return 'unknown';
    return value;
  }

  /// Upload a document and start extraction pipeline
  Future<UploadDocumentResult> uploadDocument({
    required String fileName,
    required Uint8List fileBytes,
    required String mimeType,
  }) async {
    final companyId = await _ref.read(companyIdProvider.future);

    if (companyId == null) {
      debugPrint('uploadDocument: companyId is null, cannot upload');
      // Invalidate and retry once — the provider may have been initialized
      // before auth was fully ready
      _ref.invalidate(companyIdProvider);
      final retryId = await _ref.read(companyIdProvider.future);
      if (retryId == null) {
        return const UploadDocumentResult(
          success: false,
          error:
              'No company linked to your account. Please complete company setup in Settings.',
        );
      }
      return _doUpload(
        companyId: retryId,
        fileName: fileName,
        fileBytes: fileBytes,
        mimeType: mimeType,
      );
    }

    return _doUpload(
      companyId: companyId,
      fileName: fileName,
      fileBytes: fileBytes,
      mimeType: mimeType,
    );
  }

  Future<UploadDocumentResult> _doUpload({
    required String companyId,
    required String fileName,
    required Uint8List fileBytes,
    required String mimeType,
  }) async {
    final userId = SupabaseService.currentUser?.id;
    final storageService = _ref.read(storageServiceProvider);
    final supabase = SupabaseService.client;

    debugPrint('[UI] Upload start file=$fileName mime=$mimeType');
    final documentId = const Uuid().v4();
    final companyCurrency = await _ref.read(companyCurrencyProvider.future);

    Uint8List uploadBytes = fileBytes;
    String uploadMime = mimeType;
    String uploadFileName = fileName;

    if (uploadMime.startsWith('image/')) {
      final preprocessed = await const DocumentImagePreprocessor()
          .preprocessSinglePage(uploadBytes);
      if (preprocessed != null) {
        uploadBytes = preprocessed;
        uploadMime = 'image/jpeg';
        uploadFileName = _replaceFileExtension(uploadFileName, 'jpg');
        debugPrint(
            '[Upload] Image preprocessed for OCR (${uploadBytes.length} bytes)');
      }
    }

    try {
      _ref.read(uploadProgressProvider.notifier).state = 0.1;

      final storageFileName =
          uploadMime == 'application/pdf' ? 'original.pdf' : uploadFileName;

      // Step 1: Upload to storage
      final uploadResult = await storageService.uploadDocument(
        companyId: companyId,
        documentId: documentId,
        fileName: storageFileName,
        fileBytes: uploadBytes,
        mimeType: uploadMime,
        onProgress: (progress) {
          _ref.read(uploadProgressProvider.notifier).state =
              0.1 + progress * 0.3;
        },
      );

      if (uploadResult is StorageUploadFailure) {
        _ref.read(uploadProgressProvider.notifier).state = null;
        return UploadDocumentResult(
          success: false,
          error: uploadResult.message,
        );
      }

      final success = uploadResult as StorageUploadSuccess;
      _ref.read(uploadProgressProvider.notifier).state = 0.4;

      // Step 2: Insert document record — status = 'processing'
      final actualMime = success.mimeType;

      await supabase.from('documents').insert({
        'id': documentId,
        'company_id': companyId,
        'uploaded_by': userId,
        'file_path': success.path,
        'file_name': fileName,
        'file_type': actualMime,
        'status': 'processing',
        'document_type': 'unknown',
        'currency': companyCurrency,
      });

      // Step 3: Optimistic UI
      final optimisticDoc = DocumentModel(
        id: documentId,
        companyId: companyId,
        createdAt: DateTime.now(),
        uploadedBy: userId,
        fileUrl: success.url,
        filePath: success.path,
        fileName: fileName,
        fileType: actualMime,
        status: DocumentStatus.processing,
        documentType: DocumentType.unknown,
      );

      _ref.read(documentsProvider.notifier).addOptimistic(optimisticDoc);

      final processingSet = _ref.read(processingDocumentsProvider);
      _ref.read(processingDocumentsProvider.notifier).state = {
        ...processingSet,
        documentId,
      };

      _ref.read(uploadProgressProvider.notifier).state = 0.5;

      // Step 4: Call Edge Function (server-side OpenRouter)
      debugPrint('[UI] Navigate back doc=$documentId');
      unawaited(_processDocumentBackground(
        documentId: documentId,
        companyId: companyId,
        fileName: fileName,
        fileBytes: fileBytes,
        mimeType: mimeType,
        companyCurrency: companyCurrency,
      ));

      _ref.read(uploadProgressProvider.notifier).state = null;

      return UploadDocumentResult(
        success: true,
        documentId: documentId,
      );
    } catch (e, stackTrace) {
      debugPrint('DocumentUploadService.uploadDocument error: $e');
      debugPrint('Stack trace: $stackTrace');
      _ref.read(uploadProgressProvider.notifier).state = null;
      return UploadDocumentResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<void> _processDocumentBackground({
    required String documentId,
    required String companyId,
    required String fileName,
    required Uint8List fileBytes,
    required String mimeType,
    required String companyCurrency,
    String? expenseId,
  }) async {
    try {
      final extractionResult = await BackgroundExtractionService(
        SupabaseService.client,
        _ref.read(storageServiceProvider),
      )
          .processDocument(
            docId: documentId,
            companyId: companyId,
            fileBytes: fileBytes,
            mimeType: mimeType,
            fileName: fileName,
            companyCurrency: companyCurrency,
          )
          .timeout(const Duration(seconds: 120));

      if (expenseId != null &&
          extractionResult == ExtractionInvocationResult.completed) {
        await _syncExpenseAfterExtraction(
          documentId: documentId,
          expenseId: expenseId,
          companyId: companyId,
        );
      }
    } on TimeoutException {
      await _markDocumentFailed(
        documentId: documentId,
        companyId: companyId,
        message: 'Extraction timed out. Please retry or review manually.',
      );
      if (expenseId != null) {
        await SupabaseService.client
            .from('expenses')
            .update({'status': 'flagged'})
            .eq('id', expenseId)
            .eq('company_id', companyId);
      }
    } catch (e, stackTrace) {
      debugPrint('[BG] processing error doc=$documentId error=$e');
      debugPrint('$stackTrace');
      await _markDocumentFailed(
        documentId: documentId,
        companyId: companyId,
        message: 'Background processing failed unexpectedly. Please retry.',
      );
      if (expenseId != null) {
        await SupabaseService.client
            .from('expenses')
            .update({'status': 'flagged'})
            .eq('id', expenseId)
            .eq('company_id', companyId);
      }
    } finally {
      _clearProcessingState(documentId);
    }
  }

  Future<void> _syncExpenseAfterExtraction({
    required String documentId,
    required String expenseId,
    required String companyId,
  }) async {
    final supabase = SupabaseService.client;

    try {
      final doc = await supabase.from('documents').select('''
            status,
            extraction_clean,
            document_date,
            total_amount,
            currency,
            document_type,
            category_id
          ''').eq('id', documentId).eq('company_id', companyId).maybeSingle();

      if (doc == null) return;

      // Read the expense's existing category_id so we never overwrite a
      // user-selected category with an AI-detected one.
      final existingExpense = await supabase
          .from('expenses')
          .select('category_id')
          .eq('id', expenseId)
          .eq('company_id', companyId)
          .maybeSingle();
      final existingExpenseCategoryId =
          existingExpense?['category_id'] as String?;

      final status = doc['status'] as String?;
      final extraction =
          (doc['extraction_clean'] as Map<String, dynamic>?) ?? doc;

      if (status == 'completed' || status == 'linked') {
        final updateData = <String, dynamic>{
          'status': 'completed',
          if (extraction['supplier_name'] != null)
            'supplier_name': extraction['supplier_name'],
          if (extraction['document_date'] != null)
            'document_date': extraction['document_date'],
          if (extraction['total_amount'] != null)
            'total_amount': extraction['total_amount'],
          if (extraction['currency'] != null)
            'currency': extraction['currency'],
          if (doc['document_type'] != null)
            'document_type': doc['document_type'],
          // User-selected category always wins over AI-derived category.
          if (doc['category_id'] != null && existingExpenseCategoryId == null)
            'category_id': doc['category_id'],
        };

        debugPrint(
          '[CATEGORY] sync doc=${doc['category_id']} '
          'existing=$existingExpenseCategoryId → '
          'final=${updateData['category_id'] ?? existingExpenseCategoryId}',
        );

        await supabase
            .from('expenses')
            .update(updateData)
            .eq('id', expenseId)
            .eq('company_id', companyId);
      } else if (status == 'flagged' || status == 'failed') {
        await supabase
            .from('expenses')
            .update({'status': 'flagged'})
            .eq('id', expenseId)
            .eq('company_id', companyId);
      }
    } catch (e) {
      debugPrint('[ExpenseExtraction] sync failed: $e');
    }
  }

  void _clearProcessingState(String documentId) {
    try {
      _ref.invalidate(documentsProvider);
      _ref.invalidate(documentCountsProvider);
      final processingSet = _ref.read(processingDocumentsProvider);
      _ref.read(processingDocumentsProvider.notifier).state =
          processingSet.where((id) => id != documentId).toSet();
    } catch (_) {
      // Provider may have been disposed if user navigated away.
    }
  }

  /// Invoke the process-document Edge Function (server-side OpenRouter).
  /// Fire-and-forget — the Edge Function updates the DB row when done.
  Future<void> _invokeExtraction({
    required String documentId,
    required String companyId,
  }) async {
    final supabase = SupabaseService.client;

    try {
      await const ExtractionService()
          .invokeProcessDocument(
            supabase: supabase,
            documentId: documentId,
            companyId: companyId,
          )
          .timeout(const Duration(seconds: 60));

      debugPrint('[Extraction] Edge Function completed ✓');
    } catch (e) {
      debugPrint('[Extraction] Edge Function call failed: $e');
      await _markDocumentFailed(
        documentId: documentId,
        companyId: companyId,
        message: 'Extraction failed unexpectedly. Tap Re-extract to retry.',
      );
    }

    // Refresh UI regardless of outcome
    _clearProcessingState(documentId);
  }

  /// Mark a document as flagged with an error message.
  Future<void> _markDocumentFailed({
    required String documentId,
    required String companyId,
    required String message,
  }) async {
    try {
      await SupabaseService.client
          .from('documents')
          .update({
            'status': 'flagged',
            'notes': message,
          })
          .eq('id', documentId)
          .eq('company_id', companyId);
    } catch (_) {}
  }

  /// Re-extract a document via the Edge Function.
  /// The Edge Function downloads the file from storage and reprocesses it.
  Future<bool> reExtractDocument(String documentId) async {
    final companyId = await _ref.read(companyIdProvider.future);
    if (companyId == null) return false;

    final supabase = SupabaseService.client;

    try {
      // Mark as processing
      await supabase
          .from('documents')
          .update({
            'status': 'processing',
            'notes': null,
          })
          .eq('id', documentId)
          .eq('company_id', companyId);

      _ref.invalidate(documentsProvider);

      // Call Edge Function — it downloads the file from storage itself
      await _invokeExtraction(
        documentId: documentId,
        companyId: companyId,
      );

      return true;
    } catch (e) {
      debugPrint('Re-extraction failed: $e');
      return false;
    }
  }

  /// Soft delete a document
  Future<bool> deleteDocument(String documentId) async {
    try {
      await _ref
          .read(stepUpAuthServiceProvider)
          .requireStepUp(action: StepUpAction.deleteDocument);
    } on StepUpAuthException {
      return false;
    }

    final companyId = await _ref.read(companyIdProvider.future);
    if (companyId == null) return false;

    final supabase = SupabaseService.client;

    try {
      await supabase
          .from('documents')
          .update({
            'deleted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', documentId)
          .eq('company_id', companyId);

      _ref.read(documentsProvider.notifier).removeDocument(documentId);
      _ref.invalidate(documentCountsProvider);

      return true;
    } catch (e) {
      debugPrint('Delete document failed: $e');
      return false;
    }
  }

  /// Update document manually
  Future<bool> updateDocument({
    required String documentId,
    String? supplierName,
    String? documentNumber,
    DateTime? documentDate,
    String? categoryId,
    double? totalAmount,
    double? taxAmount,
    String? notes,
  }) async {
    final companyId = await _ref.read(companyIdProvider.future);
    if (companyId == null) return false;

    final supabase = SupabaseService.client;

    try {
      Map<String, dynamic>? existingRow;
      if (categoryId != null) {
        existingRow = await supabase
            .from('documents')
            .select(
              'category_id, ai_category_id, category_confidence, expense_id, supplier_name, extraction_clean',
            )
            .eq('id', documentId)
            .eq('company_id', companyId)
            .maybeSingle();
      }

      final updateData = <String, dynamic>{};
      if (documentNumber != null)
        updateData['document_number'] = documentNumber;
      if (documentDate != null) {
        updateData['document_date'] =
            documentDate.toIso8601String().split('T').first;
      }
      if (categoryId != null) updateData['category_id'] = categoryId;
      if (totalAmount != null) updateData['total_amount'] = totalAmount;
      if (taxAmount != null) updateData['tax_amount'] = taxAmount;
      if (notes != null) updateData['notes'] = notes;

      if (updateData.isEmpty) return true;

      await supabase
          .from('documents')
          .update(updateData)
          .eq('id', documentId)
          .eq('company_id', companyId);

      if (categoryId != null) {
        final expenseId = existingRow?['expense_id'] as String?;
        if (expenseId != null) {
          await supabase
              .from('expenses')
              .update({'category_id': categoryId})
              .eq('id', expenseId)
              .eq('company_id', companyId);
        }

        final previousCategoryId = existingRow?['category_id'] as String?;
        if (previousCategoryId != categoryId) {
          final extraction =
              existingRow?['extraction_clean'] as Map<String, dynamic>?;
          final supplier = existingRow?['supplier_name'] as String? ??
              extraction?['supplier_name'] as String?;
          final lineItems =
              (extraction?['line_items'] as List<dynamic>? ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .map((item) => item['description'] as String?)
                  .whereType<String>();
          final keywords = _ref.read(learningServiceProvider).extractKeywords(
                supplierName: supplier,
                description: notes,
                lineItems: lineItems,
              );
          final predictedCategoryId = existingRow?['ai_category_id'] as String?;
          final predictionConfidence =
              (existingRow?['category_confidence'] as num?)?.toDouble() ?? 0.2;

          await _ref.read(learningServiceProvider).recordCorrection(
                documentId: documentId,
                supplierName: supplier,
                predictedCategoryId: predictedCategoryId,
                confirmedCategoryId: categoryId,
                keywords: keywords,
                confidence: predictedCategoryId == categoryId
                    ? predictionConfidence
                    : 0.2,
              );
        }
      }

      _ref.invalidate(documentsProvider);
      _ref.invalidate(documentDetailProvider(documentId));

      return true;
    } catch (e) {
      debugPrint('Update document failed: $e');
      return false;
    }
  }
}

class _ExpenseUploadPayload {
  final String fileName;
  final Uint8List fileBytes;
  final String mimeType;
  final List<Uint8List> pageBytes;

  const _ExpenseUploadPayload({
    required this.fileName,
    required this.fileBytes,
    required this.mimeType,
    this.pageBytes = const [],
  });
}
