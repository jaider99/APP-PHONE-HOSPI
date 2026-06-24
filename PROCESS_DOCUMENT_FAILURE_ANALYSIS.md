# Process Document Failure Analysis

Date: 2026-06-02

## Executive Summary

All document extraction requests now fail after the `process-document` Edge Function reaches OpenRouter.

The failure is not in Flutter upload, Supabase Storage, document row creation, background processing startup, JWT invocation, tenant lookup, request validation, or image fetching. The current logs show the function reaches the OpenRouter call and OpenRouter returns HTTP 400 with the message `Provider returned error`.

The most likely regression is the recent `process-document` OpenRouter payload change made for multi-image support:

- the function now always fetches the document image itself,
- base64-encodes it into a `data:image/...;base64,...` URL,
- builds a multimodal `content` array with the text block first and image blocks after it,
- and sends that payload to `nvidia/nemotron-nano-12b-v2-vl:free`.

That change affects every document type, including single images and rendered PDFs, because every path now passes through the same OpenRouter request builder. OpenRouter accepts the request envelope and model id, then the selected provider rejects the payload.

The exact provider-side reason is still not fully exposed because current client-facing extraction only surfaces `error.message` from OpenRouter. For this run, that message is generic: `Provider returned error`. The function logs the raw OpenRouter body, but the Supabase CLI available in this workspace does not expose a `functions logs` command, and hosted logs were not retrievable from this shell.

## 1. What Is Currently Happening

Observed Flutter flow:

```text
[StorageService] uploadDocument SUCCESS
[BG] Invoking process-document doc=...
[Extraction][doc=...][file=document (21)_rendered.jpg] invoke process-document
[LineItems][doc=...] extraction pipeline started
process-document failed status=500 reason=Internal Server Error details=OpenRouter error 400: Provider returned error
[BG] Unexpected error doc=... Exception: OpenRouter error 400: Provider returned error
[BG] Marking flagged doc=... Unexpected extraction error: Exception: OpenRouter error 400: Provider returned error
```

Current pipeline:

```text
StorageService.uploadDocument()
  -> uploads original image or rendered PDF JPEG to private Supabase Storage
  -> returns long-lived signed URL and storage path

documents insert/update
  -> one tenant-scoped row with company_id
  -> file_url/file_path for original upload
  -> rendered_image_url for rendered PDFs or background handoff

DocumentUploadService._processDocumentBackground()
  -> starts detached background extraction

BackgroundExtractionService.processDocument()
  -> for PDFs: renders page 1 to JPEG and uploads under company_id/document_id
  -> for images: reads existing file_url
  -> updates documents.rendered_image_url with the resolved image URL
  -> calls ExtractionService.invokeProcessDocument()

ExtractionService.invokeProcessDocument()
  -> validates company_id exists
  -> invokes Supabase Edge Function process-document with body { documentId }

process-document Edge Function
  -> validates Authorization/JWT
  -> reads document through user-scoped Supabase client
  -> derives company_id from authorized document row
  -> creates service-role client only after tenant context is established
  -> resolves image source from ocr_raw_data pages, rendered_image_url, or file_url
  -> fetches image bytes
  -> base64-encodes image bytes into data URL
  -> calls OpenRouter
  -> receives HTTP 400 from OpenRouter/provider
  -> throws Error("OpenRouter error 400: Provider returned error")
  -> marks document flagged
  -> returns 500 to Flutter
```

## 2. Where The Failure Occurs

The failure occurs inside `supabase/functions/process-document/index.ts`, at the OpenRouter HTTP call boundary:

```ts
const openRouterResponse = await fetch(OPENROUTER_ENDPOINT, {
  method: "POST",
  headers: {
    Authorization: `Bearer ${apiKey}`,
    "Content-Type": "application/json",
    "HTTP-Referer": "https://hospidash.app",
    "X-Title": "HospiDash Document Extraction",
  },
  body: openRouterPayload,
});
```

Evidence:

- Flutter receives `OpenRouter error 400: Provider returned error` from the function.
- That string is only thrown after the function has already called OpenRouter and read the non-OK OpenRouter response body.
- If JWT validation failed, the client would receive 401.
- If document access failed, the client would receive 403.
- If request validation failed, the client would receive 400 before OpenRouter.
- If image resolution failed, the function would return `imageUrl is required`.
- If image fetch failed, the thrown error would be `Image fetch failed: <status>` or `Image fetch timed out`, not `OpenRouter error 400`.
- If `OPENROUTER_API_KEY` were absent, the function would throw `OPENROUTER_API_KEY not configured` before calling OpenRouter.

Therefore the failure is after image fetch and before response parsing/persistence.

## 3. Why OpenRouter Returns 400

What is proven:

- The model id still exists in OpenRouter public metadata: `nvidia/nemotron-nano-12b-v2-vl:free`.
- The model advertises `text+image+video->text` with `image` and `text` input modalities.
- The request does not include `response_format`, strict JSON schema, `modalities`, provider preferences, or other obvious unsupported structured-output fields.
- The current request uses supported parameters listed by OpenRouter metadata: `max_tokens` and `temperature`.
- OpenRouter returns 400 from the provider layer, not a local Supabase validation error.

Most likely cause:

The selected OpenRouter provider for `nvidia/nemotron-nano-12b-v2-vl:free` is rejecting the current multimodal payload shape, especially one of these recent changes:

1. **Text block before image block**
   - Previous working code sent the `image_url` block first and the text block second.
   - Current code sends text first, then image blocks.
   - The OpenAI-compatible spec permits text first, but provider adapters for some free VLM endpoints can be stricter than the spec.

2. **Always using base64 `data:` image URLs**
   - Previous code already used base64 data URLs for single-image extraction, so this alone is less likely than content order.
   - However the current code now also routes every page source through the new multi-image builder, so any provider limitation in the new builder affects all paths.

3. **Payload size after PDF rendering**
   - Rendered PDFs can still be larger than ordinary images.
   - The Edge Function currently allows up to 8 MB per fetched image; base64 expands that by about 33%.
   - OpenRouter/provider may reject payloads well below the Edge Function’s 8 MB ceiling.
   - This explains PDFs, but it does not fully explain small single images unless they are also above provider-specific limits or the provider rejects the current data URL shape.

4. **Provider-specific rejection masked by generic OpenRouter message**
   - OpenRouter body currently surfaces only `error.message` to Flutter.
   - The generic text `Provider returned error` likely has more detail in `error.metadata.raw`, but current parsing does not include that metadata in the thrown message.

Conclusion:

The root failure is OpenRouter provider rejection of the current `process-document` multimodal request payload. The most suspicious recent change is the multi-image request rewrite, specifically the content block order and universal routing through the new base64 multi-image builder.

The exact provider reason cannot be proven from Flutter logs alone because OpenRouter returned a generic message and hosted function logs are not retrievable with the available CLI command set in this workspace.

## 4. What Changed Recently That Could Have Broken It

Recent extraction-affecting changes found in the current codebase:

### A. Multi-image support changed the OpenRouter request builder

Current code:

```ts
content: [
  {
    type: "text",
    text: extractionPrompt(currency, preparedImages.length),
  },
  ...preparedImages.map((image) => ({
    type: "image_url",
    image_url: { url: image.dataUrl },
  })),
]
```

Previous working pattern from the earlier RCA was:

```ts
content: [
  {
    type: "image_url",
    image_url: { url: dataUrl },
  },
  {
    type: "text",
    text: extractionPrompt(currency),
  },
]
```

This changed all extraction calls, not only multi-image documents.

### B. The function now reads `ocr_raw_data.pages`

For multi-image documents, Flutter writes page metadata to `documents.ocr_raw_data.pages`. The function now tries page paths first, signs them server-side, and sends up to three images.

This is additive and safe for documents without page metadata, because the fallback remains:

```ts
rendered_image_url -> file_url
```

It is unlikely to break all document types by itself.

### C. The image preprocessing size changed

`DocumentImagePreprocessor` now caps image dimension at 1600 and quality at 82 for Flutter-preprocessed images.

This reduces payload size and is unlikely to cause OpenRouter 400. It does not affect PDF rendered images in `BackgroundExtractionService`, which still renders at `page.width * 2.5`, `page.height * 2.5`, quality 88, then compresses only if bytes exceed 1.5 MB.

### D. Error diagnostics changed

The function now reads the OpenRouter error body and throws:

```ts
OpenRouter error ${status}: ${extractOpenRouterErrorMessage(errorBody)}
```

This is why Flutter now sees `Provider returned error` instead of only `OpenRouter error 400`.

Diagnostics improved, but they still do not expose provider metadata such as `error.metadata.raw`.

## 5. Files Involved

Primary failure path:

- `lib/services/storage_service.dart`
  - Uploads document bytes to Supabase Storage.
  - Generates signed URL stored as `file_url`.
  - Storage succeeds in observed logs.

- `lib/providers/documents_provider.dart`
  - Creates document row.
  - Starts detached background extraction via `_processDocumentBackground`.
  - Multi-image path now stores page metadata in `ocr_raw_data`.

- `lib/services/background_extraction_service.dart`
  - Renders PDF page 1 to JPEG.
  - Uploads rendered JPEG.
  - Updates `rendered_image_url`.
  - Invokes `ExtractionService`.

- `lib/services/extraction_service.dart`
  - Calls `supabase.functions.invoke('process-document', body: {'documentId': documentId})`.
  - Logs FunctionException status/reason/details.
  - Correctly surfaces Edge Function error to Flutter.

