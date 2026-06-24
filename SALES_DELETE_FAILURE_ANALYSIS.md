# Sales Delete Failure Analysis

Date: 2026-06-14

## 1. Current Delete Sale UI Flow

The active Sales screen is `lib/features/sales/presentation/screens/sales_screen.dart`.

There are two destructive Sales data paths:

- Sales import row menu -> `Delete import` -> `_deleteSalesImport(...)`
- Import management sheet -> imported sale row menu -> `Delete` -> `_deleteSale(...)`

There are also POS management paths in the same screen:

- POS row menu -> `Disconnect` -> `_disconnectPosConnection(...)`
- POS row menu -> `Delete connection` -> `_deletePosConnection(...)`

The specific sale delete path is:

1. `_ImportedSaleRow` renders a `PopupMenuButton<_SaleAction>`.
2. Selecting `_SaleAction.delete` calls `_deleteSale(context, ref, sale, salesImportId)`.
3. `_deleteSale` asks for destructive confirmation.
4. If confirmed, `_deleteSale` awaits `StepUpAuthService.requireStepUp(action: StepUpAction.deleteSalesData, required: false)`.
5. If that call returns normally, `_deleteSale` calls `SalesRepository.deleteSale(companyId: sale.companyId, saleId: sale.id)`.
6. Repository invokes Supabase RPC `delete_sales_record` with `p_company_id` and `p_sale_id`.
7. On success, `invalidateSalesSurfaces(ref, salesImportId: salesImportId)` invalidates Sales and dashboard providers.
8. UI shows `Sales record deleted`.

## 2. Current Confirmation Dialog Flow

The delete handlers call `_confirmDestructiveAction(...)`, which uses the shared `showAppSheet<bool>` helper.

For sale delete:

- Title: `Delete sales record?`
- Message: `This removes this sales record from revenue analytics.`
- Action label default: `Delete`

If the user cancels confirmation or the context is no longer mounted, the function returns before step-up and before any repository call.

## 3. Current StepUpAuthService Result Handling

`StepUpAuthService.requireStepUp(...)` currently returns `Future<void>` and throws only for blocking auth outcomes.

Observed log:

```text
[StepUpAuthService] Step-up skipped (local auth unavailable, not required) for delete_sales_data
```

This comes from `LocalAuthResult.skipped`. Because Sales delete passes `required: false`, skipped local auth is treated as an allowed optional gate and `requireStepUp` returns normally.

Therefore this log is not a delete failure. If the deletion does not complete, the failure is after `requireStepUp` returns.

Current semantics:

- `LocalAuthResult.success` -> continue
- `LocalAuthResult.skipped` with `required: false` -> continue
- `LocalAuthResult.cancelled`, `failed`, `unavailable`, `notConfigured`, `error` when required -> throw `StepUpAuthException`

The current call site does not use a bad `if (!stepUpResult.success) return;` pattern. It awaits a void method and continues unless an exception is thrown.

## 4. Current Repository Delete Method

`SalesRepository.deleteSale(...)` calls:

```dart
await _supabase.rpc(
  'delete_sales_record',
  params: {
    'p_company_id': companyId,
    'p_sale_id': saleId,
  },
);
```

The method includes `companyId` and does not delete by id alone.

`SalesRepository.deleteSalesImport(...)` calls:

```dart
await _supabase.rpc(
  'delete_sales_import',
  params: {
    'p_company_id': companyId,
    'p_sales_import_id': salesImportId,
  },
);
```

The repository currently has no structured logging around these RPC stages and lets raw `PostgrestException` details bubble to the Sales screen catch blocks.

## 5. Current Supabase Tables Affected

Sale delete affects:

- `public.sales_items`
- `public.sales`
- `public.sales_imports` totals through `recalculate_sales_import_totals(...)` when the deleted sale belongs to an import

Import delete affects:

- `public.sales_items`
- `public.sales`
- `public.sales_imports`

Dashboard reads affected data from:

- Sales screen: `get_sales_summary(...)`, `sales_imports`, `sales`, `sales_items`
- Main dashboard grid: direct reads from `sales`

## 6. Whether Deletion Is Hard Delete Or Soft Delete

Sales tables currently use hard delete.

Live schema check found no `deleted_at` column on:

- `sales`
- `sales_items`
- `sales_imports`

The existing Sales CRUD migration uses hard delete functions and child-row cleanup. Do not introduce mixed soft-delete semantics in this fix.

## 7. Whether Imported Sales And Manual Sales Use Different Paths

The current active UI path mainly exposes imported report sales through `importedSalesProvider(import.id)` and `_ImportedSaleRow`.

`delete_sales_record(...)` is generic for any row in `sales`, but the UI path passes a `Sale` model from `fetchImportedSales(...)`, which filters by `sales_import_id`.

Manual sales rows can still be represented by `source_type = 'manual'`, but the currently inspected UI does not expose a separate manual sale list/delete path outside the imported-sale management sheet.

## 8. Whether Related Sales Items Exist

`process-sales-import` inserts item rows with both:

- `sale_id: inserted.id`
- `sales_import_id: salesImportId`

So imported sale rows can have linked `sales_items` by `sale_id`.

The live production data at investigation time contained:

- `sales_count = 0`
- `sales_items_count = 0`
- three remaining failed `sales_imports` rows

That means the live database no longer has a current sale row to delete; the remaining visible Sales entries may be import rows rather than sale rows.

