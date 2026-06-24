# PROCESS_DOCUMENT_JSON_PARSE_ANALYSIS

## 1. Executive Summary

The OpenRouter transport failure is resolved. `process-document` now reaches the AI response stage, but the extraction pipeline still fails before persistence because the Edge Function cannot convert the model response into a valid extraction object.

The failure is not in Flutter upload, Storage, signed URL generation, document lookup, tenant authorization, or the OpenRouter HTTP request itself. It occurs after a successful OpenRouter response and before `documents.status` is updated to `completed`.

The root issue is an AI response contract mismatch:

- `process-document` historically assumed `choices[0].message.content` was a plain JSON string.
- The current multimodal NVIDIA model can return content that is valid semantically but not in that exact shape, for example fenced JSON, explanatory text plus JSON, or assistant content blocks instead of a single string.
- The original parser was too strict and returned `null`, which triggered `Could not parse extraction JSON`.

The safest fix is to harden the parser boundary, add sanitized diagnostics, preserve those diagnostics through the Flutter caller, and normalize a small set of common field aliases without changing tenant/security logic or rewriting the extraction pipeline.

## 2. Evidence From Logs

Observed Flutter sequence from the failing flow:

1. `StorageService.uploadDocument SUCCESS`
2. `[BG] START doc=...`
3. `[BG] Invoking process-document doc=...`
4. `[Extraction][doc=...][file=...] invoke process-document`
5. `[LineItems][doc=...] extraction pipeline started`
6. `process-document failed status=500 ... details=Could not parse extraction JSON`
7. Background service marks the document flagged

What this proves:

- The file upload succeeded.
- The document row exists.
- Background extraction started.
- `process-document` was invoked with a valid `documentId`.
- The failure happened inside the Edge Function after invocation, not in Flutter request construction.

## 3. Failure Location

Primary failure boundary:

- File: `supabase/functions/process-document/index.ts`
- Function: `serve(async (req: Request) => { ... })`
- Exact failure point: the extraction parse step immediately after the successful OpenRouter response is read.

Current critical path:

1. Read `{ documentId }` from request body
2. Authorize document access via JWT-scoped user client
3. Derive `company_id` from the authorized document row
4. Resolve rendered image / page images
5. Fetch and base64-encode images
6. Call OpenRouter chat completions
7. Read `choices[0].message.content`
8. Convert assistant output to text
9. Parse extraction JSON
10. Normalize extraction
11. Persist `documents` and `document_items`

The parse error occurs between steps 8 and 9.

## 4. Raw AI Response Analysis

Important evidence limitation:

- The original failing production run did **not** capture a sanitized raw AI response preview before returning `Could not parse extraction JSON`.
- Therefore the exact raw content for the previously failed invocation is not present in the user-supplied Flutter logs.

What is still provable from code:

- OpenRouter returned HTTP success, otherwise the function would have thrown `OpenRouter error ...` instead.
- The failure occurred before `documents.extraction_raw` was written, because persistence happens only after parsing succeeds.
- The previous implementation did this:

```ts
const content = String(openRouterJson?.choices?.[0]?.message?.content ?? "");
const extraction = parseExtraction(content);
```

That is fragile for modern multimodal/reasoning models because `message.content` may be:

- a plain JSON string
- fenced JSON inside a string
- explanatory text followed by JSON
- an array of assistant content parts
- slightly malformed JSON (for example trailing commas)

The current model is `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free`, which is more likely than the previous VLM to return reasoning-style or block-structured output instead of a single raw JSON string.

Conclusion:

- The exact raw response for the original failed invocation is unavailable.
- The parsing boundary was still defective, because the code assumed a plain string and strict JSON while the model contract is looser.

## 5. Why Parsing Fails

Before parser hardening, `process-document` failed for any of these cases:

1. `message.content` was not a plain string
2. JSON was wrapped in markdown fences
3. Explanatory text appeared before the JSON object
4. The model emitted a trailing comma before `}` or `]`

The parser only removed markdown fences and then searched from the first `{` to the last `}`. It did not:

- safely read content arrays
- preserve diagnostics for non-string assistant content
- return structured debug information on parse failure
- normalize common field aliases such as `items` vs `line_items` or `total` vs `total_amount`

## 6. Recent Change Analysis

Identifiable recent changes relevant to this regression:

1. The AI transport issue forced a model change to `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free`.
2. `process-document` still relied on a parser designed around a strict single-string JSON response contract.

Likely regression cause:

- The new model/provider combination returns a different response shape or more verbose output than the old parser tolerated.
- The parser brittleness was already latent in `process-document`; the model change exposed it.

What is **not** implicated by current evidence:

- Flutter upload path
- Supabase Auth
- Storage signed URL generation
- RLS / tenant isolation
- request validation helpers in `_shared/request.ts`
- rate limiting helpers in `_shared/rate_limit.ts`

## 7. Recommended Fix

Safest fix, in order of necessity:

1. Harden assistant content extraction so `message.content` may be a string or content array.
2. Parse AI output robustly:
   - trim whitespace
   - strip markdown fences
   - extract the first balanced JSON object
   - retry after removing trailing commas
3. Add sanitized parse-failure diagnostics:
   - assistant content type
   - response length
   - sanitized preview
   - finish reason if available
4. Normalize a small alias set before persistence:
   - `items` / `products` -> `line_items`
   - `supplier` -> `supplier_name`
   - `date` -> `document_date`
   - `total` -> `total_amount`
   - `tax` -> `tax_amount`
5. Return a structured parse-failure response to Flutter.
6. Preserve function-side diagnostics in Flutter instead of overwriting them with a generic background error.

Not recommended as the first follow-up fix:

- adding a second-model JSON repair call immediately

Reason:

- no evidence yet that a second LLM repair pass is necessary once the local parser boundary is corrected
- it adds extra cost, latency, and another failure surface
- the smallest safe fix is local parser hardening plus better diagnostics

## 8. Files To Modify

Necessary:

- `supabase/functions/process-document/index.ts`
- `lib/services/extraction_service.dart`
- `lib/services/background_extraction_service.dart`

Why these files:

- `process-document` owns the OpenRouter request, raw assistant response handling, parser, normalization, and document flagging.
- `ExtractionService` currently compresses function failures down to the top-level `error` field and discards structured debug details.
- `BackgroundExtractionService` currently overwrites function-side flagged notes with a generic local exception message.

## 9. Files To Leave Untouched

Explicitly leave untouched:

- dashboard UI
- FAB
- navigation
- product UI
- supplier UI
- auth flow
- RLS policies
- unrelated migrations
- storage upload flow
- tenant scoping rules

## 10. Validation Matrix

Required validation after the fix:

1. normal invoice image
2. normal ticket image
3. delivery note / albaran image
4. rendered PDF -> JPG path
5. previously failed document re-extraction
6. fenced JSON response
7. explanation + JSON response
8. trailing-comma JSON response
9. assistant content array response
10. no-line-item document
11. many-line-item document
12. ensure no URLs, JWTs, or signed URLs leak to logs
13. ensure `company_id` isolation is unchanged

## 11. Rollback Plan

Rollback is straightforward because the recommended fix is local and surgical:

1. revert `process-document/index.ts` parser and diagnostic changes
2. revert Flutter-side diagnostic propagation changes in `ExtractionService` and `BackgroundExtractionService`
3. redeploy `process-document`

This rollback does not require schema changes, storage changes, or UI rollback.