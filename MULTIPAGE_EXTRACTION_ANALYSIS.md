# MULTIPAGE_EXTRACTION_ANALYSIS

## 1. Executive Summary

Multi-image extraction (multiple photos of one invoice) and multi-page PDF extraction are **not symmetric** today. The multi-image path is fully wired end to end. The PDF path is silently single-page: only page 1 is rasterized, so a 5-page PDF reaches the model as a single image.

The minimum safe fix is to make the PDF path produce the same artifact the multi-image path already produces — `page_N.jpg` files in storage plus an `ocr_raw_data.pages[]` array on the document row. The Edge Function's existing multi-image discovery path then handles the rest with no server changes.

## 2. Current Pipeline Map

### Flow A — Single image (WORKS)

```
Image → DocumentUploadService.submitExpenseFlow
  → storage: {company_id}/{doc_id}/{file_name}
  → documents row (file_url, file_path, status='processing')
  → BackgroundExtractionService.processDocument (uses documents.file_url as-is)
  → ExtractionService.invokeProcessDocument({documentId})
  → process-document Edge Function
      → resolveDocumentImageSources → 1 signed URL
      → 1 image_url block to OpenRouter
  → parse JSON → update documents → completed
```

### Flow B — Multiple photos of one document (WORKS at infra level)

```
N images → ExpenseFormState.pages (List<Uint8List>)
  → DocumentImagePreprocessor.preprocessPages
  → DocumentUploadService.submitExpenseFlow
      → page 1 → storage: {company_id}/{doc_id}/original.jpg
      → page 2..N → storage: {company_id}/{doc_id}/page_2.jpg, page_3.jpg
      → documents row with ocr_raw_data = {
          source: 'flutter_multi_image_upload',
          page_count: N,
          pages: [{ page_number, file_url, file_path, mime_type }, ...]
        }
  → BackgroundExtractionService.processDocument (image branch, single resolved URL)
  → ExtractionService.invokeProcessDocument({documentId})
  → process-document Edge Function
      → resolveDocumentImageSources reads ocr_raw_data.pages[]
      → up to MAX_IMAGES_PER_REQUEST (3) signed URLs
      → N image_url blocks + 1 text block to OpenRouter
      → prompt already says: "Treat all provided images/pages as ONE document"
  → parse JSON → update documents → completed
```

The previous failure on multi-image (`json_parse_failed`) is the **same root cause** as the single-image truncation already addressed in [AI_EXTRACTION_FAILURE_ANALYSIS.md](AI_EXTRACTION_FAILURE_ANALYSIS.md): more pages = more line items = response hits `max_tokens`. With `max_tokens=6000`, slimmer `raw_text`, and the 90 s timeout already deployed in `process-document` v34, multi-image should now go through cleanly. No further change is required on the multi-image path itself.

### Flow C — PDF (BROKEN: single page only)

```
PDF → DocumentUploadService.submitExpenseFlow
  → storage: {company_id}/{doc_id}/original.pdf
  → documents row (file_type='application/pdf', NO ocr_raw_data.pages)
  → BackgroundExtractionService.processDocument (PDF branch)
      → _renderPdfToImage()
        → opens PdfDocument
        → ❌ getPage(1) ONLY  (lib/services/background_extraction_service.dart:167)
        → renders page 1 to JPEG
      → uploads ONE image as {file_basename}_rendered.jpg
      → documents.rendered_image_url = page 1 URL
      → ❌ ocr_raw_data.pages NOT populated for PDFs
  → process-document Edge Function
      → resolveDocumentImageSources finds NO pages array
      → falls back to rendered_image_url (page 1 only)
      → 1 image_url block to OpenRouter
  → model sees only page 1
```

Result: A 3-page PDF invoice loses pages 2 and 3 entirely. Headers may render fine, line items and totals from later pages are missing. Depending on what page 1 contains, the model may also produce a structurally odd response that trips the parser, surfacing as `json_parse_failed`.

## 3. Failure Points

