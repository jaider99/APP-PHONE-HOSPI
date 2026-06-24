# Multi-Image Extraction Debug

## 1. Current Pipeline Map

### Single image document upload

1. `DocumentUploadService.uploadDocument` creates one `documentId`.
2. The image is preprocessed by `DocumentImagePreprocessor.preprocessSinglePage`.
3. `StorageService.uploadDocument` uploads one image to `documents/{company_id}/{document_id}/{file_name}`.
4. One row is inserted into `documents` with `company_id`, `file_url`, `file_path`, `file_type`, and `status = processing`.
5. `BackgroundExtractionService.processDocument` reads the document `file_url`, writes it to `rendered_image_url`, and calls `ExtractionService.invokeProcessDocument`.
6. `ExtractionService` invokes the Supabase Edge Function `process-document` with only `{ documentId }`.
7. `process-document` authorizes the caller by selecting the document through the user client, fetches one image URL, base64-encodes it as a data URL, and sends one `image_url` content item to OpenRouter.

### PDF upload

1. PDF upload still creates one `documents` row.
2. `BackgroundExtractionService` renders the first PDF page to JPEG, compresses it if larger than about 1.5 MB, uploads the rendered image under the same `company_id/document_id` storage prefix, and sets `rendered_image_url`.
3. `process-document` sees `rendered_image_url` first and sends that one rendered image to OpenRouter.

### Multi-image expense/add-page flow

1. `ExpenseFormNotifier` initializes `pages` with the original selected image for image uploads.
2. `_pickAdditionalPage` appends more page bytes via `ExpenseFormNotifier.addPage`.
3. `DocumentUploadService.submitExpenseFlow` receives all page bytes in `pages`.
4. `_prepareExpenseUploadPayload` preprocesses every page.
5. If more than one processed page exists, `DocumentImagePreprocessor.mergePages` stitches all pages vertically into one JPEG.
6. Only that merged JPEG is uploaded to storage.
7. One `documents` row is created, which is correct for tenant and document identity.
8. The Edge Function receives only `{ documentId }`, fetches that merged JPEG, and sends it as one `image_url` object.

## 2. Exact Failure Location

The failure is at the Edge Function to OpenRouter boundary.

The multi-image flow is not currently sending multiple images to the VLM. It sends one merged JPEG. For two or three phone photos, the merged JPEG can become very tall and large. The Edge Function then base64-encodes that merged image into a single data URL and places it in one `image_url` content item.

When OpenRouter rejects the request, `process-document` logs only the HTTP status and then cancels the response body:

```ts
if (!openRouterResponse.ok) {
  await openRouterResponse.body?.cancel();
  throw new Error(`OpenRouter error ${openRouterResponse.status}`);
}
```

That hides the real OpenRouter error message, so Flutter only sees `OpenRouter error 400`.

## 3. Why OpenRouter Returns 400

The most likely root cause is an invalid or oversized vision payload caused by merging multiple pages into one large base64 image. Base64 expands binary size by roughly 33%, and the data URL prefix plus JSON escaping add more overhead.

Observed code facts:

- Client-side preprocessing resizes each page up to at least 1800 px width when smaller.
- Multi-page preprocessing then vertically merges all pages into one image.
- Storage upload allows up to 10 MB for the final file.
- Edge Function allows fetching an image up to 8 MB.
- A single 5 MB merged JPEG becomes about 6.7 MB of base64 before JSON overhead.
- The Edge Function does not log width, height, base64 size, total request size, or OpenRouter response body.

Because the actual OpenRouter body is discarded, the exact provider message is not yet captured. The first fix must expose `response.status` and sanitized `response.body`.

## 4. Current Payload Example

Current multi-image upload effectively becomes:

```json
{
  "model": "nvidia/nemotron-nano-12b-v2-vl:free",
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "type": "image_url",
          "image_url": {
            "url": "data:image/jpeg;base64,<one huge merged page image>"
          }
        },
        {
          "type": "text",
          "text": "You are a document classification and OCR system... Then extract structured data from this document image."
        }
      ]
    }
  ],
  "max_tokens": 2000,
  "temperature": 0.05
}
```

This is not corrupted JSON, and it does not create multiple document rows. It is a single-image VLM payload that becomes fragile for multiple phone pages.

## 5. Correct Payload Example

