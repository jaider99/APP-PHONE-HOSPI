# Sales Dashboard Sync And CRUD Analysis

Date: 2026-06-13

## 1. Current Sales Import Flow

The Sales import flow is:

1. `ImportSalesScreen` reads a selected PDF/CSV/image into bytes.
2. `SalesRepository.createSalesReportImport(...)` uploads the file to Supabase Storage bucket `sales-imports`.
3. Flutter inserts a `sales_imports` row with `status = processing` and the uploaded `file_path`.
4. Flutter invokes `process-sales-import` with `{ "sales_import_id": "..." }`.
5. `process-sales-import` validates the authenticated user through the caller JWT, reads the import row through RLS, derives `company_id` from that row, downloads the storage object with service role, extracts sales with OpenRouter, normalizes the result, deletes prior rows for the same import, inserts `sales` and `sales_items`, and marks `sales_imports.status = completed`.

The current import pipeline is reaching completion and is no longer blocked by the previous function/schema 500.

## 2. What Tables Are Written When Import Completes

For the latest completed import, the function writes:

- `sales_imports`: status, totals, period, currency, `extraction_raw`, `extraction_clean`.
- `sales`: canonical analytics row(s) linked by `sales_import_id`.
- `sales_items`: item/detail rows linked by `sales_import_id` and `sale_id` when visible rows exist in the report.

Live latest completed import id:

```text
c3e2be7b-2ce0-4be3-8d28-07e5c365049d
```

Live company id:

```text
e70aabbf-679d-4270-aaf6-bb8a8c25babe
```

## 3. Whether `sales_imports` Only Is Updated Or `sales` Rows Are Created

The import does not only update `sales_imports`. It also creates a `sales` row.

Latest completed import created this `sales` row:

- `sales_import_id`: `c3e2be7b-2ce0-4be3-8d28-07e5c365049d`
- `gross_amount`: `42564.70`
- `net_amount`: `4256.01`
- `tax_amount`: `46820.71`
- `transaction_count`: `1`
- `source_type`: `vlm_import`
- `sale_date`: `2026-01-06`

The row exists, but its date is wrong for the imported June report.

## 4. Whether `sales_items` Rows Are Created

Yes. The latest completed import created 12 `sales_items` rows.

The live `sales_items` table does not have `gross_amount` or `net_amount` columns. It stores line-level amounts as `total_amount`, plus `quantity`, `unit_price`, `category`, and metadata.

The created item names are the visible daily labels from the screenshot, for example:

- `01/06/26`
- `02/06/26`
- `03/06/26`
- through `12/06/26`

## 5. Which Table The Sales Dashboard Reads From

The current Sales screen reads from `salesSummaryProvider`, which calls `SalesRepository.fetchSummary(...)`.

That repository calls the live RPC:

```text
public.get_sales_summary(p_company_id, p_period_start, p_period_end)
```

The RPC reads `public.sales` and filters by:

```sql
s.company_id = p_company_id
and s.sale_date >= p_period_start
and s.sale_date <= p_period_end
```

It sums:

- `sales.gross_amount`
- `sales.net_amount` with fallback to `gross_amount - tax_amount`
- `sales.tax_amount`

Current RPC counts `COUNT(s.id)` for transactions, not `SUM(s.transaction_count)`. For aggregate imported reports this undercounts real report transaction count if the VLM extracts a transaction count later.

## 6. Which Table The Main Dashboard Reads From

The main dashboard has two revenue-related paths:

1. `DashboardIntelligenceGrid` uses `dashboardGridMetricsProvider` -> `DashboardGridRepository`.
2. The older `DashboardViewModel` uses `lib/data/repositories/sales_repository.dart` for `SaleSummary` state used by other dashboard sections/activity context.

The visible 2x2 dashboard grid reads `public.sales` first:

```dart
.from('sales')
.select('id, total_amount')
.eq('company_id', companyId)
.gte('sale_date', range.start)
.lte('sale_date', range.end)
```

If no `sales` rows are found in the period, it falls back to completed `orders`.

The older dashboard repository also reads `public.sales` for current month and previous month, using `sale_date`.

Neither main dashboard path reads `sales_imports` totals directly.

## 7. Why Revenue Remains 0

Revenue remains 0 because the completed import's canonical `sales` row was saved with the wrong `sale_date`:

```text
raw report period_start: 01/06/26
raw report period_end:   13/06/26
raw transaction date:    13/06/26
normalized period_start: 2026-01-06
normalized period_end:   2026-01-06
sales.sale_date:         2026-01-06
```

The current date is 2026-06-13. The Sales page default filter is `thisMonth`, which queries 2026-06-01 through 2026-06-13. The imported `sales` row is outside that range, so both dashboards correctly return 0 for June.

Live aggregate confirmation:

```text
June 2026 gross: 0
January 2026 gross: 42564.70
```

The exact root cause is `process-sales-import` date parsing. Its `parseDate` function falls through to JavaScript `Date.parse(...)`. JavaScript interprets `01/06/26` as January 6, 2026 under US-style parsing. `13/06/26` cannot be parsed that way, so transaction date falls back to the already-wrong period date.

