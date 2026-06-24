# Multi-Picture Extraction Pipeline Analysis

Date: 2026-06-06

## 1. Current Upload Architecture

HospiDash currently uses a Flutter-first upload orchestration with server-side AI extraction:

1. `CameraUploadService` captures or selects an image/PDF and opens the expense form.
2. `ExpenseFormNotifier` holds form metadata and an in-memory `pages` list for image uploads.
3. `DocumentUploadService.submitExpenseFlow()` preprocesses image pages, uploads files to Supabase Storage, creates one `documents` row, optionally creates one `expenses` row, then starts `_processDocumentBackground()` with `unawaited()`.
4. `BackgroundExtractionService.processDocument()` prepares PDF pages when needed, confirms an extraction source exists, then calls `ExtractionService.invokeProcessDocument()`.
5. `ExtractionService` invokes the Supabase Edge Function `process-document` with only `{ "documentId": documentId }`.
6. `process-document` authenticates the caller, reads the document through the user/RLS client, derives `company_id`, signs/downloads images server-side, builds an OpenRouter VLM request, saves extraction results, and returns only after all of that work is complete.
7. After a successful synchronous response, Flutter currently runs document-type finalization and fires `recognize-products` as a second Edge Function call.

The UI returns to Documents quickly because Flutter uses `unawaited()` for `_processDocumentBackground()`, but the background isolate/task still holds one mobile HTTP request open until `process-document` finishes.

## 2. Current Single-Image Path

Single-image capture/gallery flow:

1. `CameraUploadService.handleCameraCapture()` or `handleGalleryPick()` reads one image into memory and passes `initialPages: [bytes]` into `ExpenseFormArgs`.
2. `ExpenseFormNotifier` seeds `state.pages` with that image.
3. `DocumentUploadService._prepareExpenseUploadPayload()` runs `DocumentImagePreprocessor.preprocessPages()`.
4. If there is one page, it uploads one JPEG as `company_id/document_id/<filename>.jpg`.
5. The `documents` insert stores `file_path` and no multi-page `ocr_raw_data.pages` payload.
6. `process-document` resolves the direct `documents.file_path`, signs it with the service client, downloads it, converts it to a base64 data URL, sends one image content block to OpenRouter, persists results, and returns.

This path has worked because one image generally finishes before the mobile function HTTP connection closes.

## 3. Current Multi-Picture Path

Multi-picture upload is real, but it is not backed by a `document_pages` table:

1. Additional pages are added in the expense form with `ExpenseFormNotifier.addPage(Uint8List bytes)`.
2. `DocumentUploadService.submitExpenseFlow()` preprocesses all pages via `DocumentImagePreprocessor.preprocessPages()`.
3. It creates one `documentId` before upload.
4. It uploads page 1 as `page_1.jpg` and every additional page as `page_2.jpg`, `page_3.jpg`, etc., all under the same `company_id/document_id/` folder.
5. It inserts one `documents` row.
6. For 2+ pages, it writes `documents.ocr_raw_data` as:

```json
{
  "source": "flutter_multi_image_upload",
  "page_count": 2,
  "pages": [
    { "page_number": 1, "file_path": "company_id/document_id/page_1.jpg", "mime_type": "image/jpeg" },
    { "page_number": 2, "file_path": "company_id/document_id/page_2.jpg", "mime_type": "image/jpeg" }
  ]
}
```

7. `process-document` reads `ocr_raw_data.pages`, signs every page path, downloads every page, embeds every image as a base64 data URL, and sends them in one OpenRouter request.

Evidence: there are no migrations creating `document_pages` or `extraction_jobs`; page metadata is stored in `documents.ocr_raw_data.pages`.

## 4. Current PDF Path

PDFs use the same server extraction function but a different Flutter preparation step:

1. `DocumentUploadService.submitExpenseFlow()` uploads the original PDF as `company_id/document_id/original.pdf` and creates one `documents` row.
2. `_processDocumentBackground()` calls `BackgroundExtractionService.processDocument()`.
3. `BackgroundExtractionService` renders up to `kMaxPdfPagesToExtract = 3` pages with `pdfx`.
4. It uploads rendered pages as `page_1.jpg`, `page_2.jpg`, etc. under the same document folder.
5. It updates `documents.ocr_raw_data.pages` with the rendered page paths.
6. It invokes `process-document` once for the document.

PDF behaves differently because page rendering is capped at 3 pages and the rendered/compressed JPEG pages tend to be smaller and more predictable than multiple camera/gallery images.

## 5. Supabase Storage Representation

Current secure path shape:

```text
documents bucket:
company_id/document_id/original.pdf
company_id/document_id/page_1.jpg
company_id/document_id/page_2.jpg
company_id/document_id/page_3.jpg
```

Important findings:

- All upload paths are tenant-prefixed by `company_id`.
- All multi-page paths are grouped under the same `document_id`.
- `process-document` validates paths with `isSafeDocumentStoragePath(path, companyId, documentId)` before signing.
- Fresh writes now prefer `file_path` and page `file_path` instead of persistent URL fields.
- `StorageService.uploadDocument()` still generates a long-lived signed URL for optimistic preview compatibility; durable new document inserts no longer store `file_url`, but the signed URL still exists in memory and is a tracked security risk until preview compatibility is fully migrated.
- The bucket is still public in the historical migration; the current remediation plan must not rely on public URLs.

## 6. Postgres Representation

Confirmed tables/columns:

- `documents`: business document row; includes `id`, `company_id`, `status`, `file_name`, `file_type`, `file_path`, `file_url` legacy column, `ocr_raw_data`, `extraction_raw`, `extraction_clean`, `category_id`, amount/type/date fields, and `extraction_started_at`.
- `document_items`: extracted line items.
- `products`, `product_prices`: product intelligence outputs from `recognize-products`.
- `review_items`: Review Center records.
- `expenses`: expense metadata linked to `documents`.

Not found:

- No `document_pages` table exists in migrations.
- No `extraction_jobs` table exists.

Current page model:

- Multiple pictures and rendered PDF pages are stored as JSON metadata in `documents.ocr_raw_data.pages`.
- Existing single-image/legacy documents may only have `documents.file_path` or old URL fields, so `process-document` must keep fallback support.

## 7. Flutter Payload Sent To `process-document`

`ExtractionService.invokeProcessDocument()` sends:

```json
{ "documentId": "<uuid>" }
```

It does not send `companyId`, `imageUrl`, base64 image data, page URLs, or OpenRouter keys. It first reads `documents.company_id` client-side only to validate local context, but the Edge Function derives tenant access again through RLS and does not trust a client-supplied company id.

## 8. What `process-document` Expects

Request schema:

- POST JSON object
- allowed field: `documentId`
- max request body: `MAX_JSON_BYTES = 4096`

Server expectations:

1. Authorization header must be present.
2. Supabase Auth user must be valid.
3. Document must be readable through the user-scoped/RLS client.
4. `company_id` is derived from the DB row.
5. Service role is used only after tenant validation.
6. Image sources are resolved from `ocr_raw_data.pages`, direct `file_path`, or legacy URL fallback.

## 9. How Images Are Sent To OpenRouter

The Edge Function signs/downloads private storage objects server-side, converts bytes to base64 data URLs, and sends OpenRouter content blocks like:

```ts
{
  role: "user",
  content: [
    { type: "image_url", image_url: { url: "data:image/jpeg;base64,..." } },
    { type: "image_url", image_url: { url: "data:image/jpeg;base64,..." } },
    { type: "text", text: extractionPrompt(currency, pageCount) }
  ]
}
```

This is privacy-compatible with a private bucket because Flutter does not send document bytes to OpenRouter and does not expose the OpenRouter key.

## 10. Where The Connection Is Closing

The observed stack shows the close at the mobile HTTP call boundary:

```text
IOClient.send
FunctionsClient.invoke
ExtractionService._invokeWithDetails
ExtractionService.invokeProcessDocument
```

