import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hospi_dash/services/extraction_service.dart';
import 'package:hospi_dash/services/storage_service.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Maximum number of PDF pages we render and forward to OpenRouter per
/// document. Must stay <= MAX_IMAGES_PER_REQUEST on the Edge Function.
const int kMaxPdfPagesToExtract = 3;

class BackgroundExtractionService {
  final SupabaseClient _supabase;
  final StorageService _storage;

  BackgroundExtractionService(this._supabase, this._storage);

  Future<ExtractionInvocationResult> processDocument({
    required String docId,
    required String companyId,
    required Uint8List fileBytes,
    required String mimeType,
    required String fileName,
    required String companyCurrency,
  }) async {
    debugPrint('[BG] START doc=$docId mime=$mimeType');

    try {
      String imageFileName = fileName;
      var hasExtractionSource = false;

      if (mimeType == 'application/pdf') {
        final renderedPages = await _renderPdfPages(
          pdfBytes: fileBytes,
          docId: docId,
          maxPages: kMaxPdfPagesToExtract,
        );

        if (renderedPages.pages.isEmpty) {
          await _markFlagged(
            docId,
            companyId,
            'PDF rendering failed. Could not convert any page to an image.',
          );
          return ExtractionInvocationResult.completed;
        }

        final pageUploads = <StorageUploadSuccess>[];
        for (var i = 0; i < renderedPages.pages.length; i++) {
          final pageNumber = i + 1;
          final pageFileName = 'page_$pageNumber.jpg';
          debugPrint(
            '[BG] Uploading rendered PDF page $pageNumber/${renderedPages.pages.length} doc=$docId',
          );
          final uploadResult = await _storage.uploadDocument(
            companyId: companyId,
            documentId: docId,
            fileName: pageFileName,
            fileBytes: renderedPages.pages[i],
            mimeType: 'image/jpeg',
          );

          if (uploadResult is StorageUploadFailure) {
            await _markFlagged(
              docId,
              companyId,
              'Rendered image upload failed for page $pageNumber: ${uploadResult.message}',
            );
            return ExtractionInvocationResult.completed;
          }

          pageUploads.add(uploadResult as StorageUploadSuccess);
        }

        imageFileName = 'page_1.jpg';
        hasExtractionSource = pageUploads.isNotEmpty;

        // Merge multi-page metadata into ocr_raw_data so the process-document
        // Edge Function discovers every rendered page through the same path
        // it already uses for multi-image uploads.
        final pagesPayload = pageUploads
            .asMap()
            .entries
            .map((entry) => {
                  'page_number': entry.key + 1,
                  'file_path': entry.value.path,
                  'mime_type': entry.value.mimeType,
                })
            .toList(growable: false);

        final ocrPayload = <String, dynamic>{
          'source': 'flutter_pdf_render',
          'page_count': pageUploads.length,
          'pages': pagesPayload,
          if (renderedPages.totalPages > pageUploads.length) ...{
            'pdf_truncated': true,
            'pdf_total_pages': renderedPages.totalPages,
          },
        };

        try {
          await _supabase
              .from('documents')
              .update({'ocr_raw_data': ocrPayload})
              .eq('id', docId)
              .eq('company_id', companyId);
        } catch (e) {
          debugPrint('[BG] Failed to persist PDF page metadata doc=$docId: $e');
        }
      } else {
        final document = await _supabase
            .from('documents')
            .select('file_path, file_url')
            .eq('id', docId)
            .eq('company_id', companyId)
            .maybeSingle();

        final filePath = document?['file_path'] as String?;
        final legacyUrl = document?['file_url'] as String?;

        hasExtractionSource = (filePath != null && filePath.isNotEmpty) ||
            (legacyUrl != null && legacyUrl.isNotEmpty);

        if (!hasExtractionSource) {
          final uploadResult = await _storage.uploadDocument(
            companyId: companyId,
            documentId: docId,
            fileName: fileName,
            fileBytes: fileBytes,
            mimeType: mimeType,
          );

          if (uploadResult is StorageUploadFailure) {
            await _markFlagged(
              docId,
              companyId,
              'Image upload failed: ${uploadResult.message}',
            );
            return ExtractionInvocationResult.completed;
          }

          final success = uploadResult as StorageUploadSuccess;
          hasExtractionSource = true;

          try {
            await _supabase
                .from('documents')
                .update({'file_path': success.path})
                .eq('id', docId)
                .eq('company_id', companyId);
          } catch (e) {
            debugPrint(
                '[BG] Failed to persist fallback file path doc=$docId: $e');
          }
        }
      }

      if (!hasExtractionSource) {
        await _markFlagged(
          docId,
          companyId,
          'Document source is missing after background preparation.',
        );
        return ExtractionInvocationResult.completed;
      }

      debugPrint('[BG] Invoking process-document doc=$docId');
      final result = await const ExtractionService().invokeProcessDocument(
        supabase: _supabase,
        documentId: docId,
        companyId: companyId,
        currency: companyCurrency,
        fileName: imageFileName,
      );

      debugPrint('[BG] Extraction ${result.name} doc=$docId');
      return result;
    } on ExtractionInvocationException catch (e, stackTrace) {
      debugPrint('[BG] Extraction function error doc=$docId: $e');
      debugPrint('[BG] Stack: $stackTrace');
      if (!e.remoteFlagged) {
        await _markFlagged(docId, companyId, e.message);
      }
      return ExtractionInvocationResult.completed;
    } on TimeoutException {
      await _markFlagged(
        docId,
        companyId,
        'Extraction timed out. Tap Re-extract to retry.',
      );
      return ExtractionInvocationResult.completed;
    } catch (e, stackTrace) {
      debugPrint('[BG] Unexpected error doc=$docId: $e');
      debugPrint('[BG] Stack: $stackTrace');
      await _markFlagged(
        docId,
        companyId,
        'Unexpected extraction error: $e',
      );
      return ExtractionInvocationResult.completed;
    }
  }

