# Sales Import Failure Analysis

Date: 2026-06-13

## 1. Current Sales Import Flow

The Sales import flow starts in `ImportSalesScreen`. The user picks a sales report file, Flutter reads the bytes, resolves the active `company_id`, uploads the file to Supabase Storage, inserts a `sales_imports` row with `status = processing`, then invokes the `process-sales-import` Edge Function asynchronously.

The UI returns to `/sales` immediately after queueing the import. Processing completion is expected to arrive through `sales_imports` / `sales` realtime invalidation and repository refresh.

## 2. Flutter File Picker / Upload Flow

`lib/features/sales/presentation/screens/import_sales_screen.dart` uses `FilePicker.platform.pickFiles` with these extensions:

- `pdf`
- `csv`
- `jpg`
- `jpeg`
- `png`
- `webp`

On mobile, `file.path` is read with `File(file.path!).readAsBytes()`. The local Android path is not sent to the Edge Function. Only the uploaded Supabase Storage path is persisted.

`_submit()` calls `SalesRepository.createSalesReportImport(...)` with:

- `companyId` from `companyIdProvider`
- selected `file.name`
- selected bytes
- MIME type inferred from file extension

## 3. Supabase Storage Path Used

`StorageService.uploadSalesImport(...)` uploads to bucket:

```text
sales-imports
```

Current path format:

```text
company_id/sales_import_id/sanitized_file_name
```

Live failed examples confirm the persisted path is a Supabase object path, not a local Android path:

```text
e70aabbf-679d-4270-aaf6-bb8a8c25babe/81330d03-895c-4a74-ab84-a8084767f2e9/captura_de_pantalla_2026-06-13_165431.png
```

## 4. `sales_imports` Row Creation Flow

`SalesRepository.createSalesReportImport(...)` generates a UUID import id, uploads the file, then inserts:

```json
{
  "id": "<salesImportId>",
  "company_id": "<activeCompanyId>",
  "source_type": "vlm_import",
  "source_name": "Image sales report | PDF sales report | CSV sales report | Sales report",
  "file_path": "<storage path>",
  "status": "processing",
  "created_by": "<current user id>"
}
```

The insert returns a `SalesImport` model and `_invokeSalesImport(...)` is started with `unawaited(...)`.

## 5. Payload Sent To `process-sales-import`

Current Flutter call:

```dart
await _supabase.functions.invoke(
  'process-sales-import',
  body: {'salesImportId': salesImportId},
);
```

The current request body is camelCase:

```json
{
  "salesImportId": "..."
}
```

The Edge Function currently expects the same camelCase field, so the observed 500 is not caused by a request-body name mismatch.

Recommended canonical contract going forward:

```json
{
  "sales_import_id": "..."
}
```

For compatibility, the Edge Function can temporarily accept both `sales_import_id` and `salesImportId` while Flutter is moved to snake_case.

## 6. Edge Function Request Schema

`supabase/functions/process-sales-import/index.ts` currently calls:

```ts
readJsonObject(req, {
  maxBytes: 1024,
  allowedFields: ["salesImportId"],
});
```

Then:

```ts
salesImportId = requireStringField(body, "salesImportId", { maxLength: 64 });
```

This validates a single import id. It does not accept `company_id` from Flutter.

## 7. Edge Function Auth / Company Validation

The function requires `Authorization`, creates a user Supabase client with the caller JWT, and calls `userClient.auth.getUser()`.

Then it fetches the import row through the user client:

```ts
userClient
  .from("sales_imports")
  .select("id, company_id, file_path, status")
  .eq("id", salesImportId)
  .maybeSingle();
```

This is the correct tenant-safe validation boundary: RLS must allow the authenticated user to see only their company import rows. `company_id` is derived from the row after access is validated.

The service-role client is only used after that validation for storage download and database writes.

## 8. Storage Access Method

The function downloads the uploaded file via service-role storage access:

```ts
serviceClient.storage
  .from("sales-imports")
  .download(path);
```

It checks:

- file exists
- byte size <= 10 MB
- MIME type from Blob type or file extension

Images are converted to a base64 data URL for OpenRouter. CSV/text is sent as text. PDFs currently return `unsupported_pdf`.

## 9. OpenRouter Request Payload

The function calls:

```text
https://openrouter.ai/api/v1/chat/completions
```

Model:

```text
OPENROUTER_SALES_MODEL or nvidia/nemotron-nano-12b-v2-vl:free
```

Current payload shape:

```json
{
  "model": "...",
  "temperature": 0,
  "max_tokens": 2500,
  "messages": [
    {"role": "system", "content": "You extract sales data and return strict JSON only."},
    {"role": "user", "content": "text or image content"}
  ]
}
```

For image imports, the user message contains a text prompt and an `image_url` data URL.

Required production schema should be tightened toward explicit sales-report fields such as `report_type`, `period_start`, `gross_revenue`, `payment_methods`, `channels`, `items`, and `raw_text`, but that is not the root cause of the current 500.

## 10. VLM Response Parsing

The current parser extracts `choices[0].message.content`, strips optional Markdown fences, finds the first `{` and last `}`, and parses JSON.

Money and quantity normalization uses `supabase/functions/_shared/number_normalization.ts`, which correctly supports European formats like:

- `1.506,21` -> `1506.21`
- `808,16` -> `808.16`

Parser failures currently throw inside the function catch and become a generic `{error: "Sales import failed"}` response.

