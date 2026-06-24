# Sales Module Architecture Analysis

Date: 2026-06-13

## Scope Guardrails

This analysis covers the Sales module foundation for HospiDash. The implementation must stay separate from the existing document extraction pipeline. It must not modify `process-document`, `recognize-products`, the invoice/document prompt, document upload flow, OpenRouter keys, or existing product matching behavior. Flutter must never call OpenRouter directly. All business data must remain company-scoped with `company_id` and protected by RLS.

## 1. Current Sales Screen Widget Tree

Current route: `AppRoutes.sales` in `lib/core/router/app_router.dart` renders `SalesScreen` from `lib/features/sales/presentation/screens/sales_screen.dart` inside the bottom-nav `ShellRoute`.

Current `SalesScreen` tree:

- `SalesScreen extends ConsumerWidget`
- `AppScaffold`
  - `AppTopBar(eyebrow: 'revenue', title: 'Sales')`
  - `PremiumFAB(label: 'New sale')`
    - currently shows SnackBar: `Sale creation coming soon`
  - `CustomScrollView`
    - filter row: `StatusBadge('Today')`, `StatusBadge('This week')`, `StatusBadge('This month')`
    - `SectionHeader(eyebrow: 'overview', title: 'Revenue')`
    - `AppCard`
      - `FinancialValue(amount: 0, caption: 'gross revenue - this month')`
      - static text: `Connect a POS or import sales to populate this view.`
    - `SliverFillRemaining`
      - `AppEmptyState(icon: point_of_sale, title: 'No sales yet')`
      - message still points to the New sale button.

There is also a detached `SalesTrackerScreen` in `lib/features/sales/presentation/screens/sales_tracker_screen.dart`. It is not routed. It contains a fuller dashboard layout with KPI cards, chart, AI insight banner, category breakdown, top products, and payment split, but its providers query `orders` and `order_items`, not the requested `sales`, `sales_imports`, and `sales_items` model.

## 2. Current Sales Providers and Repositories

Existing sales surfaces are split across two incompatible paths:

1. `lib/data/repositories/sales_repository.dart`
   - Uses `AuthService.currentCompanyId`.
   - Reads old `sales` rows by `sale_date` and `total_amount`.
   - Aggregates current/previous month in Dart after fetching rows.
   - Creates old daily aggregate sales rows using `total_amount`, `cash_amount`, `card_amount`, `other_amount`, and `notes`.
   - It explicitly filters by `company_id`, which is good, but it is not the new MVP structure.

2. `lib/features/sales/data/providers/sales_providers.dart`
   - Uses Riverpod and `companyIdProvider`.
   - `salesDateRangeProvider` supports today, yesterday, this week, this month, custom.
   - KPI/chart/payment providers query `orders`.
   - category/top-product providers query `order_items` joined to `orders`.
   - This is not aligned with the Sales module mission because the app currently has no real POS/VLM sales import flow feeding those `orders` tables.

3. `lib/features/sales/data/models/sales_models.dart`
   - Defines UI data objects such as `SalesDateRange`, `KpiData`, `RevenueDataPoint`, `CategorySales`, `TopProduct`, `PaymentSplit`.
   - Does not define persistent models for `sales_imports`, transaction-level `sales`, `sales_items`, POS connections, or POS sync jobs.

## 3. Current Supabase Sales Tables

Existing migration `supabase/migrations/00001_multi_tenant_schema.sql` creates an old `sales` table:

- `id uuid default uuid_generate_v4()`
- `company_id uuid not null`
- `sale_date date not null default current_date`
- `sale_time time`
- `cash_amount`, `card_amount`, `other_amount`, `total_amount`
- `tax_collected`, `tips_amount`, `discounts_amount`
- `transaction_count`, `covers_count`
- `source check in ('manual', 'pos_import', 'api')`
- `pos_reference`, `notes`, timestamps, `created_by`
- `unique (company_id, sale_date)`

This table is a daily aggregate table. It conflicts with the requested transaction/import model because the new `sales` table needs multiple rows per day, `sales_import_id`, `gross_amount`, `net_amount`, `payment_method`, `channel`, `pos_transaction_id`, and flexible source types. The MVP should migrate the existing table in place, not create a second table named `sales`.

Existing RLS in `supabase/migrations/00002_row_level_security.sql` enables and forces RLS on `sales` and creates company-scoped select/insert/update/delete policies using `get_current_company_id()`, `user_has_role_in_company()`, and `user_is_company_admin()`.

