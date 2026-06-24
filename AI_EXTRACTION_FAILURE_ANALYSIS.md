# AI_EXTRACTION_FAILURE_ANALYSIS

## 1. Executive Summary

OpenRouter is healthy. The Nemotron VLM is being called and is generating output. The pipeline fails after inference because the model is hitting the response token cap before it can emit a complete JSON object, so `JSON.parse` fails downstream and the document is flagged.

The smoking-gun evidence comes directly from the OpenRouter dashboard:

- model: `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free`
- output: 2000 tokens
- finish_reason: `length` on most calls

`finish_reason = length` means the response was truncated by `max_tokens`. The current Edge Function sets `max_tokens: 2000`, but the prompt asks the model to return the full OCR text plus every line item inside one JSON object. For invoices and delivery notes with many items the JSON is cut mid-output and ends with `...` instead of a closing brace.

The previously deployed parser hardening helped with formatting issues but cannot recover from a JSON object that does not exist yet because the model never finished writing it.

## 2. Pipeline Map

```
Flutter (DocumentUploadService)
  ↓
Storage upload (StorageService.uploadDocument)
  ↓
documents row insert (status = 'processing')
  ↓
BackgroundExtractionService.processDocument
  ↓ (PDF render → image upload if needed)
  ↓
ExtractionService.invokeProcessDocument
  ↓
Supabase Edge Function process-document
  ↓ (auth, RLS check, image fetch, base64)
  ↓
OpenRouter chat completions (Nemotron VLM)
  ↓ (returns assistant content)
  ↓
parseExtraction (JSON parser)
  ↓
normalizeExtraction
  ↓
documents UPDATE (status='completed') + document_items insert
  ↓
Flutter caller resumes, recognize-products fired async
```

The failure is specifically between the model response and `parseExtraction`.

## 3. Failure Point

File: `supabase/functions/process-document/index.ts`

Two contributing settings:

1. `max_tokens: 2000` on the OpenRouter request.
2. The extraction prompt asks for `raw_text: "full OCR text from the document or null"` in addition to all `line_items`.

Combined effect: a normal restaurant invoice with 15–40 lines easily exceeds 2000 output tokens once `raw_text` is included, so the JSON object is cut.

Secondary issue: there is no explicit fetch timeout on the main OpenRouter call. If the provider stalls, the Edge Function can ride up against the Supabase function idle timeout (~150s) before failing.

## 4. Evidence

From the OpenRouter dashboard (user-supplied screenshot):

- 7 of 7 visible Nemotron generations completed
- 6 of 7 finished with `finish_reason = length`
- output token counts pinned at 2000 in the truncated runs
- only the run with very small input (~124 output tokens) finished with `stop`

From Flutter logs:

- `process-document failed status=500 ... details=Could not parse extraction JSON`

From code:

- `max_tokens: 2000` in `process-document/index.ts`
- prompt instructs the model to return `raw_text: "full OCR text from the document"`
- no `AbortController` timeout on the main OpenRouter fetch

## 5. Root Cause

The model is not failing. The Edge Function is asking for too much output inside a too-small token budget:

1. `raw_text` duplicates content that is already implicit in the line items.
2. `max_tokens: 2000` is below the realistic response size for hospitality invoices when `raw_text` is included.
3. There is no instruction telling the model to prioritize closing the JSON over emitting more line items if the budget gets tight.
4. There is no client-side timeout on the OpenRouter fetch, so a slow provider compounds the symptom.

## 6. Recommended Fix (minimal and safe)

Apply only inside `supabase/functions/process-document/index.ts`. No DB schema changes, no Flutter changes, no auth/RLS changes.

1. Raise the response budget:
   - `max_tokens: 6000`
2. Trim the prompt schema:
   - keep `raw_text` but require it to be a short header excerpt (≤ 200 chars) or `null` so it stops eating the entire output budget
   - reorder the schema so metadata and totals come first and `line_items` last
   - add an explicit rule: if the model is running low on space, prefer returning fewer `line_items` over emitting invalid/truncated JSON
3. Add an AbortController on the main OpenRouter fetch (e.g. 90s) so the function fails fast and surfaces a clean error instead of hanging toward the 150s Supabase idle timeout.
4. When `finish_reason === "length"` and parsing fails, return a structured `length_truncated` debug payload so the cause is obvious in Flutter logs.

This keeps existing downstream behaviour intact:

- `extraction_clean.raw_text` still exists (just shorter or null)
- `_finalizeDocumentType` and `resolveDocumentType` both already tolerate empty `raw_text`
- `recognize-products` is still fire-and-forget from the Flutter service
- tenant isolation, storage paths, dashboard, FAB, products UI, and supplier UI are untouched

Out of scope for this fix:

- changing the model
- moving OpenRouter to Flutter
- rewriting the extraction system
- adding a "continue the JSON" repair pass — not justified yet; first prove that with a 6000-token budget and a leaner schema, `finish_reason` becomes `stop` for normal documents

## 7. Validation Matrix

After deploying the fix, verify:

1. Single photo invoice → `completed`, `finish_reason=stop`
2. Long delivery note (≥ 30 lines) → `completed` (or `completed` with line items truncated cleanly), `finish_reason=stop`
3. Multi-page PDF → `completed`
4. Bad image → `flagged` with a clear note
5. Slow OpenRouter response → fails within ~90s, not 150s; doc flagged with timeout note
6. OpenRouter dashboard `finish_reason` should mostly be `stop` after the change

## 8. Rollback Plan

Revert `process-document/index.ts` to the previous commit and redeploy. No schema or storage rollbacks needed.
