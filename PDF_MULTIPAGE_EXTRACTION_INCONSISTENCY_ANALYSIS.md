# PDF Multipage Extraction Inconsistency Analysis

Date: 2026-06-06

## Scope

This analysis covers the inconsistent PDF extraction behavior for `document (22).pdf`, `document (23).pdf`, and `document (24).pdf` in HospiDash.

The goal is to identify the exact difference between the working and stuck documents before coding. The investigation used live Supabase read-only SQL inspection plus the current Flutter and Edge Function source.

## Executive Finding

The root cause is not that the PDF pipeline only reads page 1.

Live data proves documents 22, 23, and 24 all have two rendered PDF page paths stored in `documents.ocr_raw_data.pages`, and `process-document` currently reads those paths in page-number order.

The actual inconsistency for documents 23 and 24 is a parent-document finalization failure:

- `document_items` were inserted for both documents.
- `document_items.product_id` was populated for both documents, so product matching ran after item extraction.
- But `documents.status` stayed `processing`.
- `documents.extraction_clean` stayed null.
- `documents.extraction_raw` stayed null.

That combination means extraction produced line items, but the parent `documents` update did not persist and the Edge Function still continued to item/product matching. The current `process-document` code awaits Supabase writes but does not check returned `error` values for the parent update, item delete, or item insert. It also writes `documents.status = completed` before line item persistence, which is the wrong ordering for database truth.

## Document 22 vs 23/24 Live Comparison

| Document | Page Count | file_path | document_pages count | extracted items count | product matched items | status | UI status | issue |
|---|---:|---|---:|---:|---:|---|---|---|
| document (22).pdf | 2 | `.../7ecc4eab-76ff-4db7-9653-eab664009cca/original.pdf` | 0, table does not exist | 20 | 0 | completed | completed | Works. Parent `documents` row has `extraction_clean`, totals, type, and completed status. |
| document (23).pdf | 2 | `.../8286872d-dee6-4e39-a5d7-28b8e64e2606/original.pdf` | 0, table does not exist | 8 | 8 | processing | AI extracting | Broken parent finalization. Items exist and are matched, but parent status/extraction fields are null. |
| document (24).pdf | 2 | `.../01c93f98-3d18-4dbf-a1e2-cd2922e60eaa/original.pdf` | 0, table does not exist | 15 | 15 | processing | AI extracting | Broken parent finalization. Items exist and are matched, but parent status/extraction fields are null. |

## Live Schema Facts

The live database contains these relevant tables:

- `documents`
- `document_items`
- `products`
- `product_prices`

The live database does not contain:

- `document_pages`
- `document_line_items`

Therefore, page storage currently uses `documents.ocr_raw_data.pages`, not a normalized `document_pages` table.

The live `documents` table does not have a top-level `supplier_name` or `raw_text` column. Those values live inside `documents.extraction_clean`.

## Why Document 22 Succeeds

Document 22 succeeds because its pipeline persisted all three layers coherently:

1. PDF page rendering produced two page images.
2. Both rendered page paths were stored in `documents.ocr_raw_data.pages`:
   - `page_1.jpg`
   - `page_2.jpg`
3. `process-document` read both page paths from `ocr_raw_data.pages`.
4. OpenRouter returned structured extraction that included page 2 line items.
5. The parent `documents` row was updated:
   - `status = completed`
   - `document_type = delivery_note`
   - `document_number = L02616077`
   - `total_amount = 1454.66`
   - `tax_amount = 252.46`
   - `extraction_clean` populated
6. `document_items` contains 20 rows.

Document 22 is proof that the pipeline can access and extract page 2.

## Why Documents 23/24 Stay Extracting

Documents 23 and 24 stay extracting because the UI reads `documents.status`, and both rows are still `processing`.

The stuck UI is not caused by local Flutter background state. Flutter clears `processingDocumentsProvider` after the background call, but the document card renders `_ProcessingCard` whenever `DocumentModel.status == DocumentStatus.processing`. That value is parsed from `documents.status`.

For docs 23/24, live DB state is contradictory:

- `document_items` exist.
- `document_items.product_id` values exist.
- `documents.status` is still `processing`.
- `documents.extraction_clean` is null.
- `documents.extraction_raw` is null.

This means local logs such as `[BG] Extraction done` or `[BG] Extraction accepted` only prove the invocation returned or was queued. They do not prove the final parent row was completed.

## Does PDF Extraction Use One Page Or All Pages?

Current code uses all rendered pages up to `kMaxPdfPagesToExtract = 3`.

Flutter PDF path:

1. `BackgroundExtractionService.processDocument()` detects `mimeType == 'application/pdf'`.
2. `_renderPdfPages()` opens the PDF with `pdfx`.
3. It renders pages `1..pagesToRender`, where `pagesToRender = min(totalPages, 3)`.
4. It uploads each rendered page as `page_1.jpg`, `page_2.jpg`, etc.
5. It writes all uploaded page paths into `documents.ocr_raw_data.pages`.
6. It invokes extraction by `documentId` through `ExtractionService.invokeProcessDocument()`.

Edge Function path:

1. Flutter sends only `{ documentId }`.
2. `process-document` authenticates the user.
3. It reads the document through the user/RLS client.
4. It derives `company_id` from the document row, not Flutter input.
5. It calls `resolveDocumentImageSources()`.
6. `resolveDocumentImageSources()` reads `documents.ocr_raw_data.pages`, signs each safe path, sorts by `page_number`, and returns all signed page URLs.
7. It falls back to `documents.file_path` only when no page paths exist and the path is not a PDF.
8. It falls back to legacy URLs only after path-based sources fail.

Therefore, the current source-of-truth contract is document-centric, not image-centric.

## Is Page Selection Deterministic Or Accidental?

Current page selection is deterministic:

- PDF pages are rendered starting at page 1.
- Rendered pages are stored with explicit `page_number`.
- `process-document` sorts page paths by `page_number`.

Earlier behavior may have been image-centric or selected-page-based, but the current code and live DB rows for documents 22/23/24 show deterministic two-page metadata in `ocr_raw_data.pages`.

## Are Pages Stored In `document_pages`?

No.

There is no live `document_pages` table and no migration in this workspace creates one.

Pages are stored in `documents.ocr_raw_data.pages` like this:

```json
{
  "source": "flutter_pdf_render",
  "page_count": 2,
  "pages": [
    { "page_number": 1, "file_path": ".../page_1.jpg", "mime_type": "image/jpeg" },
    { "page_number": 2, "file_path": ".../page_2.jpg", "mime_type": "image/jpeg" }
  ]
}
```

## Is `documents.file_path` Overwritten By Page Rendering?

No, not in the current PDF path.

For documents 22, 23, and 24, `documents.file_path` points to `original.pdf`, not `page_1.jpg` or `page_2.jpg`.

The current PDF renderer uploads rendered pages and stores their paths in `ocr_raw_data.pages`. It does not update `documents.file_path` inside the page loop.

## Are All Extracted Items Saved?

For documents 23 and 24, extracted items were saved:

- Document 23: 8 `document_items`
- Document 24: 15 `document_items`

All items for documents 23 and 24 also have `product_id`, which proves product matching ran after item insertion.

However, the parent extraction payload was not saved:

- `documents.extraction_clean = null`
- `documents.extraction_raw = null`
- `documents.document_number = null`
- `documents.total_amount = null`
- `documents.tax_amount = null`
- `documents.document_type = unknown`

So the failure is not “items never saved.” The failure is inconsistent DB finalization across parent document and child items.

## Is Status Updated Correctly?

No.

The current Edge Function attempts to update the parent document to `completed`, but it does not check the returned Supabase `error`. It then proceeds to delete/insert `document_items` and invoke product matching.

Current risky order:

1. Update `documents` to `completed` with extraction fields.
2. Delete old `document_items`.
3. Insert new `document_items`.
4. Invoke product matching.

Current risky error handling:

- Parent document update result is not checked.
- Item delete result is not checked.
- Item insert result is not checked.
- Product matching can be invoked even if item persistence failed or produced zero rows.

The observed docs 23/24 state matches this class of bug: child item work completed, but parent status and extraction fields did not.

## Is Flutter Reading The Correct Status?

Yes.

Flutter list rendering uses the canonical `documents.status` field:

- `DocumentModel.fromJson()` parses `json['status']`.
- `DocumentCard` renders `_ProcessingCard` when `document.status == DocumentStatus.processing`.
- The “AI extracting...” label is shown by `_ProcessingCard`.
- `documentsRealtimeListProvider` streams rows from `documents` filtered by `company_id`.

The UI is correctly showing what the database says. The bug is that the database remains `processing` after partial extraction persistence.

## Process-Document Input Contract

Flutter sends:

```json
{
  "documentId": "..."
}
```

It does not send `imageUrl` to the Edge Function.

The Edge Function request schema allows only `documentId`. It derives image sources server-side from the stored document row and storage metadata.

This is the expected tenant-safe contract because Flutter does not choose arbitrary image URLs and does not send `company_id` as trusted input.

