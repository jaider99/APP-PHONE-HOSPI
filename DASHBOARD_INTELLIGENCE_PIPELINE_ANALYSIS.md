# Dashboard Intelligence Pipeline Analysis

Date: 2026-06-03

Scope: Restore the existing Dashboard Intelligence cards (`Spend by Category`, `Top Products`) without rebuilding UI, mocking data, or changing upload/extraction/auth/storage/navigation.

## Executive Summary

The dashboard intelligence UI is still connected to Riverpod providers. The empty cards are not static UI regressions.

The break is at the analytics boundary:

1. The existing dashboard intelligence cards read `v_category_intelligence` and `v_top_products_by_spend` through `IntelligenceService`.
2. Those views hard-code calendar-month windows using `date_trunc('month', CURRENT_DATE)`.
3. The working dashboard expense totals use `chartPeriodProvider`, whose default `ChartPeriod.oneMonth` means rolling last 30 days.
4. On 2026-06-03, valid May 2026 invoice/product rows can still appear in the working expense total, but are zero for the view's current calendar month.
5. `v_category_intelligence` is additionally coupled to `documents.category_id`, while the real product intelligence chain is `document_items -> products -> categories` and `product_prices`.
6. Dashboard intelligence providers do not watch product/product_price/document_item realtime changes, so extraction/product recognition can finish after `documents` updates without refreshing these cards.

Smallest safe fix applied: keep the existing UI, keep tenant-scoped Supabase reads, and update only the dashboard intelligence data layer/providers so they query the same rolling dashboard period and subscribe to the product intelligence tables.

## Pipeline Map

| Step | File responsible | Table / source | Expected data | Actual data observed in code | Status |
| --- | --- | --- | --- | --- | --- |
| Document upload | `lib/providers/documents_provider.dart` | `documents`, `expenses` | Insert processing document with `company_id`, optional user category, file metadata; create expense row when available | `submitExpenseFlow()` inserts `documents` with `company_id`, status `processing`, file fields, currency, and optional `category_id`; creates `expenses` row with optional `category_id`; tenant-scoped | WORKING |
| OpenRouter VLM extraction | `supabase/functions/process-document/index.ts` | OpenRouter VLM response | Extract supplier, document type, date, totals, line items | Function normalizes JSON, resolves document type, updates `documents`, deletes/reinserts `document_items` | WORKING |
| Supabase Edge Function persistence | `supabase/functions/process-document/index.ts` | `documents`, `document_items` | Completed document row plus line items with quantities/prices/totals | `documents` updated with status `completed`, `document_date`, `total_amount`, `tax_amount`, `extraction_clean`; `document_items` inserted with `company_id`, `document_id`, description, quantity, unit, unit_price, line_total | WORKING |
| Product recognition | `supabase/functions/recognize-products/index.ts` | `document_items`, `products`, `product_aliases`, `product_prices` | Match/create products, link line items, update price history | Fetches tenant document via RLS, derives `company_id`; reads `document_items`; matches aliases/candidates/products; creates products; updates `document_items.product_id`; upserts `product_prices` by `document_item_id` | WORKING |
| Product category assignment | `supabase/functions/recognize-products/index.ts` | `products.category_id`, `documents.category_id` | Product receives category from AI/user/supplier default/review path | New products are created with `category_id: documentRow.category_id`; existing products with null category are enriched from `documentRow.category_id`; no product-category fallback if document category is null | PARTIAL |
| Supplier connection | `supabase/functions/recognize-products/index.ts`, supplier resolution migrations | `documents.provider_id`, `document_items.supplier_id`, `product_prices.supplier_id` | Product price observations keep supplier context | Recognizer writes `document_items.supplier_id` and `product_prices.supplier_id` from `documents.provider_id`; if provider resolution has not completed, supplier remains null | PARTIAL |
| Category analytics | `supabase/migrations/20260517_intelligence_analytics.sql`, `lib/services/intelligence_service.dart` | `v_category_intelligence` | Spend by category for same dashboard period, tenant-scoped, preferably via product/category line-item chain | View aggregates `documents.total_amount` by `documents.category_id` and hard-coded calendar current month; Flutter filters `currentMonthSpent > 0`; ignores `product_prices -> products.category_id` | BROKEN |
| Product analytics | `supabase/migrations/20260517_intelligence_analytics.sql`, `lib/services/intelligence_service.dart` | `v_top_products_by_spend` | Top products for same dashboard period, tenant-scoped | View aggregates `product_prices`; Flutter filters `.gt('current_month_spent', 0)`, where current month is calendar month from DB view, not selected dashboard period | BROKEN |
| Flutter providers | `lib/features/dashboard/providers/intelligence_providers.dart` | `companyIdProvider`, `IntelligenceService` | Watch company, dashboard period, and realtime dependencies | Providers watch only `companyIdProvider`; they do not watch `chartPeriodProvider` or product/product_price/document_item realtime | BROKEN |
| Dashboard widgets | `lib/features/dashboard/presentation/widgets/intelligence_section.dart` | `categoryIntelligenceProvider`, `topProductsDashboardProvider` | Render provider data/empty/loading/error states | `_CategoryBreakdownCard` and `_TopProductsCard` are `ConsumerWidget`s and call `ref.watch(...)`; UI is not static | WORKING |

