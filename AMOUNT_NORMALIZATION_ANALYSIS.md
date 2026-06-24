# Amount Normalization Analysis

Date: 2026-06-08

## 1. Current amount extraction flow

Current money pipeline for document extraction:

1. Flutter uploads the source file and creates a `documents` row with `status = processing`.
2. Flutter invokes `supabase/functions/process-document` through `lib/services/extraction_service.dart` with only `documentId`.
3. `supabase/functions/process-document/index.ts` resolves image sources, calls OpenRouter VLM, and receives structured extraction JSON.
4. `process-document` normalizes the returned extraction through `normalizeExtraction(...)`.
5. Normalized values are written to:
   - `documents.subtotal`
   - `documents.tax_amount`
   - `documents.total_amount`
   - `documents.extraction_clean`
   - `document_items.quantity`
   - `document_items.unit_price`
   - `document_items.line_total`
6. Flutter reads the saved values through `DocumentModel.fromJson(...)` and displays them in document cards, document detail, extracted products, dashboards, supplier intelligence, price history, and anomaly logic.

## 2. Where VLM returns monetary values

OpenRouter VLM is prompted in `supabase/functions/process-document/index.ts` to return JSON with numeric fields:

- document-level:
  - `subtotal`
  - `tax_rate`
  - `tax_amount`
  - `total_amount`
- line-item level:
  - `quantity`
  - `unit_price`
  - `line_total`

The prompt currently asks for JSON numbers but does not explicitly force correct European decimal interpretation strongly enough.

For the affected live row `de79af0c-df1b-4296-b4c9-fb06efb7ee79` (`document (24).pdf`), the saved `extraction_raw` preview already contains inflated numeric values such as:

- `"total_amount": 80816`
- `"tax_amount": 16215`
- `"subtotal": 42338`
- `"quantity": 1000` for visible `1,000`
- `"quantity": 6828` for visible `6,828`
- `"line_total": 34170` for visible `34,1700` / nearby visible European monetary values

This proves the model response itself is already numerically wrong for comma-decimal values in this document.

## 3. Where values are parsed into numbers

Primary parsing happens in `supabase/functions/process-document/index.ts`:

- `normalizeExtraction(...)`
- `parseNullableNumber(...)`

Current parsing behavior in `parseNullableNumber(...)`:

- if value is a number: return it unchanged
- if value is a string:
  - strip currency symbols and spaces
  - if comma and dot both exist:
    - assume last separator decides locale
  - if comma only:
    - if comma has `<= 2` digits after it, treat comma as decimal
    - otherwise remove commas entirely

This logic is unsafe for hospitality invoice data because:

- quantity values like `1,000`, `6,828`, `5,240`, `2,155` are interpreted as integers `1000`, `6828`, `5240`, `2155`
- money values with comma and more than 2 decimals or ambiguous patterns are vulnerable to being treated as thousands separators
- if OpenRouter already emits the wrong numeric literal, `parseNullableNumber(number)` preserves the damage unchanged

## 4. Where totals/tax/line prices are saved to Supabase

In `supabase/functions/process-document/index.ts`:

- document final update writes:
  - `subtotal: cleanExtraction.subtotal`
  - `tax_amount: cleanExtraction.tax_amount`
  - `total_amount: cleanExtraction.total_amount`
  - `extraction_clean: cleanExtraction`
- line item insert writes:
  - `quantity: item.quantity`
  - `unit_price: item.unit_price`
  - `line_total: item.line_total`

Therefore any wrong normalization at the Edge Function layer becomes canonical database state and propagates into downstream product, dashboard, supplier, and anomaly systems.

## 5. Where Flutter formats amounts for display

Flutter does not re-parse these amounts from localized strings in the normal display path. It mostly formats numeric values already read from Supabase.

Relevant readers/formatters:

- `lib/models/document_model.dart`
  - `DocumentModel.fromJson(...)` reads `total_amount` and `tax_amount` as numeric DB fields or numeric `extraction_clean` fallbacks.
  - `DocumentLineItem.fromJson(...)` reads `quantity`, `unit_price`, and `line_total` as numeric DB fields.
- `lib/features/documents/presentation/widgets/document_card.dart`
  - `_formatAmount(...)` uses `NumberFormat.currency(...)` with default locale and the currency symbol.
- `lib/features/documents/presentation/widgets/document_detail_sheet.dart`
  - header `_formatAmount(...)` uses `NumberFormat.currency(...)`
  - metadata rows use `toStringAsFixed(2)` and raw currency code prefix
- `lib/features/documents/presentation/widgets/extracted_products_card.dart`
  - `_formatCurrency(...)` uses `NumberFormat.currency(locale: 'es_ES', ...)`

This means Flutter will display wrong money if the database stores wrong money. The card/header formatter also uses the default locale instead of Spanish/European locale, so a stored `80816` becomes `€80,816.00` rather than a European-style display.