- `supabase/functions/process-document/index.ts`
  - Owns JWT validation, tenant derivation, image fetch, OpenRouter request, extraction parsing, document updates, and document item inserts.
  - Current failure occurs here when OpenRouter returns 400.

Supporting shared Edge Function files:

- `supabase/functions/_shared/request.ts`
  - Allows only `{ documentId }` and bounds request size.

- `supabase/functions/_shared/rate_limit.ts`
  - Per-user/per-company rate limiting.

- `supabase/functions/_shared/redact.ts`
  - Redacts bearer tokens, JWTs, URLs, UUIDs, and storage paths from logs.

## 6. Flutter Caller Answers

### What payload is Flutter sending?

Flutter sends exactly:

```json
{
  "documentId": "..."
}
```

### Is it sending `documentId`?

Yes.

### Is it sending `companyId`?

No. `companyId` is resolved in Flutter only for local validation/logging and then derived server-side in the function from the authorized document row.

### Is it sending `imageUrl`?

No. This is intentional after security hardening. The Edge Function derives image URLs from the authorized document row.

### Is it sending `currency`?

No. The Edge Function reads `currency` from the document row and defaults to `EUR`.

### Is it sending `fileName` or `fileType`?

No. These are not accepted by `process-document` request validation.

### Is `imageUrl` null?

Not at the failing boundary. If image URL resolution were empty, the function would return `imageUrl is required`, not `OpenRouter error 400`.

### Is `imageUrl` a signed URL?

For fallback single-image/PDF paths, yes: `file_url` and `rendered_image_url` are signed URLs stored in the document row. For multi-image page paths, the function signs storage paths server-side for 15 minutes.

### Is `imageUrl` expired?

Unlikely for the observed failure. The function fetches the image before OpenRouter. An expired signed URL would fail at `fetchImageBytes()` with an image fetch error, not after the OpenRouter call.

### Is `imageUrl` accessible from the Edge Function runtime?

Yes for this failure path, because the function reaches OpenRouter after fetching and base64-encoding the image.

### Is the rendered JPG uploaded before invoking the function?

Yes. `BackgroundExtractionService` uploads the rendered PDF image, then updates `documents.rendered_image_url`, then invokes the function.

### Is the function receiving a PDF URL instead of image URL?

For PDFs, the function should use `rendered_image_url` first. The observed filename `document (21)_rendered.jpg` and logs indicate PDF rendering/upload completed before invocation.

### Is the file path correct?

The storage contract remains:

```text
company_id/document_id/file
```

The upload service constructs paths this way when `documentId` is supplied.

### Is the JWT/session passed correctly?

Yes for the observed failure. Otherwise the function would return 401 before OpenRouter.

## 7. Edge Function Findings

### Request validation

`readProcessDocumentRequest()` allows only `documentId`:

```ts
allowedFields: ["documentId"]
```

This means older client payload fields such as `companyId`, `imageUrl`, and `currency` would now be rejected if sent. Current Flutter does not send them.

### JWT validation

The function requires `Authorization`, creates a user-scoped Supabase client, and calls `auth.getUser()`.

### Tenant validation

The function selects the document via user-scoped client:

```ts
.from("documents")
.select("id, company_id, rendered_image_url, file_url, currency, ocr_raw_data")
.eq("id", documentId)
.maybeSingle()
```

This relies on RLS and derives `company_id` from the returned row.

### Image fetching

The function fetches the resolved image URL with a 15 second timeout and an 8 MB max byte limit.

The failure happens after this step.

### OpenRouter request construction

Current request:

```json
{
  "model": "nvidia/nemotron-nano-12b-v2-vl:free",
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "..." },
        { "type": "image_url", "image_url": { "url": "data:image/jpeg;base64,..." } }
      ]
    }
  ],
  "max_tokens": 2000,
  "temperature": 0.05
}
```

No strict `response_format` is used.

## 8. Environment / Secrets Check

Verified:

- `npx supabase functions list` shows `process-document` active at version 28, updated `2026-06-01 21:54:58 UTC`.
- `deno check` passes for `process-document` and shared helpers.
- VS Code diagnostics show no errors in the function or Flutter caller files.
- OpenRouter public metadata confirms the model id exists and supports image input.

Not independently verified from this shell:

- `npx supabase secrets list` failed with `Access token not provided`.
- However, the observed error proves the function has enough OpenRouter configuration to call OpenRouter and receive a provider-level 400. Missing key would produce `OPENROUTER_API_KEY not configured` before OpenRouter or an OpenRouter auth error, not this provider response.

## 9. Minimal Reproduction Strategy

To prove the exact provider rejection reason without touching production logic:

1. Pick a known failed document id from the current company.
2. Re-run extraction once after adding structured internal OpenRouter error logging for:
   - `error.code`
   - `error.message`
   - `error.metadata.raw`
   - `error.metadata.provider_name`
   - content block types
   - payload character count
   - image bytes/base64 chars/dimensions
3. Compare two isolated OpenRouter payload variants using the same fetched image:
   - Variant A: current `text -> image_url` order.
   - Variant B: previous known-working `image_url -> text` order.
4. Keep model, prompt, image bytes, auth headers, and request parameters identical.

Expected discriminating result:

- If Variant B succeeds and Variant A fails, the root cause is provider-specific content order sensitivity.
- If both fail with the same provider metadata, inspect payload size/data URL support.
- If URL-based `image_url` succeeds while data URL fails, the provider no longer accepts base64 data URLs for this model/route.
- If smaller compressed data URL succeeds, the root cause is payload size.

## 10. Possible Solutions To Evaluate

### Solution A — Restore previous content order

If provider metadata or A/B test shows content-order rejection, change request construction to put images first and text last, matching the previous working request.

Risk: Low. It changes only the OpenRouter payload order and preserves security hardening, Edge Functions, model, storage, and tenant isolation.

### Solution B — Improve OpenRouter error diagnostics

Parse and log safe provider metadata:

```ts
error.code
error.message
error.metadata.raw
error.metadata.provider_name
```

Do not log keys, signed URLs, image bytes, or raw OCR.

Risk: Low. It improves root-cause visibility and can keep client-facing messages safe.

### Solution C — Reduce Edge Function image payload cap

If payload size is the cause, reduce `MAX_IMAGE_BYTES` from 8 MB to a model-safe value and compress rendered PDF images more aggressively before OpenRouter.

Risk: Medium. Too much compression can harm OCR accuracy.

### Solution D — Use direct signed image URLs for OpenRouter

If data URLs are rejected but signed URLs work, send the signed URL to OpenRouter instead of base64.

Risk: Medium. It exposes a temporary signed URL to OpenRouter. This is still server-side and time-limited, but weaker than not sharing URLs.

### Solution E — Change model

Do not do this unless the model endpoint is proven broken or incompatible. The model id is still listed and supports image input.

Risk: High for regression and extraction quality drift.

## 11. Safest Fix Recommendation

The safest fix sequence is:

1. First, improve diagnostics to include sanitized provider metadata from OpenRouter.
2. Then restore the previous known-working content order: image blocks first, text block last.
3. Keep all security hardening:
   - caller JWT required,
   - company_id derived from DB/RLS,
   - no OpenRouter key in Flutter,
   - no client-trusted imageUrl,
   - no dashboard/FAB/navigation/product/supplier UI changes.
4. Re-deploy only `process-document`.

Why this is safest:

- It addresses the only recent change that affects all document types at the failing boundary.
- It preserves the multi-image extension: multiple images can still be sent, just before the text block.
- It does not change model, authentication, storage, tenant isolation, database schema, or Flutter UI.

## 12. Validation Plan

Run validation in this order:

1. **Static checks**
   - `deno check supabase/functions/process-document/index.ts supabase/functions/_shared/request.ts supabase/functions/_shared/rate_limit.ts supabase/functions/_shared/redact.ts`
   - Focused Flutter diagnostics for caller files.

2. **Single image smoke test**
   - Upload one known-good invoice image.
   - Confirm OpenRouter status is 200.
   - Confirm document status becomes `completed`.
   - Confirm supplier/type/date/total/line items persist.

3. **Rendered PDF smoke test**
   - Upload one known-good PDF.
   - Confirm rendered JPEG is stored under `company_id/document_id`.
   - Confirm `rendered_image_url` is set.
   - Confirm OpenRouter status is 200.

4. **Delivery note / albaran test**
   - Confirm final `document_type = delivery_note`.
   - Confirm no invoice-only assumptions are introduced.

5. **Multi-image invoice test**
   - Upload header/products/totals images.
   - Confirm one document row.
   - Confirm up to three image blocks sent.
   - Confirm no duplicate line items.

6. **Re-extraction test**
   - Re-extract an existing document.
   - Confirm fallback paths still work when `ocr_raw_data.pages` is absent.

7. **Tenant safety check**
   - Confirm every document update/delete/insert remains filtered by `company_id`.
   - Confirm `document_items` delete/insert remains scoped by both `document_id` and `company_id`.

## 13. Current Status

Root-cause confidence: high that the failure is in the current OpenRouter request payload generated by `process-document`.

Exact provider reason: not fully proven because OpenRouter only surfaced `Provider returned error` to Flutter and hosted function logs were not accessible from the available CLI.

Do not change the model, remove Edge Functions, move AI calls to Flutter, or weaken tenant/security controls. The next code change should be the smallest server-only patch: better provider metadata logging plus restoring image-first content order.