## 9. Whether Sales Imports Relations Block Delete

`sales.sales_import_id -> sales_imports.id` is `ON DELETE SET NULL`.

`sales_items.sales_import_id -> sales_imports.id` is `ON DELETE SET NULL`.

`sales_items.sale_id -> sales.id` is `ON DELETE SET NULL`.

The RPC avoids FK ambiguity by deleting children first:

1. `sales_items`
2. `sales`
3. `sales_imports` for full import delete only

A rollback-only live test of `delete_sales_import(...)` as the live owner user succeeded and removed the import row inside the transaction, then rolled back.

## 10. Whether RLS Allows Delete

Table RLS is enabled and forced on `sales_imports` and `sales_items`; base Sales RLS is also enabled/forced.

Direct table delete policies require admin/owner semantics:

- `sales`: `Admins can delete sales`
- `sales_imports`: `Admins can delete sales imports`
- `sales_items`: `Admins can delete sales items`

The RPCs are `SECURITY DEFINER`, but they still explicitly require:

```sql
public.user_is_company_admin(p_company_id)
```

So a non-owner/non-admin cannot delete sales data through the RPC. This is a correct security boundary and should not be weakened. The UI currently does not pre-hide destructive actions by role, so a non-admin would see the action and then receive an RPC permission failure.

## 11. Whether Dashboard Queries Exclude Deleted Rows

There is no Sales soft delete today, so dashboard queries cannot filter `deleted_at` for Sales tables.

Sales dashboard summary uses `get_sales_summary(...)`, which reads hard-deleted `sales` rows only.

Main dashboard grid reads `sales` rows directly by `company_id` and `sale_date` range. Once a sale row is hard-deleted, it will not be counted.

Provider invalidation after sale/import delete calls:

- `salesSummaryProvider`
- `salesImportsProvider`
- `salesItemsProvider`
- `posConnectionsProvider`
- `dashboardGridMetricsProvider`
- `importedSalesProvider(salesImportId)` when applicable

Realtime also listens to `sales`, `sales_imports`, and `sales_items` changes.

## 12. Exact Root Cause

The step-up log is not the root cause. `LocalAuthResult.skipped` with `required: false` returns normally and the delete flow continues.

The confirmed failure risk after step-up is weak post-step-up handling:

1. The repository delete methods do not log delete stages or map Postgres/RPC errors.
2. The UI catch blocks display raw `$error` strings for sale/import/POS delete failures.
3. If the RPC denies the action (for example, non-admin user), cannot find the row, or encounters a network/PostgREST failure, the app surfaces a raw failure and gives no clear indication of which stage failed.
4. The live database currently has no `sales` rows left, only failed `sales_imports`, so a user may be trying to delete an import row while reading the step-up skip log as a sale-delete error.

Validated non-root-causes:

- Step-up skipped-not-required is already allowed to proceed.
- The repository does include `company_id` in delete RPC params.
- Live `delete_sales_import(...)` succeeds for the owner inside a rollback transaction.
- Live schema has no soft-delete mismatch for Sales tables.

## 13. Minimal Safe Fix

Keep the existing server-side delete model and tenant isolation.

Implement the narrow Flutter-side fix:

1. Add a small Sales delete exception mapper in the repository.
2. Wrap `deleteSale`, `deleteSalesImport`, and `deletePosConnection` RPC calls with stage-specific safe logging.
3. Map `PostgrestException` codes/messages to user-safe exceptions:
   - `42501` -> permission message
   - `P0002` -> not found message
   - FK-like codes (`23503`) -> linked records message
   - network/unknown -> generic safe retry message
4. Update Sales screen delete catch blocks to show the safe exception message, not raw Supabase errors.
5. Keep `requireStepUp(required: false)` for Sales/POS destructive actions.
6. Keep provider invalidation after successful deletes.

Do not change RLS, do not use service role in Flutter, and do not rewrite the Sales module.

## 14. Files To Modify

Expected minimal files:

- `lib/features/sales/data/repositories/sales_repository.dart`
- `lib/features/sales/presentation/screens/sales_screen.dart`

Optional if documenting after validation:

- `PROJECT_CONTEXT.md`

## 15. Files To Leave Untouched

Do not touch:

- `supabase/functions/process-document/**`
- `supabase/functions/process-sales-import/**` unless cleanup evidence changes
- OpenRouter or VLM extraction code
- document upload/extraction code
- product matching
- storage policies
- unrelated RLS
- bottom navigation
- dashboard UI design

## 16. Validation Checklist

Required focused checks:

1. `flutter analyze lib/features/sales/data/repositories/sales_repository.dart lib/features/sales/presentation/screens/sales_screen.dart`
2. Confirm `Step-up skipped ... delete_sales_data` is followed by repository delete logging, not treated as cancellation.
3. Delete failed sales import as owner/admin; row disappears and Sales imports provider refreshes.
4. Delete imported sale as owner/admin; linked `sales_items` are removed and import totals recalculate.
5. Attempt delete as non-admin; user sees `You do not have permission to delete this sale.` and no data is removed.
6. Confirm Sales summary updates after delete.
7. Confirm main dashboard grid updates after delete.
8. Confirm no raw `PostgrestException`, SQL, or Supabase internals appear in SnackBars.
9. Confirm VLM sales import still creates `sales`, `sales_items`, and `sales_imports` rows.
10. Confirm document extraction remains untouched.
