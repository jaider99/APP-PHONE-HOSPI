# UUID Generation Extraction Failure Analysis

Date: 2026-06-06

## Scope

This analysis covers the new extraction finalization failure after the PDF multipage finalization fix:

```text
Extraction error: Failed to finalize document extraction: function uuid_generate_v4() does not exist
```

The goal is to identify the exact caller of `uuid_generate_v4()` and apply the smallest safe Supabase/Postgres fix without changing PDF rendering, OpenRouter, Flutter UI, tenant checks, or the document page model.

## 1. Exact Error

The UI shows:

```text
Extraction error: Failed to finalize document extraction: function uuid_generate_v4() does not exist
```

The message prefix `Failed to finalize document extraction:` comes from the checked parent-document update in `supabase/functions/process-document/index.ts`.

The failing Supabase operation is the final `documents.update(...)` that sets:

- `status = completed`
- `ocr_status = completed`
- document fields such as `document_type`, `document_number`, totals
- `extraction_raw`
- `extraction_clean`
- `notes = null`

## 2. Where It Occurs In The Extraction Pipeline

The failure occurs after OpenRouter extraction and after line item persistence.

Current path:

1. Flutter invokes `process-document` with `{ documentId }`.
2. Edge Function validates the user through Supabase Auth.
3. Edge Function reads the document through the user/RLS client.
4. Edge Function derives `company_id` from the document row.
5. Edge Function resolves rendered PDF pages from `documents.ocr_raw_data.pages`.
6. OpenRouter VLM returns extraction JSON.
7. `document_items` are deleted and inserted with checked errors.
8. Final parent `documents.update(...)` runs.
9. The update fires database triggers on `documents`.
10. One trigger inserts into `activity_logs` without an explicit `id`.
11. `activity_logs.id DEFAULT uuid_generate_v4()` is evaluated in a restricted trigger/search-path context and fails.

So the failure is in database finalization side effects, not VLM extraction and not Flutter UI.

## 3. Which File/Function Calls `uuid_generate_v4()`

`process-document` does not directly call `uuid_generate_v4()`.

The exact extraction failure path is:

- Edge Function file: `supabase/functions/process-document/index.ts`
- Edge Function operation: final `serviceClient.from("documents").update(...)`
- Live DB trigger on `documents`: `log_documents_activity`
- Trigger function: `public.log_activity()`
- Trigger behavior: inserts into `public.activity_logs` without an explicit `id`
- Live default expression: `public.activity_logs.id DEFAULT uuid_generate_v4()`

The trigger function itself does not call `uuid_generate_v4()` explicitly. The table default does.

## 4. Classification Of The Call Site

The call is in a default column expression, reached through a trigger.

| Possible source | Finding |
|---|---|
| Edge Function SQL | No direct `uuid_generate_v4()` call found in `process-document`. |
| Migration | Original schema migrations use `uuid_generate_v4()` defaults extensively. |
| RPC/function body | Live DB function search found `public.prevent_duplicate_provider` references `uuid_generate_v4()`, but not the extraction finalization path. |
| Insert payload | `process-document` does not send an `id` for `document_items` or `documents`; it relies on DB defaults. |
| Trigger | `documents` update fires `log_documents_activity`, which calls `public.log_activity()`. |
| Default column expression | `activity_logs.id DEFAULT uuid_generate_v4()` is the direct failing expression during trigger insert. |

## 5. Project UUID Standard

The project is mixed historically:

- Early migrations use `uuid-ossp` and `uuid_generate_v4()`.
- Later migrations use `pgcrypto` and `gen_random_uuid()`.
- Live extraction-related defaults are mixed.

Live defaults for involved tables:

| Table | id default |
|---|---|
| `activity_logs` | `uuid_generate_v4()` |
| `document_items` | `uuid_generate_v4()` |
| `documents` | `uuid_generate_v4()` |
| `products` | `uuid_generate_v4()` |
| `product_prices` | `gen_random_uuid()` |
| `review_items` | `gen_random_uuid()` |

Because `gen_random_uuid()` is available from `pg_catalog`, it is safer under restricted `search_path` contexts than unqualified `uuid_generate_v4()` in the `extensions` schema.

## 6. Is `pgcrypto` Enabled?

Yes.

Live DB inspection found:

| Extension | Schema |
|---|---|
| `pgcrypto` | `extensions` |

Function inspection also found:

| Function | Schema |
|---|---|
| `gen_random_uuid()` | `extensions` |
| `gen_random_uuid()` | `pg_catalog` |

A direct SQL test showed `gen_random_uuid()` works.

## 7. Is `uuid-ossp` Enabled?

Yes, but it is installed in the `extensions` schema:

| Extension | Schema |
|---|---|
| `uuid-ossp` | `extensions` |

Function inspection found:

| Function | Schema |
|---|---|
| `uuid_generate_v4()` | `extensions` |

A reproduction query with restricted search path failed:

```sql
SET LOCAL search_path TO public;
SELECT uuid_generate_v4();
```

Error:

```text
function uuid_generate_v4() does not exist
```

This matches the extraction finalization failure because `public.log_activity()` is defined with `SET search_path TO 'public'` and inserts into `activity_logs` inside that context.

