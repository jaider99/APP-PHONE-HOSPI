# Intelligence Pipeline Root Cause Analysis

## Scope

Investigate why Dashboard Intelligence, Top Products, and Top Providers are empty even though document extraction is now producing completed documents, line items, products, categories, and providers.

This analysis does not change OpenRouter/VLM extraction, PDF extraction/rendering, product matching semantics, UI design, auth, storage, or RLS.

## Live Database Evidence

Tenant under investigation: `e70aabbf-679d-4270-aaf6-bb8a8c25babe`.

### Documents are present and linked

Recent completed documents include provider/category links and valid totals:

- Latest `document (24).pdf`: `id=01bbf598-2c25-400b-ba5a-7bd2603333a3`, `status=completed`, `provider_id=7c967c7d-61d5-4bce-a443-61dbc62f808e`, `category_id=53dfaaa3-3cea-47a4-a050-0ee09eaa5cc9`, `document_date=2026-05-29`, `total_amount=808.16`.
- Other completed documents exist in the same tenant with May 2026 `document_date` values.

### Providers are present

Recent provider rows exist for the tenant, including:

- `IL BOCCONCINO DISTRIBUCION ALIMENTARIA SL` (`7c967c7d-61d5-4bce-a443-61dbc62f808e`)
- `Escolà Vins i destil·lats` (`e8c28022-e764-4497-aa64-93a570121a1c`)
- `La Ribera, S.A.` (`93061b1b-028e-4681-91e6-0df772d72160`)

### Document items are present and product-linked

Recent `document_items` for the latest completed `document (24).pdf` have populated `product_id`, quantities, unit prices, and line totals. Example rows include:

- `BERENJENAS A LA PARILLA...`: `product_id=8dac3592-2537-4097-b8a9-6d43f6256a7b`, `quantity=1.000`, `unit_price=27.2800`, `line_total=23.19`
- `MORTADELLA BOLLO ORO...`: `product_id=5b8ebc53-923f-401b-981c-3125c0f69125`, `quantity=5.280`, `unit_price=9.7000`, `line_total=40.97`
- `RADISE PROSECCO DOC EXTRA DRY...`: `product_id=ca262085-d046-4e5c-816b-ecebf9ae9c53`, `quantity=6.000`, `unit_price=34.2000`, `line_total=143.64`

This proves the recognizer runs far enough to match/create products and update `document_items.product_id`.

### Products are present and categorized

Recent `products` rows exist and have category IDs. For example:

- `Radise Prosecco Doc Extra Dry...`: `category_id=63975ea7-02cf-4185-a8e2-4fa23a5df432`
- `Mortadella Bollo Oro...`: `category_id=63975ea7-02cf-4185-a8e2-4fa23a5df432`
- `Stracciatella Di Burrata...`: `category_id=53dfaaa3-3cea-47a4-a050-0ee09eaa5cc9`

### Categories are present

Tenant categories are active, including `Raw Materials` (`63975ea7-02cf-4185-a8e2-4fa23a5df432`) and `Drinks` (`53dfaaa3-3cea-47a4-a050-0ee09eaa5cc9`).

### Product price observations are missing

`SELECT ... FROM public.product_prices ORDER BY created_at DESC LIMIT 40` returned an empty result.

This is the primary broken link for Top Products and productized category intelligence. The dashboard service reads product spend from `product_prices`; with no price rows, Top Products has no source data even though `document_items.product_id` is populated.

## Code Path Evidence

### Dashboard Intelligence

`lib/services/intelligence_service.dart` reads:

- category spend from `product_prices`, then falls back to categorized `documents` only for documents that do not have productized price rows.
- top products from `product_prices` only.

Therefore:

- Missing `product_prices` directly explains empty Top Products.
- Missing `product_prices` should not fully prevent Spend by Category because there is a categorized-document fallback, but only for rows inside the selected period.

### Top Providers

`lib/data/repositories/providers_repository.dart` reads provider spend from `documents`, but filters by the current calendar month:

- `document_date >= startOfMonth`
- `document_date <= endOfMonth`

The newest successful documents were uploaded in June but dated May. Live comparison:

- current calendar month by `document_date`: `0` rows, `0` amount
- last 30 days by `document_date`: `5` rows, `3484.37` amount
- created this month: `7` rows, `3802.09` amount

This explains the Top Providers empty state when the dashboard is in June and recent invoices are dated May.

### Product Recognition

`supabase/functions/recognize-products/index.ts` does the following sequence:

1. Fetches `document_items`.
2. Matches or creates `products`.
3. Updates `document_items.product_id`.
4. Attempts to upsert a `product_prices` row using `onConflict: "document_item_id"`.

Live state proves steps 1-3 are succeeding and step 4 is not creating rows.

## Probable Root Cause

The recognizer uses Supabase upsert with `onConflict: "document_item_id"`, but the live database only has a partial unique index:

`CREATE UNIQUE INDEX idx_product_prices_document_item_unique ON public.product_prices USING btree (document_item_id) WHERE (document_item_id IS NOT NULL)`

The live constraints on `product_prices` do not include a full unique constraint for `document_item_id`; only the primary key and foreign keys are constraints.

Postgres `ON CONFLICT (document_item_id)` requires a matching unique/exclusion arbiter. A partial unique index with a predicate is not a match for a plain conflict target emitted by Supabase upsert. The expected failure is a logged `product_prices insert failed` while the function continues and returns success, leaving `document_items.product_id` populated but `product_prices` empty.

## Secondary Root Cause

Top Providers is not connected to the same rolling dashboard period model used by other dashboard intelligence providers. It is hard-coded to the current calendar month, so May-dated documents disappear from the June dashboard despite being in the last 30 days.

The empty message says "No provider data yet", but the database has provider data. The actual condition is "no provider spend in the current calendar month by document_date".

## Minimal Fix Plan

1. Fix `product_prices` persistence without changing extraction or matching:
   - Add a non-partial unique constraint or non-partial unique index on `product_prices(document_item_id)` so the existing recognizer upsert has a valid conflict target.
   - Backfill `product_prices` from existing linked `document_items` joined to completed `documents`, scoped by tenant columns and excluding rows already present.

2. Align Top Providers with the dashboard period:
   - Change provider spend filtering from current calendar month to the same rolling period semantics as `ChartPeriod.oneMonth` or pass the selected chart period into the provider repository.
   - Keep company scoping and existing completed/non-deleted/non-duplicate filters.

3. Validate:
   - Run a rolled-back SQL probe or migration validation proving `ON CONFLICT (document_item_id)` works.
   - Query `product_prices` count and recent rows after backfill.
   - Query dashboard-equivalent top products and provider spend.
   - Run Dart analysis for touched Flutter files and Deno check for untouched/related Edge Function if changed.

## Out Of Scope

- OpenRouter model changes.
- PDF extraction or rendering changes.
- Product matching algorithm changes.
- RLS policy weakening.
- UI redesign.