## Database Relationship Findings

### Documents

Defined in `supabase/migrations/00001_multi_tenant_schema.sql` and extended later.

Important fields:

- `id`
- `company_id`
- `provider_id`
- `document_type`
- `document_date`
- `subtotal`
- `tax_amount`
- `total_amount`
- `status` added/used by later app code
- `category_id`, `ai_category_id`, `category_confidence` added by category learning migrations
- `expense_id` added by expenses migration
- `deleted_at`, duplicate/merge fields added by later migrations

Status: WORKING for expense totals because dashboard grid and chart read completed tenant documents by `document_date`.

### Document Items

Base table: `document_items`.

Important fields:

- `id`
- `document_id`
- `company_id`
- `product_id`
- `description`
- `quantity`
- `unit_price`
- `line_total`
- `matched_automatically`
- `confidence_score`
- `normalized_description`
- `supplier_id`

`process-document` inserts text/price/quantity rows. `recognize-products` later links `product_id`, `normalized_description`, match confidence, and supplier.

Status: WORKING/PARTIAL. Rows are created, but downstream analytics depend on product recognition and product price rows being generated after extraction.

### Products

Base table: `products`, extended with:

- `image_url`
- `category_id`
- `normalized_name`

`recognize-products` creates or matches products and updates product snapshots (`unit_price`, `currency`, `unit_type`). New products only get `category_id` when the parent document already has `category_id`.

Status: WORKING/PARTIAL. Product rows are created, but category assignment is only as good as `documents.category_id` at recognition time.

### Product Prices / Price History

Table: `product_prices`.

Important fields:

- `company_id`
- `product_id`
- `document_id`
- `document_item_id`
- `supplier_id`
- `price`
- `quantity`
- `unit`
- `date`
- `observed_at`

`recognize-products` upserts by `document_item_id`, sets `date` to `documents.document_date`, and uses `observed_at` fallback only for observation time.

Status: WORKING/PARTIAL. Top-products analytics are possible from this table, but the current dashboard provider filters through a calendar-month view instead of the selected rolling period.

### Categories

Table: `categories`.

Used by:

- `documents.category_id`
- `expenses.category_id`
- `products.category_id`

Status: WORKING/PARTIAL. Categories exist and are tenant-scoped. The dashboard category view currently uses `documents.category_id`, while product-level category intelligence should use `products.category_id` through line-item/price observations when available.

### Suppliers

Table: `providers`; supplier aliases/resolution exist separately.

Used by:

- `documents.provider_id`
- `document_items.supplier_id`
- `product_prices.supplier_id`

Status: WORKING/PARTIAL. Product price supplier context is written when `documents.provider_id` is available.

### Expenses

Table: `expenses`.

The expense form writes category/user metadata before upload and `_syncExpenseAfterExtraction()` syncs extraction results later. The already-fixed expenses screen reads `expenses.category_id` first and `documents.category_id` as fallback.

Status: WORKING for expense tracker/category summary logic outside the dashboard intelligence cards.