## 8. Whether The Issue Is Missing `sales` Rows

No. The latest completed import creates a `sales` row.

The issue is not missing canonical sales rows; it is wrong canonical sale dates.

## 9. Whether The Issue Is Wrong Query Table

No for the Sales dashboard. It reads the canonical `sales` table through `get_sales_summary`, which is the correct analytics source.

No for the main dashboard grid. It also reads `sales` first.

There is still cleanup debt in the older dashboard view model, but it also uses `sales`, so it is not the root cause of the zero revenue.

## 10. Whether The Issue Is Wrong Date Filter

The dashboard date filters are conceptually correct because sales analytics should use `sale_date`.

The problem is upstream: `sale_date` is wrong. A June report was normalized to January.

The current Sales page period logic is:

- Today: today only
- This week: Monday through today
- This month: first day of current month through today
- Custom: currently today only in the model

The main dashboard grid uses rolling chart periods from `ChartPeriod`, such as one month = last 30 days.

## 11. Whether The Issue Is Wrong Status Filter

No. The Sales dashboard does not filter by `sales_imports.status`; it sums `sales` rows. The latest import status is exactly `completed`.

The main dashboard grid does not filter `sales_imports.status` either.

## 12. Whether The Issue Is Wrong `company_id`

No. The latest completed import, created sales row, and created sales item rows all share:

```text
company_id = e70aabbf-679d-4270-aaf6-bb8a8c25babe
```

Tenant scoping is not the cause of the zero revenue.

## 13. Whether The Provider Is Not Invalidating

Provider invalidation is not the primary cause.

The Sales providers subscribe to:

- `sales_imports`
- `sales`
- `pos_sync_jobs`
- `pos_connections`

The dashboard grid provider subscribes to:

- `sales`
- `orders`
- documents/review streams through its other providers

When `sales` rows are inserted or updated, providers should refresh. The problem is that refreshed queries still filter June and the imported row is in January.

There is one gap: dashboard intelligence realtime does not subscribe to `sales_items`, but current revenue cards do not use `sales_items`.

## 14. Whether Realtime Is Not Refreshing

Realtime is not the controlling issue for the observed zero revenue. The data remains zero even after refresh because the row date is out of period.

Realtime should still be preserved and extended after CRUD changes so dashboard and Sales page update after edit/delete.

## 15. Whether Sales Import Completed But Totals Not Copied

No. Totals are copied to `sales_imports` and a canonical `sales` row is created with nonzero amounts.

However, totals are copied with the same wrong parsed period:

```text
sales_imports.period_start = 2026-01-06
sales_imports.period_end   = 2026-01-06
sales.sale_date            = 2026-01-06
```

## 16. Whether Main Dashboard Still Reads Old Sales Table/View

The visible main dashboard grid reads `public.sales` directly and does not use an old revenue view.

It falls back to `orders` only when no sales rows exist inside the selected period. Because the misdated import is outside the selected period, the grid treats the current period as having no sales.

## 17. Current Delete/Edit Support

Current UI support is missing:

- Sales import rows display static status rows only.
- POS connection rows display static status rows only.
- No overflow menu or detail screen exists for import actions.
- No edit sale form exists for imported aggregate sales.
- No delete import action exists.
- No delete/disconnect/manage UI exists for POS connections.

Current backend/RLS support:

- `sales`, `sales_imports`, and `sales_items` have tenant-scoped SELECT/INSERT/UPDATE policies.
- DELETE policies exist for admins on `sales`, `sales_imports`, and `sales_items`.
- `pos_connections` deliberately has no direct SELECT policy because token columns must not be exposed. Flutter reads the token-free `pos_connection_status` view.
- `pos_connections` UPDATE/DELETE policies are admin-only.
- `disconnect-pos` exists, but it currently accepts client `companyId`, only checks membership, and does not clear encrypted tokens/credential status.

## 18. Missing CRUD Operations

Missing production operations:

- Update canonical `sales` rows.
- Keep aggregate `sales_imports` totals consistent when editing an imported aggregate sale.
- Delete a sales import and remove/exclude related `sales` and `sales_items` so analytics no longer count it.
- Delete or disconnect POS connections without exposing token columns.
- Edit custom POS display/config fields without returning credentials to Flutter.
- Retry/re-import action for failed or corrected imports.

## 19. RLS Impact

All CRUD must remain tenant-safe.

Safe pattern:

- Flutter uses active `company_id` only as a row filter, never as proof of authorization.
- RLS remains enabled and forced.
- Direct Flutter edits/deletes include both `company_id` and row id.
- POS token-bearing table mutations should go through Edge Functions or RPCs that derive/validate tenant access before service-role writes.
- Do not add direct SELECT access to `pos_connections`.

Because `sales_imports` and `sales_items` have `ON DELETE SET NULL` relationships from `sales`/`sales_items`, deleting only `sales_imports` would orphan analytics rows. Import delete must explicitly update/delete dependent `sales_items` and `sales` before hiding/removing the import.