Realtime migration `supabase/migrations/00007_realtime.sql` already publishes `sales` and sets replica identity full. It does not publish `sales_imports` or `pos_sync_jobs` because those tables do not exist yet.

No existing `sales_imports`, `sales_items`, `pos_connections`, or `pos_sync_jobs` tables were found.

## 4. Current Dashboard Revenue Logic

Dashboard revenue is currently derived from the old sales model:

- `lib/features/dashboard/presentation/viewmodels/dashboard_viewmodel.dart`
  - loads `SalesRepository.getSalesSummary()` from `lib/data/repositories/sales_repository.dart`.
  - if daily sales revenue is empty, it temporarily uses the expense daily series as chart data, while keeping revenue totals from sales.

- `lib/features/dashboard/data/repositories/dashboard_grid_repository.dart`
  - tries `sales(id, total_amount)` scoped by `company_id` and `sale_date`.
  - falls back to `orders(total_amount, tax_amount, discount_amount)` if no sales rows exist.

The dashboard assumes the old `sales.total_amount` column. To avoid breaking the dashboard during MVP, the migration should preserve a generated or maintained `total_amount` compatibility column mapped to `gross_amount`, or update the dashboard intentionally in a separate follow-up. For this task, preserve compatibility.

## 5. Current Navigation and FAB Action for Sales

Current navigation:

- Bottom nav item 1 routes to `/sales`.
- `/sales` renders `SalesScreen`.
- nested `/sales/:id` renders `SalesScreen(saleId: id)`, but there is no real sale detail implementation.

Current Sales FAB:

- `PremiumFAB(label: 'New sale', icon: add)`.
- It only shows a SnackBar.

Required MVP navigation additions:

- `/sales/import` outside or inside shell depending on desired full-screen flow.
- `/sales/connect-pos` for POS connection status/provider choice.
- optional future `/sales/manual` for manual entry.

FAB/action strategy:

- Replace the single fake `New sale` FAB action with real entry points in the empty state.
- Keep manual entry documented but not fake if not implemented.
- Primary visible actions: `Connect POS`, `Import sales report`.

## 6. Existing Document VLM Extraction Architecture That Can Be Reused

Existing document pipeline:

- Flutter upload: `DocumentUploadService` in `lib/providers/documents_provider.dart`.
- Storage: private `documents` bucket, company-scoped paths and policies.
- DB row: `documents` row is inserted with `status = processing`.
- Processing: background call to `BackgroundExtractionService.processDocument(...)` and/or `ExtractionService.invokeProcessDocument(...)`.
- Edge Function: `supabase/functions/process-document/index.ts`.
- OpenRouter is called only from Edge Functions.
- Access check: user Supabase client reads the document row and validates RLS access before service-role writes.
- Shared request validation: `supabase/functions/_shared/request.ts`.
- Shared audit events: `supabase/functions/_shared/audit.ts`.
- Shared deterministic money parser: `supabase/functions/_shared/number_normalization.ts` with `parseMoney`, `parseQuantity`, `roundMoney`.
- Rate limiting: `supabase/functions/_shared/rate_limit.ts`.
- Logging/redaction: `supabase/functions/_shared/redact.ts`.

Reusable safely:

- `_shared/number_normalization.ts` for European money parsing.
- `_shared/request.ts` for small request body validation.
- `_shared/audit.ts`, `_shared/rate_limit.ts`, `_shared/redact.ts`.
- The access-check pattern: authenticate with anon client + auth header, validate user access with RLS, then use service role for processing updates.

Must remain separate:

- `process-document/index.ts` prompt and flow.
- `documents` table and document status flow.
- `recognize-products` and product matching.

## 7. Required Database Tables

MVP database should add/verify:

### `sales_imports`

Tracks manual/POS/VLM/CSV import batches.

Required fields: `id`, `company_id`, `source_type`, `source_name`, `file_path`, `status`, `imported_at`, `period_start`, `period_end`, totals, `currency`, `notes`, `extraction_raw`, `extraction_clean`, `created_by`, timestamps.

### `sales`

Should become transaction/report-line level revenue rows. Because an old table exists, migration should add columns rather than drop data:

- add `sales_import_id`, `sale_datetime`, `gross_amount`, `net_amount`, `tax_amount`, `discount_amount`, `tip_amount`, `currency`, `payment_method`, `channel`, `pos_transaction_id`, `source_type`, `metadata`.
- preserve old `total_amount` compatibility for dashboard. Existing rows can be backfilled: `gross_amount = coalesce(total_amount, cash_amount + card_amount + other_amount, 0)`.
- old unique `(company_id, sale_date)` must be dropped if present, because imports can contain many sales rows per day.

### `sales_items`

Stores item-level rows extracted from POS reports, CSVs, or VLM reports. Includes `company_id`, nullable `sale_id`, nullable `sales_import_id`, product name, normalized name, quantity, unit price, total amount, category, POS product ID, optional matched `product_id`, metadata.

### `pos_connections`

Stores provider connection metadata only. Tokens must be encrypted and must never be returned to Flutter. Flutter reads status/provider/last sync metadata only.

### `pos_sync_jobs`

Tracks server-side POS sync runs, period, status, error, completion time.

### Storage

Recommended: create private `sales-imports` bucket with the same company path strategy as documents. If minimizing storage policy churn for MVP, files can be stored under the private `documents` bucket in a `sales-reports` path, but a separate bucket is cleaner and easier to audit.

## 8. Required Edge Functions

MVP:

- `process-sales-import`
  - Authenticates user.
  - Reads a `sales_imports` row by ID through the user client to validate tenant access.
  - Fetches uploaded file securely with service role after access is confirmed.
  - Sends image/PDF page data to OpenRouter VLM.
  - Extracts strict JSON only.
  - Normalizes money and dates server-side.
  - Inserts `sales` and `sales_items` rows with the authorized `company_id` from DB, not from Flutter trust.
  - Updates `sales_imports.status` to `completed`, `flagged`, or `failed`.
  - Creates Review Center rows for failed/low-confidence/missing-period/total mismatch where practical.

Architecture placeholders:

- `connect-pos`
- `sync-pos-sales`
- `disconnect-pos`

For MVP, these can validate auth and table access and return configured/placeholder status without storing unencrypted credentials or pretending a real provider is connected.

## 9. Required Flutter Providers

Use Riverpod and active `companyIdProvider`.

Required providers:

- `salesDateRangeProvider` or reuse existing after alignment.
- `salesSummaryProvider(period)`
  - server-filtered query by `company_id` and date range.
  - sums gross/net/tax/transactions/average ticket from DB rows, not client filtering all rows.
- `salesImportsProvider`
  - latest import batches for active company.
- `posConnectionsProvider`
  - connection status only; no tokens.
- `salesItemsProvider`
  - top/recent items by active period where needed.
- `salesRealtimeProvider`
  - subscribes to `sales_imports`, `sales`, and `pos_sync_jobs` filtered by `company_id`, invalidating summary/import/connection providers.
- `salesImportUploadController` or repository method for selecting/uploading file, creating import row, invoking `process-sales-import`.

If `company_id` is null, providers must not query. They should return empty/safe state, not throw into a noisy UI.

## 10. POS Integration Plan

Define provider abstraction server-side first:

```ts
interface PosProviderAdapter {
  connect(input: ConnectInput): Promise<ConnectResult>;
  refreshToken(connection: PosConnection): Promise<TokenRefreshResult>;
  fetchSales(connection: PosConnection, periodStart: string, periodEnd: string): Promise<RawPosTransaction[]>;
  normalizeTransaction(raw: RawPosTransaction): NormalizedSale;
  disconnect(connection: PosConnection): Promise<void>;
}
```

Connection rules:

- Flutter only triggers Edge Functions and reads connection rows.
- OAuth/token exchange must happen in Edge Functions.
- Tokens are encrypted before storage.
- Tokens are never selected by Flutter-facing queries or returned from functions.
- Start with `custom`/placeholder adapter and a status screen if provider credentials are not available.

Future providers: Square, Lightspeed, Poster, Toast, SumUp, custom CSV/API.

## 11. VLM Sales Import Plan

Flutter flow:

1. User taps `Import sales report`.
2. User selects PDF/image/screenshot.
3. Flutter uploads to private storage under active company path.
4. Flutter creates `sales_imports` row with `status = processing`, `source_type = vlm_import`, `file_path`, `created_by`.
5. Flutter invokes `process-sales-import` with `salesImportId` only.
6. Flutter returns to Sales page immediately.
7. Realtime updates import status and revenue cards.

Edge Function extraction schema:

```json
{
  "report_type": "daily_sales|weekly_sales|monthly_sales|pos_export|unknown",
  "period_start": "YYYY-MM-DD|null",
  "period_end": "YYYY-MM-DD|null",
  "currency": "EUR",
  "gross_revenue": 0,
  "net_revenue": 0,
  "tax_amount": 0,
  "discount_amount": 0,
  "tips_amount": 0,
  "transaction_count": 0,
  "payment_methods": [],
  "channels": [],
  "items": [],
  "raw_text": null
}
```

Prompt rules:

- return only JSON.
- no markdown or explanation.
- use null for unknown values.
- use arrays for missing collections.
- do not invent sales.
- convert European numbers correctly, but still run deterministic server normalization after the model response.

Server normalization:

- `parseMoney` for `gross_revenue`, `net_revenue`, `tax_amount`, discounts, tips, payment method amounts, channel amounts, item gross/net/unit amounts.
- `parseQuantity` for item quantities and transaction counts where needed.
- Guard examples: `808,16 -> 808.16`, `1.506,21 -> 1506.21`, `1,506.21 -> 1506.21`.

## 12. MVP Scope

MVP should include:

1. Migration for `sales_imports`, upgraded `sales`, `sales_items`, `pos_connections`, `pos_sync_jobs`.
2. RLS and realtime for new sales tables.
3. Flutter models for sales imports, sale rows, sales items, POS connections, summary.
4. `SalesRepository` under `lib/features/sales/data/repositories/` for tenant-safe queries and import creation.
5. Riverpod providers under `lib/features/sales/presentation/providers/`.
6. Clean Sales page with real summary query and empty state actions.
7. `ImportSalesScreen` for file selection/upload/invoke.
8. `ConnectPosScreen` for architecture-first provider/status UI.
9. `process-sales-import` Edge Function with OpenRouter VLM, deterministic normalization, DB inserts, import status updates.
10. No mock sales and no fake revenue.

Phase 2 after MVP:

- real POS OAuth providers.
- scheduled POS sync jobs.
- sales intelligence/anomalies/forecasting.
- richer top-selling items and category/channel/payment breakdown.
- manual transaction editor.

## 13. Risks

- Existing `sales` table has a daily uniqueness constraint. It must be dropped for transaction-level rows.
- Existing dashboard uses `sales.total_amount`; compatibility must be preserved or dashboard will break.
- Existing detached SalesTracker queries `orders`; routing it directly would not satisfy MVP because no real import feeds those tables.
- VLM report layouts vary wildly. The Edge Function must flag uncertain/missing-period/total-mismatch cases instead of inventing.
- PDF rendering support inside Edge Functions may require either existing uploaded rendered images or an additional rendering strategy. MVP can support images first and gracefully flag PDFs if rendering is unavailable, but final target should support PDF reports.
- POS token encryption requires an encryption secret and audited server-only access. Do not implement real token storage without encryption.
- RLS policies must not trust Flutter-provided `company_id`; Edge Functions must derive authorized company from selected rows or membership checks.
- Realtime subscriptions must be single and disposable to avoid duplicate invalidations.

## 14. Validation Checklist

1. New company with no sales:
   - Revenue cards show zero real data.
   - Empty state shows `Connect POS` and `Import sales report`.
   - No fake revenue is displayed.
2. Import sales report image:
   - `sales_imports` row is created with `processing`.
   - `process-sales-import` updates status.
   - `sales` and `sales_items` rows are inserted only for the authorized `company_id`.
   - Sales page refreshes through realtime/provider invalidation.
3. Import POS report PDF:
   - Same flow, or explicit flagged status if PDF rendering is not yet supported in the function.
4. Bad/non-sales report:
   - `sales_imports.status` becomes `flagged` or `failed`.
   - No fake `sales` rows are inserted.
5. Money normalization:
   - `808,16` persists as `808.16`.
   - `1.506,21` persists as `1506.21`.
   - `1,506.21` persists as `1506.21`.
6. Tenant isolation:
   - Company A cannot select, import, update, or receive realtime events for Company B sales rows.
7. POS placeholder:
   - Connection screen opens and reads only provider/status metadata.
   - No credentials are exposed to Flutter.
8. Existing document extraction:
   - `process-document` remains untouched.
   - invoice/document upload still invokes the existing pipeline.
9. Analyzer/build:
   - Focused `dart analyze` on touched Flutter sales files passes.
   - Edge Function TypeScript is syntax-checked where local Deno tooling is available.
   - SQL migration is reviewed for RLS, indexes, policies, and compatibility.