## 8. Safest Fix

Preferred fix: replace affected `uuid_generate_v4()` defaults with `gen_random_uuid()`.

Reasons:

1. `gen_random_uuid()` is available in the live DB.
2. It is already used by newer project migrations.
3. It is available from `pg_catalog`, so it works under restricted `search_path` contexts.
4. It avoids relying on unqualified `uuid_generate_v4()` in the `extensions` schema.
5. It does not change tenant policies, RLS, storage, PDF rendering, OpenRouter, or Flutter UI.

Do not enable a new dependency as the primary fix. `uuid-ossp` is already enabled; visibility/search-path is the issue.

## 9. Files To Modify

Add one narrow migration:

- `supabase/migrations/20260606_fix_uuid_defaults_for_extraction.sql`

The migration should:

1. Ensure `pgcrypto` exists.
2. Change only extraction-involved table defaults that currently use `uuid_generate_v4()`:
   - `public.activity_logs.id`
   - `public.documents.id`
   - `public.document_items.id`
   - `public.products.id`
3. Leave tables already using `gen_random_uuid()` unchanged:
   - `public.product_prices.id`
   - `public.review_items.id`

Rationale for touching the four defaults:

- `activity_logs` is the direct current failure path during `documents` finalization.
- `document_items` is inserted by `process-document` without explicit IDs.
- `documents` is the parent extraction table and can be created by upload flows without explicit DB-side IDs in other paths.
- `products` can be inserted by product recognition after extraction.

## 10. Files To Leave Untouched

Do not modify:

- Flutter UI files
- dashboard/FAB/navigation/auth files
- PDF rendering code
- OpenRouter model or prompt
- `documents.ocr_raw_data.pages` page model
- storage bucket public/private settings
- RLS policies
- `process-document` extraction logic except if validation reveals a direct UUID bug there
- `recognize-products` logic except if validation reveals a direct UUID bug there

## 11. Validation Plan

Static/schema validation:

1. Run migration against linked Supabase project.
2. Query live defaults after migration:

```sql
SELECT table_name, column_name, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name IN (
  'documents',
  'document_items',
  'products',
  'product_prices',
  'review_items',
  'activity_logs'
)
AND column_name = 'id'
ORDER BY table_name;
```

Expected:

- `activity_logs.id = gen_random_uuid()`
- `document_items.id = gen_random_uuid()`
- `documents.id = gen_random_uuid()`
- `products.id = gen_random_uuid()`
- `product_prices.id = gen_random_uuid()`
- `review_items.id = gen_random_uuid()`

3. Re-run restricted-search-path reproduction:

```sql
SET LOCAL search_path TO public;
INSERT INTO public.activity_logs (...required fields...)
```

or validate through document re-extraction, which exercises the same trigger path.

Code validation:

1. `deno check supabase/functions/process-document/index.ts`
2. No Flutter analyzer run is required unless Flutter files are changed.

Runtime validation:

1. Re-extract `document (23).pdf`.
   - Expected: no `uuid_generate_v4()` error.
   - Expected: status becomes `completed` or `flagged`, not stuck `processing`.
2. Re-extract `document (24).pdf`.
   - Expected: no `uuid_generate_v4()` error.
3. Confirm `document_items` rows have valid UUIDs.
4. Confirm parent `documents` row finalizes.
5. Confirm single-image extraction still works.
6. Confirm document 22 still works.
7. Confirm product matching only runs after item rows exist.
8. Confirm tenant isolation remains unchanged: company access is still validated before service-role writes.

## 12. Implemented Fix

Implemented migration:

- `supabase/migrations/20260606_fix_uuid_defaults_for_extraction.sql`

The migration keeps the fix narrow and changes only extraction-involved table defaults:

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE IF EXISTS public.activity_logs
   ALTER COLUMN id SET DEFAULT gen_random_uuid();

ALTER TABLE IF EXISTS public.documents
   ALTER COLUMN id SET DEFAULT gen_random_uuid();

ALTER TABLE IF EXISTS public.document_items
   ALTER COLUMN id SET DEFAULT gen_random_uuid();

ALTER TABLE IF EXISTS public.products
   ALTER COLUMN id SET DEFAULT gen_random_uuid();
```

The migration was applied to the linked Supabase project with `supabase db query --linked --file` rather than `supabase db push`, because `db push --dry-run` showed several older local migrations would also be pushed. Applying only this file avoided unrelated schema changes.

## 13. Validation Results

Completed validation:

- Live defaults now show `gen_random_uuid()` for:
   - `activity_logs.id`
   - `document_items.id`
   - `documents.id`
   - `products.id`
   - `product_prices.id`
   - `review_items.id`
- A rolled-back insert into `public.activity_logs` under `SET LOCAL search_path TO public` generated an ID successfully.
- `deno check supabase/functions/process-document/index.ts` passed.
- VS Code diagnostics reported no errors for this analysis file, the migration, or `process-document`.

Runtime note: re-extracting `document (23).pdf` and `document (24).pdf` through the authenticated app should now pass the previous UUID failure point. I could not invoke `process-document` directly from the CLI without a user JWT, and the function correctly requires user authentication before service-role writes.
