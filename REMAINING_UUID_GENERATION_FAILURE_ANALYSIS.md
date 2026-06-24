# Remaining UUID Generation Failure Analysis

Date: 2026-06-06

## Scope

This analysis covers the persistent extraction finalization error after the first UUID-default migration:

```text
Extraction error: Failed to finalize document extraction: function uuid_generate_v4() does not exist
```

The goal is to locate the remaining live database source of `uuid_generate_v4()` without touching OpenRouter, PDF rendering, Flutter UI, storage security, RLS, or the document page model.

## 1. Exact Current Error

The current user-visible error is still:

```text
Extraction error: Failed to finalize document extraction: function uuid_generate_v4() does not exist
```

The screenshot shows extracted products are visible while the document note contains the UUID error. That means extraction and item persistence are succeeding, but a later database finalization side-effect fails.

## 2. Why VLM Extraction Is Proven Working

The app shows extracted products for the affected PDF documents.

Those product rows can only appear after:

1. PDF page images are resolved.
2. OpenRouter VLM returns structured line items.
3. `process-document` normalizes the extraction result.
4. The app reads saved `document_items` for the document.

Therefore, this failure is not an OpenRouter model/prompt issue and not a PDF page-rendering issue.

## 3. Why `document_items` / Product Extraction Are Proven Working

Live database inspection found multiple current `document (23).pdf` and `document (24).pdf` rows with nonzero `document_items` counts even when the parent document is flagged with the UUID error.

Examples from live DB:

| File | Document ID | status | ocr_status | item_count | matched_item_count | notes |
|---|---|---|---|---:|---:|---|
| document (23).pdf | `fa17b100-02b1-4513-98e1-2fd1208bb704` | flagged | failed | 7 | 0 | UUID finalization error |
| document (23).pdf | `5f57c81e-509e-4d2e-a207-2fa7c7813e76` | flagged | failed | 8 | 0 | UUID finalization error |
| document (24).pdf | `2ed552f6-d24f-4848-90e3-45235021f2ed` | flagged | failed | 15 | 0 | UUID finalization error |

So `document_items` insertion succeeds. The failure is later, during parent document completion and its triggers.

## 4. Exact Operation That Still Fails

A rollback reproduction against the live database isolated the failure:

```sql
BEGIN;

UPDATE public.documents
SET
  status = 'completed',
  ocr_status = 'completed',
  extraction_clean = jsonb_build_object(
    'supplier_name', 'UUID Probe Supplier 20260606',
    'document_type', 'delivery_note',
    'line_items', '[]'::jsonb
  ),
  notes = null,
  updated_at = now()
WHERE id = 'fa17b100-02b1-4513-98e1-2fd1208bb704'
RETURNING id;

ROLLBACK;
```

It failed with:

```text
ERROR: function uuid_generate_v4() does not exist
QUERY: SELECT id FROM providers
WHERE company_id = NEW.company_id
AND name_normalized = NEW.name_normalized
AND id != COALESCE(NEW.id, uuid_generate_v4())
AND is_active = TRUE
CONTEXT:
PL/pgSQL function prevent_duplicate_provider() line 6 at SQL statement
SQL statement "INSERT INTO providers (company_id, name, tax_id) ... RETURNING id"
PL/pgSQL function resolve_supplier(uuid,text,text) line 67 at SQL statement
PL/pgSQL function auto_resolve_supplier_trigger_fn() line 26 at assignment
```

This proves the actual failing operation is not the `activity_logs` default anymore. It is supplier/provider resolution during final document completion.

## 5. Every Remaining `uuid_generate_v4` Reference Found

### Live DB Defaults Still Using `uuid_generate_v4()`

After the first UUID migration, live defaults still using `uuid_generate_v4()` are:

| Schema | Table | Column | Default |
|---|---|---|---|
| public | categories | id | `uuid_generate_v4()` |
| public | companies | id | `uuid_generate_v4()` |
| public | company_users | id | `uuid_generate_v4()` |
| public | expenses | id | `uuid_generate_v4()` |
| public | order_items | id | `uuid_generate_v4()` |
| public | orders | id | `uuid_generate_v4()` |
| public | providers | id | `uuid_generate_v4()` |
| public | sales | id | `uuid_generate_v4()` |
| public | supplier_aliases | id | `uuid_generate_v4()` |