The safer multi-image payload keeps the document as one logical document but sends each page as its own image content item:

```json
{
  "model": "nvidia/nemotron-nano-12b-v2-vl:free",
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "type": "text",
          "text": "This is ONE document split across multiple images/pages. Analyze all pages together..."
        },
        {
          "type": "image_url",
          "image_url": { "url": "data:image/jpeg;base64,<page_1>" }
        },
        {
          "type": "image_url",
          "image_url": { "url": "data:image/jpeg;base64,<page_2>" }
        },
        {
          "type": "image_url",
          "image_url": { "url": "data:image/jpeg;base64,<page_3>" }
        }
      ]
    }
  ],
  "max_tokens": 2000,
  "temperature": 0.05
}
```

## 6. Files That Need Changes

Required surgical changes:

- `lib/providers/documents_provider.dart`
  - Stop merging multi-page expense images into one JPEG.
  - Upload each processed page under the same `company_id/document_id` storage prefix.
  - Keep the existing single `documents` row.
  - Store page URLs/paths in existing document metadata columns if available, without requiring a schema rebuild.

- `lib/services/document_image_preprocessor.dart`
  - Adjust page preprocessing for VLM payload limits: max dimension around 1600 px and JPEG quality 75-85.
  - Preserve single-image/PDF behavior as much as possible.

- `supabase/functions/process-document/index.ts`
  - Read document page URLs when present; otherwise fall back to existing `rendered_image_url` then `file_url`.
  - Build one text content item plus multiple `image_url` content items.
  - Log image byte sizes, decoded dimensions if feasible, base64 lengths, total payload size, and page count.
  - Capture and return/log the OpenRouter error body instead of hiding it behind `OpenRouter error 400`.
  - Update prompt language from single image to possible multi-page document.

Optional later schema improvement:

- Add a `document_pages` table with `company_id`, `document_id`, `page_number`, `file_path`, and `file_url`, protected by RLS. This is cleaner long-term, but not the smallest safe production repair.

## 7. Risk Analysis

### Tenant isolation

All DB writes must keep `.eq("company_id", companyId)` for updates/deletes. Page storage paths must stay inside `{company_id}/{document_id}/...`. The Edge Function must only read page URLs from the authorized document row selected through the user-scoped client.

### Existing working flows

Single images and PDFs currently work. The fix must preserve fallback behavior so documents without page metadata still use `rendered_image_url` or `file_url` exactly as today.

### Payload size

Sending multiple images separately reduces the risk from very tall merged images, but total request size can still exceed provider limits. The implementation must log total payload size and keep each page compressed under the target budget.

### Data duplication

The existing Edge Function deletes existing `document_items` for the same `document_id` and `company_id` before inserting new rows. That is safe for re-extraction and avoids duplicates if the VLM returns one merged result.

## 8. Implementation Plan

1. Add OpenRouter failure-body logging first in `process-document`.
2. Add Edge Function support for an optional array of document image URLs from the document row, with fallback to the current single URL.
3. Change multi-page expense upload to upload separate page images under the same document storage directory and persist their signed URLs/paths on the one `documents` row.
4. Lower image preprocessing dimensions/quality enough to target sub-700 KB pages without touching unrelated UI or extraction features.
5. Update the VLM prompt to explicitly say all images/pages are one document and line items should be merged without duplication.
6. Validate with static analysis and focused tests/commands available in this repo.

## 9. Rollback Plan

Rollback is small because the fix is additive:

1. Revert the document-row page metadata write in Flutter.
2. Revert the Edge Function page array lookup and return to `rendered_image_url || file_url`.
3. Keep OpenRouter response-body logging if possible; it is diagnostic and does not change extraction semantics.
4. Existing documents continue to work because the single-image fallback remains unchanged.

## Root-Cause Conclusion

For multiple images, the app currently chooses option C from the debugging prompt: the logical page set is transformed into a fragile single-image payload. The payload is not structurally corrupt at the Flutter/Supabase JSON level, but it is likely invalid for OpenRouter/Nemotron because multiple phone pages are merged into one oversized image data URL. The exact OpenRouter rejection reason is currently hidden by the Edge Function.

The smallest safe fix is to stop merging multiple pages, store them under the same document, send them as multiple `image_url` content objects, and expose the real OpenRouter error body for any future rejection.