| Symptom | Where | Cause |
|---|---|---|
| PDF extraction missing later pages | `lib/services/background_extraction_service.dart` `_renderPdfToImage` | Loop is hardcoded to `getPage(1)` |
| `ocr_raw_data.pages` not populated for PDFs | same file, PDF branch in `processDocument` | Branch never builds page metadata |
| Edge Function falls back to single-image path for PDFs | `supabase/functions/process-document/index.ts` `resolveDocumentImageSources` | Correct behavior given current input — not a bug, downstream of the Flutter gap |
| Multi-image `json_parse_failed` | model truncation, not infra | Already addressed by `max_tokens=6000` + slimmer prompt in v34 |

## 4. Evidence

- `lib/services/background_extraction_service.dart:167` calls `document.getPage(1)` exactly once and returns immediately. `document.pagesCount` is logged but never iterated.
- `lib/providers/documents_provider.dart` lines 492–512 build `pageMetadata` only when `pageUploads.length > 1`, which never happens on the PDF code path because the PDF branch uploads exactly one rendered image.
- `supabase/functions/process-document/index.ts` `resolveDocumentImageSources` already supports `ocr_raw_data.pages[]` and signs each page's storage path. No server change is needed once the Flutter side populates the array.
- Edge Function caps requests at `MAX_IMAGES_PER_REQUEST = 3`. PDF rendering must respect the same cap.

## 5. Recommended Fix (minimum, surgical)

Touch one Flutter file: `lib/services/background_extraction_service.dart`.

1. In the PDF branch of `processDocument`:
   - Render up to `kMaxPdfPagesToExtract = 3` pages (matching the server cap).
   - Compress each page (existing `_compressJpeg` isolate) to keep payload small.
   - Upload each page as `page_1.jpg`, `page_2.jpg`, `page_3.jpg` under `{company_id}/{doc_id}/`.
   - Set `documents.rendered_image_url` to the page 1 URL (preserves preview behaviour).
   - Merge into `documents.ocr_raw_data` a `{ source: 'flutter_pdf_render', page_count, pages: [...] }` payload that mirrors the multi-image payload exactly.
2. Single-page PDFs continue to work because the same code path produces a one-element `pages` array, which `resolveDocumentImageSources` accepts.
3. Continue to invoke `ExtractionService.invokeProcessDocument({documentId})` once. No new endpoint, no new contract.

Do not change:

- `process-document` Edge Function (already supports the multi-page contract).
- `ExtractionService` API.
- Documents table schema (uses existing `ocr_raw_data` JSONB).
- Auth, RLS, storage paths, dashboard, FAB, products page, suppliers page.
- Single-image and multi-image flows.

If a PDF has more than `kMaxPdfPagesToExtract` pages, render only the first 3 and write `pdf_truncated: true, pdf_total_pages: N` into `ocr_raw_data` so we can later surface a "partial extraction" UI without changing the schema.

## 6. Out of Scope

- Adding a `document_pages` table — current `ocr_raw_data.pages[]` is sufficient and already used.
- Increasing `MAX_IMAGES_PER_REQUEST` beyond 3 — the model's input token budget plus the already-tight output budget make >3 pages risky. Revisit only if logs show OpenRouter consistently completing 3-image extractions with `finish_reason=stop` and headroom.
- Server-side PDF rendering — pdfx in Flutter is already proven on device.
- Continuation prompts / JSON repair — only justified after the truncation fix and the page wiring are both validated in production.

## 7. Validation Matrix

After the fix:

1. Single image invoice → still `completed`, `finish_reason=stop`.
2. 2 photos of one invoice → 1 document, 2 storage pages, `ocr_raw_data.pages.length === 2`, model receives both, `completed`.
3. 3-page PDF → `_renderPdfToImage` no longer used; new pipeline uploads 3 page images, model receives all 3, `completed`.
4. Single-page PDF → 1 page rendered, `pages.length === 1`, `completed`.
5. 10-page PDF → first 3 rendered, `pdf_truncated=true` and `pdf_total_pages=10` in `ocr_raw_data`, document still completes on the first 3 pages.
6. Failing render → `_markFlagged('PDF rendering failed...')` as today.

## 8. Rollback Plan

Revert `lib/services/background_extraction_service.dart` to the previous commit. No DB rollback. No Edge Function rollback. PDFs will return to single-page extraction behaviour.