High-risk extraction side-effect tables in that list:

- `providers`
- `supplier_aliases`

`resolve_supplier()` can insert into both while completing a document.

### Live DB Functions Still Using `uuid_generate_v4()`

Live function search found:

| Schema | Function | Finding |
|---|---|---|
| extensions | `uuid_generate_v4()` | Extension function itself. |
| public | `prevent_duplicate_provider()` | Calls unqualified `uuid_generate_v4()` inside provider duplicate checks. |

The application-owned remaining function call is `public.prevent_duplicate_provider()`.

### Repository References

Repository search found historical `uuid_generate_v4()` usage in early migrations, especially:

- `supabase/migrations/00001_multi_tenant_schema.sql`
- `supabase/migrations/00006_provider_deduplication.sql`
- `supabase/migrations/20260422_expenses_and_categories.sql`
- `supabase/migrations/20260424_product_recognition.sql`
- `supabase/migrations/20260505_supplier_intelligence.sql`

The current runtime failure is not fixed by editing old migrations. It requires a new forward migration against the live database.

## 6. Which Trigger/RPC/Default Actually Fires During Extraction

The actual firing chain is:

1. `process-document` finishes OpenRouter extraction and inserts `document_items`.
2. `process-document` runs final `documents.update(...)` to set `status = completed`.
3. `documents` `BEFORE UPDATE` trigger `auto_resolve_supplier` fires.
4. Trigger function `public.auto_resolve_supplier_trigger_fn()` runs with `SET search_path TO public`.
5. It extracts `supplier_name` from `NEW.extraction_clean`.
6. It calls `public.resolve_supplier(company_id, supplier_name, tax_id)`.
7. `resolve_supplier()` runs with `SET search_path TO public`.
8. If no supplier match exists, it inserts into `providers`.
9. The `providers` insert fires `public.prevent_duplicate_provider()`.
10. `prevent_duplicate_provider()` calls unqualified `uuid_generate_v4()`.
11. Because the function is running inside a restricted search-path chain where `extensions` is not visible, `uuid_generate_v4()` fails.

Additionally, once `prevent_duplicate_provider()` is fixed, the same path can still rely on defaults for:

- `providers.id`
- `supplier_aliases.id`

Those defaults also still use unqualified `uuid_generate_v4()` and should be changed to `gen_random_uuid()` for this extraction path.

## 7. Why The Previous Migration Did Not Fully Fix It

The previous migration fixed the first identified extraction-involved defaults:

- `activity_logs.id`
- `documents.id`
- `document_items.id`
- `products.id`

That removed the likely `activity_logs` failure. However, document completion also triggers supplier resolution. Supplier resolution touches `providers` and `supplier_aliases`, which were not included in the first narrow migration.

The previous analysis also found `prevent_duplicate_provider()` but classified it as outside the observed activity-log path. The new rollback reproduction proves it is in the active extraction finalization path whenever a completed document has a supplier name that resolves or creates a provider.

## 8. Safest Fix

Apply one narrow forward migration that fixes only the proven supplier-resolution UUID path:

1. Ensure `pgcrypto` exists.
2. Change `providers.id` default to `gen_random_uuid()`.
3. Change `supplier_aliases.id` default to `gen_random_uuid()`.
4. Replace `uuid_generate_v4()` inside `public.prevent_duplicate_provider()` with `gen_random_uuid()`.

This is safer than widening search paths because:

- `gen_random_uuid()` is already available from `pg_catalog`/`pgcrypto`.
- It follows the project's newer migrations.
- It avoids relying on `extensions` being present in function search paths.
- It keeps triggers and audit/supplier logic enabled.

Do not disable `auto_resolve_supplier`, `resolve_supplier`, provider duplicate checks, or audit logging.

## 9. Files / Migrations To Modify

Add one migration:

- `supabase/migrations/20260606_fix_supplier_uuid_generation.sql`

The migration should update live DB behavior with:

- `ALTER TABLE public.providers ALTER COLUMN id SET DEFAULT gen_random_uuid();`
- `ALTER TABLE public.supplier_aliases ALTER COLUMN id SET DEFAULT gen_random_uuid();`
- `CREATE OR REPLACE FUNCTION public.prevent_duplicate_provider()` using `gen_random_uuid()` instead of `uuid_generate_v4()`.