## 20. Minimal Safe Fix

Minimal production-safe fix:

1. Fix `process-sales-import` date parsing so European report dates like `01/06/26`, `13/06/26`, `01-06-2026`, and `01.06.26` normalize as day/month/year, not US month/day/year.
2. Backfill the current completed import by deriving correct dates from `sales_imports.extraction_raw` and updating `sales_imports.period_start`, `period_end`, `extraction_clean`, `sales.sale_date`, and `sales.sale_datetime` for the affected import rows.
3. Update `get_sales_summary` to use `SUM(transaction_count)` rather than `COUNT(id)` so aggregate imported report rows can represent multiple transactions when available.
4. Keep `sales` as the canonical revenue analytics table. `sales_imports` remains the import/job container. `sales_items` remains line-level detail.
5. Add repository methods for safe sale update, sales import delete, POS disconnect/delete/update custom metadata.
6. Add compact UI actions on Sales import and POS connection rows: Edit, Delete, Disconnect/Manage.
7. Invalidate Sales and Dashboard providers after edit/delete. Existing realtime should handle cross-device refresh.

Deletion strategy for this minimal pass:

- Use explicit tenant-scoped hard deletes for `sales_items` and `sales`, then delete the `sales_imports` row.
- This matches the current schema and existing admin DELETE policies.
- Do not delete storage automatically in the first pass unless separately confirmed and required; leaving the storage object avoids accidental file loss while analytics are corrected.

POS strategy:

- Disconnect via `disconnect-pos`, but harden it to derive company server-side, require admin role, clear encrypted tokens, set `credentials_status = none`, and set `sync_status = disconnected`.
- Delete POS via a new Edge Function or hardened repository method that never returns token columns. Historical sales remain untouched.

## 21. Files To Modify

Required:

- `SALES_DASHBOARD_SYNC_AND_CRUD_ANALYSIS.md`
- `supabase/functions/process-sales-import/index.ts`
- `supabase/functions/disconnect-pos/index.ts`
- `supabase/migrations/20260613_sales_dashboard_sync_and_crud.sql`
- `lib/features/sales/data/repositories/sales_repository.dart`
- `lib/features/sales/data/models/sales_import.dart`
- `lib/features/sales/data/models/pos_connection.dart`
- `lib/features/sales/presentation/screens/sales_screen.dart`
- `lib/features/sales/presentation/providers/sales_providers.dart`
- `lib/features/dashboard/data/repositories/dashboard_grid_repository.dart`
- `lib/features/dashboard/presentation/providers/dashboard_grid_provider.dart`
- `PROJECT_CONTEXT.md`

Possible if routing/detail screens are needed:

- `lib/core/router/app_router.dart`
- new `lib/features/sales/presentation/screens/sales_import_detail_screen.dart`

## 22. Files To Leave Untouched

Do not touch:

- `supabase/functions/process-document/index.ts`
- document extraction
- document upload
- product matching
- supplier intelligence
- document storage policies unless sales import storage deletion becomes explicitly required
- auth flows
- unrelated RLS policies
- OpenRouter document VLM prompts/parsing
- Products and Documents feature UI

## 23. Validation Checklist

Data validation:

- Latest completed import has `sales_imports.status = completed`.
- Latest completed import has `sales` row(s) with nonzero `gross_amount`, `net_amount`, `tax_amount`.
- Latest completed import has `sales.sale_date = 2026-06-13` or another correct June report date, not `2026-01-06`.
- `sales_items` rows remain linked to the correct `sales_import_id` and `sale_id`.

Sales dashboard validation:

- `This month` shows imported gross revenue.
- `Today` shows imported revenue only when the sale date is today.
- `This week` shows imported revenue when the sale date is inside this week.
- Transaction count uses `sales.transaction_count` for aggregate imported rows.

Main dashboard validation:

- Dashboard Sales tile reads the same canonical `sales` data.
- Dashboard Results tile updates from sales minus expenses.
- Realtime/provider invalidation updates without app restart.

CRUD validation:

- Edit gross/net/tax/transaction count/date/notes for imported sale.
- Sales dashboard updates after edit.
- Main dashboard updates after edit.
- Delete sales import removes/excludes linked `sales` and `sales_items` from analytics.
- Delete/import action is scoped by both row id and `company_id`.
- POS disconnect changes status and clears token fields without exposing credentials.
- POS delete removes the connection/status row while preserving historical sales.
- Company A cannot edit/delete Company B sales/import/POS rows.

Security validation:

- RLS remains enabled and forced.
- Flutter never uses service-role keys.
- POS token columns are not selected by Flutter.
- Edge Functions authenticate the user and derive/validate tenant access before service-role writes.

Regression validation:

- `deno check supabase/functions/process-sales-import/index.ts`
- `deno check supabase/functions/disconnect-pos/index.ts`
- focused `flutter analyze` on touched Sales/Dashboard files
- `npx supabase functions deploy process-sales-import`
- deploy any changed POS Edge Functions
- VLM document extraction remains untouched and unaffected