## 6. Why `808,16` becomes `80,816.00`

The failure chain for the affected PDF is:

1. The source invoice uses European decimal commas.
2. OpenRouter returned already-inflated numeric literals in `extraction_raw` for the affected document.
3. `normalizeExtraction(...)` preserved those values because they were already numbers.
4. `process-document` wrote those inflated values into `documents.total_amount`, `documents.tax_amount`, and `document_items` numeric columns.
5. Flutter read `80816.00` from Supabase.
6. `document_card.dart` / `document_detail_sheet.dart` formatted `80816.00` with default `NumberFormat.currency(...)`, producing `€80,816.00`.

So the visible symptom is a combination of:

- upstream extraction/normalization corruption
- default-locale Flutter formatting of an already-wrong stored number

## 7. Whether the bug is in each possible layer

### VLM output

Yes, for the affected PDF the raw model output is already wrong.

Evidence from `documents.extraction_raw` preview for `de79af0c-df1b-4296-b4c9-fb06efb7ee79`:

- `"total_amount": 80816`
- `"quantity": 6828`
- `"line_total": 34170`

This is not only a display bug.

### Edge Function parser

Yes, partially.

`parseNullableNumber(...)` is too weak and ambiguous for European invoice data. It also preserves already-wrong numeric literals from the model instead of applying deterministic, field-aware normalization.

### Normalization helper

Yes.

There is no shared deterministic `parseMoney(...)` / `parseQuantity(...)` split. Money and quantity are handled by the same generic helper, which is unsafe for values like:

- `808,16`
- `34,1700`
- `6,828`
- `1,000`

### Supabase numeric insert

No independent bug found in Postgres numeric storage.

The DB is storing exactly what the Edge Function sends.

### Dart model parsing

No root-cause bug found in the main display path.

`DocumentModel.fromJson(...)` and `DocumentLineItem.fromJson(...)` simply convert already-stored numeric fields to `double`.

### Flutter currency formatter

Not the root cause, but a secondary display issue exists.

`document_card.dart` and the main amount formatter in `document_detail_sheet.dart` use `NumberFormat.currency(...)` without a specific locale, so values are shown in default US-style grouping/decimal format. This does not create the inflation, but it makes bad stored data render as `€80,816.00` instead of a Spanish/European format.

## 8. Most logical fix

Canonical fix must be server-side in `supabase/functions/process-document/index.ts` before DB write.

Recommended fix:

1. Add shared deterministic helpers in the Edge Function layer:
   - `parseMoney(value: unknown): number | null`
   - `parseQuantity(value: unknown): number | null`
   - `roundMoney(value: number | null): number | null`
2. Update `normalizeExtraction(...)` to apply field-aware parsing:
   - document totals/tax/subtotal via `parseMoney(...)`
   - `unit_price` and `line_total` via `parseMoney(...)`
   - `quantity` via `parseQuantity(...)`
3. Add consistency checks after line-item normalization:
   - if `quantity * unit_price` is close to `line_total`, accept
   - if money is clearly inflated by decimal-separator loss and the raw source string indicates comma decimals, correct deterministically
4. Strengthen the VLM prompt so the model is less likely to emit wrong numbers in the first place, but do not rely on prompt alone.
5. Optionally align document display formatters to `es_ES` / European formatting once the DB values are correct, but only as a presentation cleanup, not as the core fix.

## 9. Files to modify

Primary expected files:

- `supabase/functions/process-document/index.ts`

Likely additions inside the same file or extracted helper:

- shared number parsing helpers near normalization logic
- parser tests or a local test script for the new money parser

Possible minor Flutter follow-up if DB values become correct but display style should be European:

- `lib/features/documents/presentation/widgets/document_card.dart`
- `lib/features/documents/presentation/widgets/document_detail_sheet.dart`

## 10. Files to leave untouched

Do not modify:

- OpenRouter model selection
- PDF rendering/upload flow
- Supabase RLS policies
- storage policies/bucket visibility
- product matching logic
- supplier resolution logic
- Flutter layout/design/styling beyond any strictly necessary formatter locale cleanup
- dashboard/product/supplier business logic unrelated to numeric normalization

## 11. Validation plan

### Static/code validation

1. Add deterministic parser tests covering:
   - `parseMoney("808,16€") === 808.16`
   - `parseMoney("729,17") === 729.17`
   - `parseMoney("1.506,21") === 1506.21`
   - `parseMoney("1,506.21") === 1506.21`
   - `parseMoney("34,1700") === 34.17`
   - `parseMoney("29,04") === 29.04`
   - `parseMoney("14,16") === 14.16`
   - `parseMoney("80,27") === 80.27`
   - `parseMoney("40,97") === 40.97`
   - `parseMoney("1 506,21") === 1506.21`
   - `parseMoney("€808,16") === 808.16`