No Flutter or Edge Function code is required for the root fix.

## 10. Files To Leave Untouched

Leave untouched:

- OpenRouter model and prompt
- PDF rendering/upload logic
- `documents.ocr_raw_data.pages`
- Flutter UI
- dashboard/FAB/navigation/auth
- Storage bucket policies
- RLS policies
- `document_pages` schema; do not introduce it
- `process-document` extraction/page aggregation logic
- product matching logic, unless validation reveals a separate product-matching UUID failure

## 11. Validation Plan

Static/live DB validation:

1. Apply only the new migration file to linked Supabase.
2. Query defaults still using `uuid_generate_v4()`.
3. Query functions still using `uuid_generate_v4()`.
4. Confirm `providers.id` and `supplier_aliases.id` use `gen_random_uuid()`.
5. Confirm `prevent_duplicate_provider()` no longer references `uuid_generate_v4()`.
6. Re-run the exact rollback `documents.update(...)` reproduction. It should succeed and roll back.

Code validation:

1. `deno check supabase/functions/process-document/index.ts`
2. No Flutter analyzer required unless Flutter files change.

Runtime validation:

1. Re-extract `document (23).pdf`.
   - Expected: no UUID error.
   - Expected: parent `documents.status` becomes `completed` or `flagged`, not stuck due to UUID.
   - Expected: `extraction_clean` is populated when completed.
2. Re-extract `document (24).pdf`.
   - Expected: same.
3. Verify extracted products remain visible.
4. Verify no duplicate `document_items` for re-extraction.
5. Verify supplier/provider resolution still works.
6. Verify product matching still runs only after item rows exist.
7. Verify tenant isolation remains unchanged.

## 12. Implemented Fix

Implemented in:

- `supabase/migrations/20260606_fix_supplier_uuid_generation.sql`

The migration:

1. Ensures `pgcrypto` exists.
2. Changes `public.providers.id` default to `gen_random_uuid()`.
3. Changes `public.supplier_aliases.id` default to `gen_random_uuid()`.
4. Replaces both `uuid_generate_v4()` calls inside `public.prevent_duplicate_provider()` with `gen_random_uuid()`.

No Flutter files, OpenRouter code, PDF extraction code, or product matching code were changed.

## 13. Post-Fix Validation Results

The migration was applied to the linked Supabase project with:

```powershell
npx supabase db query --linked --file supabase/migrations/20260606_fix_supplier_uuid_generation.sql
```

Live validation after applying the migration:

- `providers.id` now defaults to `gen_random_uuid()`.
- `supplier_aliases.id` now defaults to `gen_random_uuid()`.
- Extraction-path defaults for `activity_logs`, `documents`, `document_items`, `products`, `providers`, and `supplier_aliases` now all use `gen_random_uuid()`.
- Live application-owned function search no longer finds `uuid_generate_v4()`; only the extension function itself remains at `extensions.uuid_generate_v4()`.
- Non-extraction defaults still using `uuid_generate_v4()` remain on `categories`, `companies`, `company_users`, `expenses`, `order_items`, `orders`, and `sales`; those were intentionally left untouched because the reproduced failure path does not use them.

The exact rollback reproduction that failed before now succeeds:

```sql
BEGIN;

UPDATE public.documents
SET
  status = 'completed',
  ocr_status = 'completed',
  extraction_clean = jsonb_build_object(
    'supplier_name', 'UUID Probe Supplier 20260606',
    'document_type', 'delivery_note',
    'line_items', '[]'::jsonb
  ),
  notes = null,
  updated_at = now()
WHERE id = 'fa17b100-02b1-4513-98e1-2fd1208bb704'
RETURNING id, provider_id;

ROLLBACK;
```

Result:

```json
[
  {
    "id": "fa17b100-02b1-4513-98e1-2fd1208bb704",
    "provider_id": "857f5ddb-bf2b-42d3-8487-d31f7b01db7f"
  }
]
```

This proves the document completion trigger path can now resolve/create suppliers without the `uuid_generate_v4()` failure.