## Multitenancy Safety Check

| Query area | Current company filter | Server-side isolation | Status |
| --- | --- | --- | --- |
| `IntelligenceService.fetchCategoryIntelligence` | `.eq('company_id', companyId)` | View uses `security_invoker = true`; base tables have RLS | WORKING |
| `IntelligenceService.fetchTopProducts` | `.eq('company_id', companyId)` | View uses `security_invoker = true`; base tables have RLS | WORKING |
| Dashboard grid expenses | `.eq('company_id', companyId)` on `documents` | Documents RLS | WORKING |
| Expense chart | `.eq('company_id', companyId)` on `documents` | Documents RLS | WORKING |
| Product catalogue | `.eq('company_id', companyId)` on `products` | Products RLS | WORKING |
| Product realtime | `PostgresChangeFilter company_id = active company` | Realtime publication/RLS posture depends on deployed policies | WORKING |

Required fix must preserve explicit `.eq('company_id', companyId)` on every Supabase query. No client-side cross-tenant filtering is acceptable.

## Spend By Category Debugging

Current provider path:

```text
IntelligenceSection
  -> categoryIntelligenceProvider
  -> IntelligenceService.fetchCategoryIntelligence(companyId)
  -> v_category_intelligence
```

Current SQL source:

```text
categories c
LEFT JOIN documents d
  ON d.category_id = c.id
 AND d.company_id = c.company_id
 AND d.status = 'completed'
 AND d.document_date >= date_trunc('month', CURRENT_DATE)
```

Findings:

1. It reads from `documents`, not `expenses` and not product line-item spend.
2. It expects `documents.category_id` to be present.
3. It ignores `products.category_id` and `product_prices` line-item spend.
4. It uses calendar current month, while the dashboard chart/grid use rolling `ChartPeriod`.
5. The UI filters out all categories where `currentMonthSpent == 0`, so prior-month or last-30-days data disappears.

Status: BROKEN relative to the desired chain `line item -> product -> category -> dashboard`.

Recommended behavior:

- Query by active dashboard `ChartPeriod` using `document_date`/`product_prices.date`.
- Prefer product-category spend from `product_prices -> products.category_id` when products have categories.
- Preserve a document/expense category fallback for documents not yet productized.
- If a product/document has no category, do not silently classify it as a real category; keep it out of categorized spend and let Review Center surface missing category work.

## Top Products Debugging

Current provider path:

```text
IntelligenceSection
  -> topProductsDashboardProvider
  -> IntelligenceService.fetchTopProducts(companyId, limit: 8)
  -> v_top_products_by_spend
```

Current SQL source:

```text
products p
JOIN product_prices pp
  ON pp.product_id = p.id
 AND pp.company_id = p.company_id
```

Findings:

1. This is the right core table chain for product spend.
2. The Flutter query filters `.gt('current_month_spent', 0)`.
3. `current_month_spent` is computed inside the SQL view using calendar month, not the selected dashboard `ChartPeriod`.
4. If uploaded/extracted invoice dates are in the last 30 days but not the current calendar month, the top products card is empty while expense totals still work.
5. Product recognition writes `product_prices` after document extraction, but the dashboard intelligence provider does not watch product/product_price/document_item realtime changes.

Status: BROKEN at date-window alignment and realtime refresh.

## UI Provider Connection Check

`lib/features/dashboard/presentation/widgets/intelligence_section.dart` is still correctly provider-connected:

- `_CategoryBreakdownCard extends ConsumerWidget`
- calls `ref.watch(categoryIntelligenceProvider)`
- `_TopProductsCard extends ConsumerWidget`
- calls `ref.watch(topProductsDashboardProvider)`

No static empty text replacement was found. The UI does not need to be rebuilt.

## Date Filter Findings

The dashboard has two different time semantics:

| Area | Current date logic | Effect |
| --- | --- | --- |
| Expense chart/grid | `ChartPeriod.oneMonth` = last 30 days | May 2026 documents can appear on 2026-06-03 |
| Intelligence SQL views | calendar month via `date_trunc('month', CURRENT_DATE)` | May 2026 documents disappear on 2026-06-03 |