2. Add quantity tests covering:
   - `parseQuantity("6,828") === 6.828`
   - `parseQuantity("1,000") === 1`
   - `parseQuantity("16,000") === 16`
   - `parseQuantity("5,240") === 5.24`
   - `parseQuantity("2,155") === 2.155`
3. Run `deno check supabase/functions/process-document/index.ts`.

### Live DB validation

1. Re-query the affected document after re-extraction.
2. Confirm `documents.total_amount = 808.16` and not `80816.00`.
3. Confirm `documents.tax_amount` and `subtotal` are similarly corrected.
4. Confirm `document_items.quantity`, `unit_price`, and `line_total` reflect European decimal meaning rather than comma stripping.

### Runtime validation

1. Re-extract `document (24).pdf`.
2. Check document detail header and metadata.
   - Expected total: `808.16` or `808,16 €` depending formatter locale.
   - Never `80,816.00`.
3. Check extracted products card values.
4. Check dashboard spend contribution.
5. Check supplier intelligence totals.
6. Check product price history and anomaly behavior.
7. Verify single-image invoice extraction still works.
8. Verify US-style values still parse correctly when present.

### Repair approach

Do not run global repair.

Safer path:

1. Re-extract affected documents first.
2. Only consider a scoped repair script later if:
   - `company_id` is enforced
   - raw extraction evidence shows comma-decimal input
   - stored money is exactly inflated by separator loss
   - changes are auditable

## Current root-cause conclusion

The primary bug is upstream and canonical:

- OpenRouter returned incorrect numeric literals for European comma-decimal values in the affected PDF.
- `process-document` lacks a deterministic, field-aware money/quantity normalization layer strong enough to prevent bad numeric values from becoming database truth.
- Flutter is mainly displaying the already-wrong stored numbers, with a secondary locale-formatting inconsistency in some document views.

## 12. Implemented fix

Implemented changes:

- Added `supabase/functions/_shared/number_normalization.ts` with:
  - `parseMoney(value: unknown): number | null`
  - `parseQuantity(value: unknown): number | null`
  - `roundMoney(value: number | null): number | null`
- Added `supabase/functions/_shared/number_normalization_test.ts` covering the requested money and quantity examples.
- Updated `supabase/functions/process-document/index.ts` to:
  - use `parseMoney(...)` for document totals, tax, subtotal, unit prices, and line totals
  - use `parseQuantity(...)` for quantities
  - derive quantity hints from line-item descriptions like `U: 6,828`
  - rescale obviously inflated money values against line-item and document anchors before DB write
  - derive/correct tax from `total - subtotal` when the parsed tax is clearly implausible
  - strengthen the extraction prompt with explicit European decimal rules without changing the model

## 13. Validation completed

Code validation completed:

- `deno test supabase/functions/_shared/number_normalization_test.ts` passed
- `deno check supabase/functions/process-document/index.ts` passed
- `process-document` was deployed successfully to project `qbvfeizmcuctmhrxkvbx`

## 14. Validation still required

Runtime validation still requires re-extracting the affected document through the authenticated app flow because the bad values are already stored in the existing row.

Required next runtime step:

1. Re-extract `document (24).pdf`.
2. Re-query the `documents` and `document_items` rows.
3. Confirm the saved totals and line-item values are corrected.

This analysis does not include a mass repair script. Historical data repair should remain tenant-scoped and opt-in only.

## 15. Follow-up finding after first deploy

After the first parser deployment and a new re-extraction of `document (24).pdf`, line items were corrected but document-level totals were still wrong in a different way.

Observed live state for the newest row:

- `document_items.line_total` sum = `729.17`
- `documents.subtotal = 808.16`
- `documents.tax_amount = 169.71`
- `documents.total_amount = 977.87`

The invoice image shows:

- base sum `729,17`
- tax sum `78,99`
- final total `808,16`

Root cause of this second-stage mismatch:

- The updated parser correctly fixed line-item quantities and line totals.
- The model still returned wrong document-level summary fields for this invoice in `extraction_raw`:
  - `subtotal = 808.16`
  - `tax_amount = 169.71`
  - `total_amount = 977.87`
- Because those summary numbers were already dot-decimal numbers, the first parser fix did not rescale them.

Implemented follow-up fix:

- Added invoice-level reconciliation in `process-document`:
  - for invoices with multiple line items, treat the corrected line-item sum as the base anchor
  - when raw model totals are inconsistent, choose the smallest plausible total above the base
  - derive/correct tax as `total - subtotal` when model tax is implausible

Expected result after the next re-extraction of `document (24).pdf`:

- `subtotal = 729.17`
- `tax_amount = 78.99`
- `total_amount = 808.16`