## 11. Database Insert / Update Flow

The function currently:

1. Marks the import `processing`.
2. Downloads the storage object.
3. Calls OpenRouter.
4. Normalizes and validates extraction.
5. Deletes prior `sales_items` for the import.
6. Deletes prior `sales` rows for the import.
7. Inserts one `sales` row per normalized transaction.
8. Inserts `sales_items` rows for visible item rows.
9. Marks the import `completed` with totals and validation metadata.

Live schema inspection confirms:

- `sales_imports` has `extraction_raw` and `extraction_clean`, but no `metadata` column.
- `sales_items` has `metadata`, but no `source_type` column.
- `sales` does have `source_type` and `metadata`.
- `sales.channel` is constrained to `dine_in`, `takeaway`, `delivery`, or `unknown`.

## 12. Exact Reason For The 500

The 500 is inside `process-sales-import`, after Flutter has successfully uploaded the file and invoked the function.

The confirmed root cause is a database write contract mismatch between the Edge Function and the deployed Sales schema:

1. `process-sales-import` inserts `source_type: "vlm_import"` into `sales_items`, but the live `sales_items` table has no `source_type` column.
2. `process-sales-import` updates `sales_imports` with `metadata: { validation_results: ... }`, but the live `sales_imports` table has no `metadata` column. It has `extraction_raw` and `extraction_clean` instead.
3. `process-sales-import` can insert `channel: "report"` for aggregate imports, but the live `sales.channel` check constraint only allows `dine_in`, `takeaway`, `delivery`, or `unknown`.

Either mismatch can produce the generic 500 depending on the VLM output:

- If item rows are present, failure occurs during `insert_sales_items`.
- If no item rows are present and sale insertion succeeds, failure occurs during `finalize_sales_import` when writing `metadata` to `sales_imports`.
- On validation failure, the same invalid `metadata` update path can also fail while trying to mark the import failed.
- If an aggregate fallback row or VLM response yields an unsupported channel, failure occurs during `insert_sales_rows`.

The latest database rows show Flutter then overwrote the more specific server-side note with the generic client-side note:

```text
Sales import processing could not be started.
```

That masks the internal function stage in `sales_imports.notes`.

Supabase CLI 2.106.0 in this workspace does not expose `supabase functions logs`; `npx supabase functions logs process-sales-import` returns an unknown-subcommand help response. Evidence used here is the Flutter stack trace, deployed function presence, live `sales_imports` rows, live table column inspection, and direct code/schema comparison.

## 13. Minimal Safe Fix

Minimal root fix:

1. Remove `source_type` from `sales_items` inserts, or store item source data inside `sales_items.metadata`.
2. Replace invalid `sales_imports.metadata` updates with `extraction_raw` and `extraction_clean` writes.
3. Normalize unknown or aggregate channels to `unknown` before inserting into `sales`.
4. Add stage-based safe diagnostics so future failures return structured stage data instead of only `{error: "Sales import failed"}`.
5. Preserve tenant-safe validation: Flutter sends only the import id; the Edge Function fetches the row through the authenticated/RLS client and derives `company_id` from the row.
6. Update Flutter `_invokeSalesImport` so it logs structured details and does not overwrite a more specific server-side status/note with the generic client-side note.

PDF handling is not the current failing file path because the observed failed rows are PNG screenshots. PDF imports should still be changed to `flagged` with clear notes instead of `failed` or generic 500 when rendering is not implemented.

## 14. Files To Modify

- `supabase/functions/process-sales-import/index.ts`
- `lib/features/sales/data/repositories/sales_repository.dart`
- `SALES_IMPORT_FAILURE_ANALYSIS.md`

Optional only if validation proves it is needed:

- `lib/features/sales/data/models/sales_import.dart`

## 15. Files To Leave Untouched

Do not touch:

- `supabase/functions/process-document/index.ts`
- document extraction code
- OpenRouter document VLM prompts/parsing
- `supabase/functions/recognize-products/index.ts`
- product matching
- PDF document extraction
- Products screens
- Documents screens
- Dashboard
- Auth
- Storage policies unless a sales-import bucket/path defect is separately proven
- Broad RLS policies

## 16. Validation Checklist

Code validation:

- `deno check supabase/functions/process-sales-import/index.ts`
- focused Dart analysis for `lib/features/sales/data/repositories/sales_repository.dart`
- VS Code diagnostics for touched files

Deployment validation:

- `npx supabase functions deploy process-sales-import`
- `npx supabase functions list` shows `process-sales-import` as `ACTIVE`

Runtime validation:

- Import JPEG sales screenshot: `sales_imports.status = completed`, real `sales` row inserted, Sales revenue updates.
- Import PNG sales screenshot: same as JPEG.
- Import PDF sales report: if PDF rendering is not implemented, `sales_imports.status = flagged` and notes explain to upload a screenshot/image; no generic 500.
- Import unclear/bad image: `sales_imports.status = flagged`, no fake sales rows.
- Money parsing: `1.506,21` becomes `1506.21`, `808,16` becomes `808.16`.
- Tenant isolation: Company A cannot invoke/import Company B's `sales_import_id`.
- Missing OpenRouter key simulation: returns structured `stage = call_openrouter` or configuration stage, no secret leakage.
- Database insert failure simulation: returns structured `stage = insert_sales_rows` or `insert_sales_items`.
- Existing document VLM extraction remains unaffected.