Business recommendation: dashboard intelligence should use the same selected dashboard period as the expense chart/grid and bucket by document date, not upload date. Product analytics should use `product_prices.date`, which is already set from `documents.document_date` by the recognition function.

## Root Cause Hypothesis

The dashboard intelligence cards are empty because their providers read calendar-month analytics views and do not observe product-intelligence realtime tables, while the rest of the dashboard uses rolling `ChartPeriod` document-date windows. Spend by Category is additionally disconnected from the product/category chain because it reads `documents.category_id` instead of product line-item categories.

Cheap disconfirming checks:

1. Query `v_top_products_by_spend` for the active company and inspect rows with `total_spent > 0` but `current_month_spent = 0`.
2. Query `product_prices` for the active company where `date` is within the last 30 days but before the current calendar month.
3. Query completed documents with `total_amount > 0`, `document_date` in the last 30 days, and `category_id IS NULL` while related `document_items.product_id` points to products with `category_id`.

## Minimal Safe Fix Plan

1. Keep `IntelligenceSection` UI unchanged.
2. Update `IntelligenceService` to support period-scoped category and top-product queries from base tables.
3. Keep every query explicitly tenant-scoped with `.eq('company_id', companyId)`.
4. Use the same `ChartPeriod` date-range semantics as `ExpenseChartRepository` and `DashboardGridRepository`.
5. Use `product_prices.date` for product-period analytics because it is derived from `documents.document_date`.
6. For category spend, aggregate productized line-item spend through `product_prices -> products.category_id -> categories`, with a document-category fallback only for categorized completed documents that do not yet have productized line-item prices.
7. Add a dashboard intelligence realtime provider that watches `documents`, `document_items`, `products`, `product_prices`, and `categories` for the active `company_id`.
8. Make `categoryIntelligenceProvider` and `topProductsDashboardProvider` watch both `chartPeriodProvider` and the new realtime provider.

Out of scope for this fix:

- OpenRouter prompts
- Upload flow
- Storage
- Auth
- Navigation/FAB
- UI redesign
- Mock data or seed data

## Applied Fix

Files changed:

- `lib/services/intelligence_service.dart`
- `lib/features/dashboard/providers/intelligence_providers.dart`

Changes:

1. `IntelligenceService.fetchCategoryIntelligence()` now accepts a `ChartPeriod` and uses the same rolling date-range semantics as the working expense chart/grid.
2. Category spend now aggregates productized line-item spend from `product_prices -> products.category_id -> categories`.
3. Categorized completed documents are used only as a fallback when that document has no productized product-price rows for the same period, preventing double counting.
4. `IntelligenceService.fetchTopProducts()` now accepts a `ChartPeriod` and ranks products by period-scoped `product_prices` spend instead of the SQL view's hard-coded calendar current month.
5. Product-price intelligence rows are restricted to active products and completed, non-duplicate, non-deleted source documents.
6. All new reads remain explicitly scoped with `.eq('company_id', companyId)`.
7. `dashboardIntelligenceRealtimeProvider` now listens to tenant-filtered changes on `documents`, `document_items`, `products`, `product_prices`, and `categories`.
8. `categoryIntelligenceProvider` and `topProductsDashboardProvider` now watch `chartPeriodProvider` and `dashboardIntelligenceRealtimeProvider`, so extraction/product-recognition completion can refresh the dashboard cards without an app restart.

Validation completed:

```bash
flutter analyze --no-fatal-infos lib/services/intelligence_service.dart lib/features/dashboard/providers/intelligence_providers.dart
```

Result: no issues found.

Runtime validation still required with real tenant data:

1. Upload or use an invoice whose `document_date` falls inside the selected dashboard period but outside the calendar month boundary.
2. Confirm expense chart/grid totals, Spend by Category, and Top Products all agree on the period.
3. Confirm a productized Drinks item such as Campari appears in Top Products and contributes to Drinks category spend when `products.category_id` is set.
4. Confirm uncategorized products/documents remain reviewable instead of being silently treated as categorized spend.
5. Switch company and confirm no dashboard intelligence data leaks across tenants.