The timing is approximately 60 seconds after `[BG] Invoking process-document`. `process-document` currently does all of this before responding:

1. Auth/RLS validation.
2. Page-path signing.
3. Sequential image download.
4. Base64 encoding.
5. One potentially large OpenRouter VLM call with `OPENROUTER_REQUEST_TIMEOUT_MS = 90_000`.
6. JSON parse/normalization.
7. Optional fallback document-type classifier call.
8. DB update and `document_items` delete/insert.
9. Return HTTP response.

The client connection closes before the function sends headers. The function may still be processing, but Flutter marks the document flagged because the client sees a transport exception.

## 11. Why PDF Behaves Differently

PDF is capped and normalized before extraction:

- `BackgroundExtractionService` renders at most 3 PDF pages.
- Rendered pages are compressed if they exceed roughly 1.5 MB.
- The filenames and page count are predictable.

Multi-picture image uploads can still be 2-5 camera/gallery images. They are preprocessed to max dimension 1600 and JPEG quality 82, but several pages still increase:

- image fetch time
- base64 size
- OpenRouter vision processing time
- response-generation time

That pushes the synchronous Edge Function response beyond the mobile HTTP connection tolerance.

## 12. Most Efficient Solution

The most efficient production-safe fix is not a full schema rewrite today. It is to make `process-document` job-style at the HTTP boundary while preserving the current page model:

1. Keep Flutter sending only `{ documentId }`.
2. Keep Edge Function tenant validation exactly as-is.
3. Keep `ocr_raw_data.pages` support and `documents.file_path` fallback.
4. In `process-document`, after auth/RLS/source validation, schedule the heavy extraction work with `EdgeRuntime.waitUntil(...)` and return `202 accepted` quickly.
5. Move the existing heavy extraction body into a server-side background workflow that:
   - downloads/signs page images
   - sends OpenRouter request
   - saves `documents` and `document_items`
   - marks `flagged` on AI/parse/timeout failure
   - triggers product recognition after `document_items` exist
6. Update Flutter `ExtractionService` to treat `202` as accepted and not require a completed extraction response.
7. Prevent Flutter from marking the document flagged on a client transport close if the server accepted or may still be working; with the job-style response this should become rare.

This fixes the actual broken boundary without changing the storage model, moving OpenRouter to Flutter, exposing keys, or breaking existing single-image/PDF fallback.

## 13. Files To Modify

Required minimal code files:

- `supabase/functions/process-document/index.ts`
  - split fast request validation from heavy extraction
  - use `EdgeRuntime.waitUntil` for the heavy workflow
  - return `202 accepted` quickly
  - trigger product recognition after extraction completes
- `lib/services/extraction_service.dart`
  - accept HTTP `202` as successful extraction start
  - skip immediate post-processing assumptions when the server accepted async work

Potential follow-up files, only if validation shows a gap:

- `lib/providers/documents_provider.dart`
  - adjust background timeout/error handling if it still marks accepted async jobs as failed
- `lib/features/documents/data/services/document_management_service.dart`
  - refresh behavior for re-extract if needed
- `lib/features/review_center/data/repositories/review_center_repository.dart`
  - retry flow refresh behavior if needed

## 14. Files To Leave Untouched

Leave these untouched for this fix unless a direct regression is proven:

- Dashboard UI
- FAB / bottom navigation
- Review Center UI
- Products UI
- Supplier UI
- Auth UI
- RLS policies
- Storage bucket public/private migration
- OpenRouter model selection
- `recognize-products` internals, except invoking it after extraction if needed

## 15. Validation Checklist

Static validation:

- `deno check supabase/functions/process-document/index.ts`
- `flutter analyze --no-fatal-infos lib/services/extraction_service.dart lib/services/background_extraction_service.dart lib/providers/documents_provider.dart`

Runtime validation:

1. Single image invoice: one document, no client freeze, status changes from `processing` to `completed` or `flagged` through DB/realtime.
2. Two-picture invoice: one document, `ocr_raw_data.pages.length == 2`, no `ClientException`, completed or flagged with server-side note.
3. Three-picture invoice: one document, up to three OpenRouter image blocks, no mobile HTTP close.
4. Five-picture delivery note: current function should reject or flag over max pages unless batching is implemented; follow-up batching needed for 4+ pages.
5. PDF invoice: original PDF remains, rendered pages remain, extraction still starts and completes/flags server-side.
6. Bad second page: server should mark partial/flagged instead of mobile transport failure.
7. Cross-tenant process attempt: unauthorized user receives 403 and no service-role side effects.
8. Background/foreground app during extraction: document status updates by realtime/refetch.
9. Retry failed multi-page document: safe retry, no duplicate `document_items` because extraction deletes old rows before inserting.

## Root Cause Ranking

### A. Flutter waits synchronously for a long Edge Function call - confirmed

Evidence for:

- Stack fails at `FunctionsClient.invoke`/`IOClient.send`.
- Failure occurs around 60 seconds after invoking `process-document`.
- `process-document` does not return until OpenRouter and DB writes finish.

Evidence against:

- Flutter starts the task with `unawaited()`, so the visible UI returns quickly. However the background task still holds the HTTP call open.

### B. `process-document` exceeds the client/functions HTTP tolerance - confirmed likely

Evidence for:

- OpenRouter timeout is 90 seconds, longer than the observed 60-second client close.
- Multi-page VLM calls are slower than one image.

Evidence against:

- Exact Supabase infrastructure timeout is not logged locally; Edge logs should confirm whether the function continues after the client disconnect.

### C. Multi-picture OpenRouter request is too heavy - likely contributor

Evidence for:

- Each page becomes a base64 image block.
- More pages increase bytes and vision processing time.
- `MAX_IMAGES_PER_REQUEST = 3`; 4+ pages already exceed the function limit.

Evidence against:

- Preprocessing does resize/compress to 1600px/quality 82, so images are not raw full-resolution camera files by the time they are uploaded.

### D. Images are too large - possible contributor

Evidence for:

- WhatsApp/camera images can still be hundreds of KB to multiple MB after preprocessing.
- Server allows up to 8 MB per image.

Evidence against:

- Flutter preprocessing is already in place for image pages and PDF pages.

### E. Extraction plus product recognition blocks one HTTP response - partially false

Evidence for:

- The extraction function itself blocks on OpenRouter and the fallback type classifier.

Evidence against:

- `recognize-products` is currently called by Flutter after `process-document` returns, so product recognition is not inside the `process-document` HTTP duration today. If we make `process-document` async, product recognition must move server-side or be deferred until extraction completes.

### F. Add Page is UI-only - false

Evidence against:

- `ExpenseFormNotifier.addPage()` appends bytes.
- `submitExpenseFlow()` uploads every `payload.pageBytes` entry before inserting the document.
- Multi-page metadata is persisted in `ocr_raw_data.pages`.

### G. `process-document` expects pages but uploads only `file_path` - false for multi-image/PDF, true for legacy fallback

Evidence against:

- `process-document` reads `ocr_raw_data.pages` first.
- It falls back to direct `documents.file_path` for single-image/legacy rows.

### H. Recent storage security changes made requests slower - possible but not primary

Evidence for:

- Path-first signing/downloading is now server-side and private-bucket compatible.

Evidence against:

- Server-side signing/downloading is required for security and should be fast relative to OpenRouter. The observed timeout aligns better with the long synchronous VLM call.

## Implementation Plan

1. Refactor `process-document` into fast request validation plus a background extraction workflow.
2. Return `202 accepted` immediately when `EdgeRuntime.waitUntil` is available.
3. Keep a synchronous fallback if `waitUntil` is unavailable so local/dev behavior remains debuggable.
4. Make Flutter accept both `200` and `202` from `process-document`.
5. Move product recognition trigger after server-side extraction completion so async extraction does not break product intelligence.
6. Keep page discovery exactly as-is: `ocr_raw_data.pages` first, `file_path` fallback, legacy URL fallback.
7. Validate with Deno check and focused Flutter analyzer.