## Multi-Page Merge Logic

Current merge behavior:

- If 1-3 images are present, all pages are sent to a single OpenRouter VLM request.
- If more than 3 images are present, pages are processed in batches of 3 and merged.
- Batch merge concatenates line items and dedupes by normalized description, quantity, and line total.
- Totals and tax fields prefer the last non-null batch value.

For documents 23/24, both PDFs have 2 pages, so they should use the single-request path, not the batching path.

## Root Cause

Root cause: `process-document` treats awaited Supabase writes as successful without checking returned `error` values, and its write order allows child items/product matching to succeed while the parent `documents` row remains `processing`.

Secondary design issue: status is attempted before line items are durably saved. A document should not become `completed` until the parent extraction payload and item rows are both saved successfully.

This explains the exact observed difference:

- Document 22: parent update and item insert both persisted.
- Documents 23/24: item insert and product matching persisted, but parent extraction/status did not persist; the Edge Function did not surface that as a failure.

## Minimal Safe Solution

Do not rewrite the extraction system.

Make `process-document` use database truth and checked writes:

1. Keep the Flutter contract as `{ documentId }`.
2. Keep `ocr_raw_data.pages` as the current page source; do not introduce `document_pages` in this fix.
3. Keep fallback to legacy `documents.file_path` for single images and old documents.
4. Extract all resolved pages as today.
5. Normalize and merge extraction as today.
6. Build line item rows before writing.
7. Delete old `document_items` and insert new rows with explicit error checks.
8. If zero valid item rows are produced, do not invoke product matching. Mark the document `flagged` with a note such as `No line items extracted from PDF pages.` The schema has no `needs_review` status, so `flagged` is the safe existing review state.
9. Update the parent `documents` row to `completed` only after item persistence succeeds.
10. Check the parent update error. If it fails, throw so the function marks the document `flagged` instead of logging success.
11. Invoke product matching only after item rows are saved and parent finalization succeeds.
12. Do not let product matching failure change `documents.status` back to processing.

This preserves:

- document 22 behavior
- single-image fallback
- PDF preview
- tenant isolation
- server-side OpenRouter key protection
- page aggregation through current metadata

## Validation Plan

Required validation after implementation:

1. `deno check supabase/functions/process-document/index.ts`
2. `flutter analyze --no-fatal-infos lib/services/extraction_service.dart lib/services/background_extraction_service.dart lib/providers/documents_provider.dart`
3. Re-run read-only SQL comparison after re-extracting docs 23/24:
   - `documents.status = completed` or `flagged`
   - never left as `processing`
   - `extraction_clean` populated for completed documents
   - `document_items` count is nonzero for product PDFs
   - product matching only runs when item rows exist
4. Regression checks:
   - Document 22 still completed with page 2 items.
   - Document 23 completes with both-page items or flags with a clear note.
   - Document 24 completes with both-page items or flags with a clear note.
   - Single image extraction still uses `documents.file_path` fallback.
   - PDF with products only on page 1 works.
   - PDF with metadata page 1 and totals/page rows on page 2 works.
   - Re-extraction deletes old items before inserting new items and does not duplicate rows.
   - Company A cannot process Company B's document because access check still uses user/RLS read first and server-derived `company_id`.

## Implemented Fix

Implemented in `supabase/functions/process-document/index.ts` after this analysis was created:

1. `document_items` delete errors are now checked.
2. Valid line-item rows are built before final status update.
3. Zero valid line items now marks the document `flagged` with `ocr_status = failed` and does not invoke product matching.
4. `document_items` insert errors are now checked.
5. `documents.status = completed` and `documents.ocr_status = completed` are written only after item persistence succeeds.
6. Parent document finalization errors now throw, allowing the failure handler to mark the document `flagged` instead of silently leaving it `processing`.
7. Product matching remains after item persistence and parent finalization, and remains non-blocking.

## Validation Results

Completed validation:

- `deno check supabase/functions/process-document/index.ts` passed.
- `flutter analyze --no-fatal-infos lib/services/extraction_service.dart lib/services/background_extraction_service.dart lib/providers/documents_provider.dart` completed with existing info-level style diagnostics only; no errors.
- VS Code diagnostics reported no errors for the touched files and this analysis document.
- `npx supabase functions deploy process-document` succeeded for project `qbvfeizmcuctmhrxkvbx`.

Runtime note: documents 23 and 24 were already stuck before this deploy. They should be re-extracted through the app after the deploy, or repaired with an explicit data-remediation step, so their parent `documents` rows can be brought out of `processing` using the corrected finalization behavior.