  Future<_RenderedPdf> _renderPdfPages({
    required Uint8List pdfBytes,
    required String docId,
    required int maxPages,
  }) async {
    File? tempFile;
    PdfDocument? document;
    final rendered = <Uint8List>[];
    var totalPages = 0;

    try {
      debugPrint('[BG] PDF render start doc=$docId');

      final tempDirectory = await getTemporaryDirectory();
      final filePath = '${tempDirectory.path}/render_$docId.pdf';
      tempFile = File(filePath);
      await tempFile.writeAsBytes(pdfBytes);

      document = await PdfDocument.openFile(filePath);
      totalPages = document.pagesCount;
      debugPrint('[BG] PDF pages=$totalPages doc=$docId');

      final pagesToRender = totalPages < maxPages ? totalPages : maxPages;

      for (var i = 1; i <= pagesToRender; i++) {
        final page = await document.getPage(i);
        try {
          final pageImage = await page.render(
            width: page.width * 2.5,
            height: page.height * 2.5,
            backgroundColor: '#ffffff',
            quality: 88,
          );

          if (pageImage == null || pageImage.bytes.isEmpty) {
            debugPrint('[BG] PDF render returned null page=$i doc=$docId');
            continue;
          }

          var bytes = pageImage.bytes;
          if (bytes.length > 1500000) {
            bytes = await compute(_compressJpeg, _CompressArgs(bytes, 1600));
          }

          debugPrint(
            '[BG] PDF render page=$i bytes=${bytes.length} doc=$docId',
          );
          rendered.add(bytes);
        } finally {
          await page.close();
        }
      }
    } catch (e) {
      debugPrint('[BG] PDF render error: $e doc=$docId');
    } finally {
      if (document != null) {
        await document.close();
      }
      if (tempFile != null) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }

    return _RenderedPdf(pages: rendered, totalPages: totalPages);
  }

  Future<void> _markFlagged(
    String docId,
    String companyId,
    String reason,
  ) async {
    debugPrint('[BG] Marking flagged doc=$docId: $reason');
    try {
      await _supabase
          .from('documents')
          .update({'status': 'flagged', 'notes': reason})
          .eq('id', docId)
          .eq('company_id', companyId);
    } catch (e) {
      debugPrint('[BG] Failed to mark flagged: $e');
    }
  }
}

Uint8List _compressJpeg(_CompressArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) return args.bytes;

  final resized = decoded.width >= decoded.height
      ? img.copyResize(decoded, width: args.maxDim)
      : img.copyResize(decoded, height: args.maxDim);

  return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
}

class _CompressArgs {
  final Uint8List bytes;
  final int maxDim;

  const _CompressArgs(this.bytes, this.maxDim);
}

class _RenderedPdf {
  final List<Uint8List> pages;
  final int totalPages;

  const _RenderedPdf({required this.pages, required this.totalPages});
}
