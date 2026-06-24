# VLM_REASONING_TOKEN_FAILURE_ANALYSIS

Date: 2026-06-02

## 1. Executive Summary

`process-document` is currently calling a **reasoning** variant of the NVIDIA Nemotron VLM. Reasoning tokens count as output tokens. On every call, ~4000 of the response budget is burned on hidden chain-of-thought *before* the model emits any visible JSON, so the JSON is truncated and `JSON.parse` fails downstream.

Raising `max_tokens` cannot fix this — every additional token gets consumed by reasoning, not by output.

The minimum safe fix is to:

1. Switch back to the non-reasoning VLM the project was using before this regression (`nvidia/nemotron-nano-12b-v2-vl:free`).
2. Defensively pass OpenRouter `reasoning: { exclude: true, effort: "minimal" }` and `include_reasoning: false` so reasoning is suppressed even if the model is later swapped back to a thinking variant.
3. Drop `max_tokens` back to a tight budget (2500) — appropriate for a non-reasoning model.
4. Strip the few "Your FIRST task is to classify…" / "NEVER guess randomly" lines from the prompt that nudge the model toward step-by-step thinking.

## 2. Current Model

```
const MODEL = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free";
const TEXT_CLASSIFIER_MODEL = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free";
```

Both are reasoning models. The previous (working) model documented in `PROCESS_DOCUMENT_FAILURE_ANALYSIS.md` was `nvidia/nemotron-nano-12b-v2-vl:free`, a non-reasoning vision model.

## 3. Current OpenRouter Request

```ts
{
  model: "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free",
  messages: [{ role: "user", content: [...image_url, text] }],
  max_tokens: 6000,            // raised in v34 from 2000
  temperature: 0.05,
}
```

No `reasoning` parameter. No `include_reasoning` flag. No `response_format`. No `provider` block. Streamed by the Supabase Edge Runtime client.

## 4. Smoking-Gun Evidence

Latest OpenRouter generation log:

```
generation_id:           gen-1780398454-zSCThRdH9txgaUzH6iOK
model:                   nvidia/nemotron-3-nano-omni-30b-a3b-reasoning
native_tokens_prompt:    1295
native_tokens_completion:6000
native_tokens_reasoning: 4082    <-- chain-of-thought
tokens_completion:       4082
finish_reason:           length
native_finish_reason:    length
provider_status:         200
```

The model finished a healthy generation (provider returned 200) but spent 4082 of 6000 output tokens on reasoning, leaving 1918 for the visible JSON, which was not enough to close the schema. Flutter then sees `code=json_parse_failed`.

## 5. Why Increasing max_tokens Alone Will Not Fix It

Reasoning effort scales with the budget. OpenRouter's docs are explicit: when `reasoning.effort` is not specified, models default to roughly the "medium" tier, which allocates approximately 50% of `max_tokens` to reasoning. Raising `max_tokens` simply raises the reasoning budget proportionally. We will keep seeing `finish_reason=length` as long as a reasoning model is in use without explicit reasoning controls.

## 6. OpenRouter Reasoning Controls (from current docs)

OpenRouter exposes a unified `reasoning` parameter:

```jsonc
{
  "reasoning": {
    "effort": "minimal",   // ~10% of max_tokens; "none" fully disables (model-dependent)
    "exclude": true        // do not return reasoning text in the response
  },
  "include_reasoning": false  // legacy alias for reasoning.exclude=true
}
```

`reasoning.effort: "none"` is documented as supported on OpenAI o-series and Grok, not universally — for Nemotron we cannot rely on it. `effort: "minimal"` plus `exclude: true` is the safest combination across providers: it strongly biases the provider toward little or no reasoning and keeps reasoning out of the response payload regardless.

## 7. Why a Non-Reasoning VLM Is the Right Default for OCR

Document extraction is a **structured-output** task, not a reasoning task. The model must:

- look at pixels,
- emit a closed JSON envelope,
- do basic Spain hospitality classification.

A reasoning model will burn budget enumerating possibilities ("Is this an albarán? Let me check VAT… let me re-examine the header…"). A non-reasoning VLM will OCR and emit. The prior working configuration in this repo (`nvidia/nemotron-nano-12b-v2-vl:free`, `max_tokens: 2000`) confirms that hypothesis empirically.

## 8. Minimum Safe Fix (in `supabase/functions/process-document/index.ts` only)

1. `MODEL` and `TEXT_CLASSIFIER_MODEL` → `nvidia/nemotron-nano-12b-v2-vl:free`.
2. `OPENROUTER_MAX_TOKENS = 2500` (down from 6000; matches the non-reasoning regime).
3. Add to the OpenRouter request body:

   ```ts
   reasoning: { exclude: true, effort: "minimal" },
   include_reasoning: false,
   ```

   Defense in depth: if anyone later swaps `MODEL` back to a reasoning variant, the budget is no longer burned silently.
4. Tighten the prompt: remove "Your FIRST task is to classify the document type with high accuracy" and "NEVER guess randomly" lines that subtly push the model into deliberation. Replace with extraction-only instructions.

Out of scope of this fix:

- Edge Function architecture, auth, RLS, storage paths.
- Flutter caller, upload flow, multi-image flow, PDF rendering.
- DB schema.
- Downstream pipelines (product recognition, suppliers, categories, price intelligence).
- `recognize-products` / async follow-ups.

## 9. Rollback Plan

Revert `supabase/functions/process-document/index.ts` to the previous commit and redeploy. Storage, DB and Flutter are untouched.

## 10. Validation Matrix

After deploy, verify in OpenRouter dashboard for the next 5 extractions:

1. `model` = `nvidia/nemotron-nano-12b-v2-vl`.
2. `native_tokens_reasoning` = 0 (or absent).
3. `finish_reason` = `stop`.
4. `tokens_completion` < 2500 for normal documents.

In Flutter:

1. Single image invoice → `completed`.
2. Albarán photo → `document_type=delivery_note`, `completed`.
3. Restaurant ticket → `completed`.
4. PDF (1–3 pages, via the multi-page fix already in place) → `completed`.
5. Long invoice (≥ 30 lines) → `completed` (the model may emit fewer line items but JSON closes).

## 11. Risk Assessment

| Change | Risk | Mitigation |
|---|---|---|
| Revert model | Low — it is the variant that historically worked | Keep `reasoning` params even on non-reasoning model (provider ignores them) |
| Add `reasoning`/`include_reasoning` | Low — OpenRouter normalizes; non-reasoning models ignore | None required |
| Lower `max_tokens` to 2500 | Low — matches prior working budget | If a real document needs more, parser still flags with `length_truncated` |
| Trim "FIRST task" prompt language | Low — classification rules retained | None required |

## 12. Expected OpenRouter Log After Fix

```
model:                   nvidia/nemotron-nano-12b-v2-vl
native_tokens_completion:~600–1500 (typical)
native_tokens_reasoning: 0
finish_reason:           stop
```
