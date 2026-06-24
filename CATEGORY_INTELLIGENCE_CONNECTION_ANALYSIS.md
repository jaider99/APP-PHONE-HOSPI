# Category Intelligence Connection Analysis

Date: 2026-06-15

## 1. Current category model

Categories are company-scoped rows in `public.categories`.

Live category fields confirmed in project `qbvfeizmcuctmhrxkvbx`:

- `id uuid`
- `company_id uuid`
- `name text`
- `color_hex text`
- `icon text`
- `sort_order integer`
- `is_active boolean`
- `created_at timestamptz`

The live table does not have a `type` column. The active company `e70aabbf-679d-4270-aaf6-bb8a8c25babe` has the expected hospitality categories: Raw Materials, Drinks, Cleaning, Consumables, Administrative services, Marketing and communication, Rent, Finance, Maintenance, Logistics, Utilities, and Other.

Important foreign keys:

- `documents.category_id -> categories.id`
- `documents.ai_category_id -> categories.id`
- `expenses.category_id -> categories.id`
- `products.category_id -> categories.id`

Because `documents` has two relationships to `categories`, PostgREST embeds from `documents` to `categories` must specify the intended foreign key.

## 2. Current upload category selector flow

The upload category selector is in `lib/features/expenses/presentation/screens/expense_form_screen.dart`.

The dropdown:

- uses `expenseCategoriesProvider`
- renders `No category` as `value: null`
- renders company categories as `DropdownMenuItem<String>(value: c.id, ...)`
- calls `ExpenseFormNotifier.setCategory`

This means the UI uses category IDs, not category names or enums.

## 3. Where selected category is stored in Flutter state

The selected category is stored in `ExpenseFormState.categoryId` in `lib/features/expenses/presentation/providers/expense_form_provider.dart`.

`setCategory(String? id)` writes the selected category ID. Passing `null` clears the category. The `No category` option is therefore represented as null, not as a real category row.

## 4. Payload sent during document upload

`ExpenseFormNotifier.submit()` calls `documentUploadServiceProvider.submitExpenseFlow(...)` with:

- `categoryId: state.categoryId`
- `documentType: state.documentType`
- `paymentMethod: state.paymentMethod`
- `purchaseOrderId: state.purchaseOrderId`
- `incident: state.incident`
- `isPaid: state.isPaid`

The selected category ID is present in the upload payload when the user selects a category.

## 5. Database field receiving category_id

`DocumentUploadService.submitExpenseFlow` in `lib/providers/documents_provider.dart` inserts the selected category into both places:

- `documents.category_id`
- `expenses.category_id` when the linked expense row is created

It also logs the value with:

`[CATEGORY] Upload category_id=$categoryId doc=$documentId`

Live evidence confirms recent uploads have `documents.category_id` set. Example rows:

- `document (26).pdf`: `category_id = 63975ea7-02cf-4185-a8e2-4fa23a5df432`, category Raw Materials, `status = completed`, `total_amount = 95.52`
- `scaled_45.jpg`: `category_id = 53dfaaa3-3cea-47a4-a050-0ee09eaa5cc9`, category Drinks, `status = completed`, `total_amount = 1075.85`

The upload/save path is not the primary reason the dashboard is empty.

## 6. Whether extraction overwrites category_id

`supabase/functions/process-document/index.ts` finalizes extraction with an update to `documents` containing:

- `status`
- `ocr_status`
- `document_type`
- `document_number`
- `document_date`
- `subtotal`
- `tax_amount`
- `total_amount`
- `currency`
- `extraction_raw`
- `extraction_clean`
- `notes`

It does not update `category_id`. Therefore it preserves an existing user-selected `documents.category_id`.

`supabase/functions/classify-expense/index.ts` writes AI classification to `expenses.category_id` and `category_confidence`, not `documents.category_id`. This can matter for older rows where only `expenses.category_id` exists, but it does not overwrite the selected document category.

## 7. Intelligence source

Dashboard category intelligence is provided by `categoryIntelligenceProvider` in `lib/features/dashboard/providers/intelligence_providers.dart`, which calls `IntelligenceService.fetchCategoryIntelligence(...)`.

`IntelligenceService.fetchCategoryIntelligence` uses two sources:

1. Productized line-item spend from `product_prices`, joined through `products.category_id`.
2. Document-level fallback spend from `documents.category_id` and `documents.total_amount` for categorized documents that do not have categorized product price rows.

The dashboard does not read `expenses.category_id` for the Intelligence section.

The expense tracker has a separate service, `ExpenseService.fetchDocumentCategorySummaries`, which prefers `expenses.category_id` and falls back to `documents.category_id`. That is not the dashboard Intelligence source.

## 8. Why Spend by Category returns empty

The dashboard document fallback query embeds `categories(...)` from `documents` without specifying the foreign key:

```dart
.from('documents')
.select(
  'id, company_id, category_id, total_amount, document_date, '
  'categories(id, name, color_hex, icon, sort_order)',
)
```

Live PostgREST reproduction returned:

```text
STATUS=300
code=PGRST201
message=Could not embed because more than one relationship was found for 'documents' and 'categories'
hint=Try changing 'categories' to one of: categories!documents_ai_category_id_fkey, categories!documents_category_id_fkey
```

`IntelligenceService.fetchCategoryIntelligence` catches `PostgrestException`, logs it, and returns `[]`. The UI then sees no active categories and displays `No categorised expenses this month.`

This is the exact root cause of the observed empty dashboard despite real categorized documents existing.

## 9. Whether date filters are excluding data

Date filtering is a secondary risk, not the exact root cause for the current empty state.

Current dashboard document fallback requires:

- `status = completed`
- `category_id IS NOT NULL`
- `total_amount IS NOT NULL`
- `document_date IS NOT NULL`
- `document_date` inside the selected rolling dashboard period

Live data for company `e70aabbf-679d-4270-aaf6-bb8a8c25babe` has dashboard-eligible categorized documents in the current rolling period. The SQL equivalent of the current filters found two non-deleted rows totaling `1884.01`:

- Raw Materials: `808.16`
- Drinks: `1075.85`

However, the current implementation excludes documents with null `document_date`. The business rule requested for financial intelligence is `COALESCE(document_date, created_at::date)`, so the safe fix should use that fallback in the client-side aggregation if PostgREST cannot express it directly.

## 10. Whether RLS/views are blocking data

Dashboard Intelligence currently queries base tables from Flutter with the user's session and company filter. No database view is required for category intelligence.

The reproduced failure is a PostgREST relationship ambiguity (`PGRST201`), not an RLS denial. RLS should remain enabled and tenant isolation should continue to rely on both:

- client-side `.eq('company_id', companyId)` filters
- server-side RLS policies

No service role is needed in Flutter.

## 11. Exact root cause

The exact root cause is an ambiguous PostgREST embed in the dashboard category intelligence document fallback query.

`documents` has two foreign keys to `categories`: `category_id` and `ai_category_id`. The query uses `categories(...)` without `!documents_category_id_fkey`, so PostgREST returns `PGRST201` HTTP 300 Multiple Choices. `IntelligenceService.fetchCategoryIntelligence` catches the exception and returns an empty list. The UI then displays `No categorised expenses this month.`

The selected category is being saved correctly for recent uploads. Extraction preserves `documents.category_id`. Live data has eligible categorized documents. The dashboard is empty because the intelligence query fails and the error is swallowed as an empty state.

## 12. Minimal safe fix

The minimal production-safe fix is:

1. Change the document fallback embed in `IntelligenceService._fetchCategorizedDocumentRows` from `categories(...)` to `categories!documents_category_id_fkey(...)`.
2. Keep the source canonical for dashboard category spend as:
   - product-level `product_prices` joined through `products.category_id` when available
   - document-level `documents.category_id` fallback when product category spend is absent
3. Add safe debug logging in `fetchCategoryIntelligence` for company ID, source row counts, date range, and errors without invoice contents.
4. Apply the requested date fallback by fetching candidate categorized documents for a broader lower-bound window and filtering in Dart using `document_date ?? created_at`.
5. Do not touch OpenRouter prompts, extraction logic, RLS, storage policies, dashboard UI, sales, POS, or navigation.

No hardcoded totals, mock data, duplicate category tables, service-role Flutter access, or RLS weakening are needed.

## 13. Files to modify

Expected minimal code modification:

- `lib/services/intelligence_service.dart`

Possible documentation update after validation:

- `PROJECT_CONTEXT.md`

## 14. Files to leave untouched

Leave these untouched unless a later validation falsifies this root cause:

- `supabase/functions/process-document/index.ts`
- `supabase/functions/classify-expense/index.ts`
- `supabase/functions/recognize-products/index.ts`
- OpenRouter model configuration and VLM prompts
- PDF extraction code
- storage policies
- auth and registration
- sales and POS integrations
- product detail UI
- bottom navigation and FAB
- dashboard presentation widgets

## 15. Validation checklist

1. PostgREST query with `categories!documents_category_id_fkey(...)` returns no `PGRST201` ambiguity.
2. Focused analyzer passes for `lib/services/intelligence_service.dart` with no errors.
3. Live query confirms current-period categorized documents exist for the active company.
4. `fetchCategoryIntelligence` no longer returns `[]` when document fallback rows exist.
5. Dashboard `Spend by Category` shows Drinks and Raw Materials for the live eligible rows.
6. Upload selecting Drinks stores `documents.category_id = Drinks ID`.
7. Extraction completion preserves `documents.category_id`.
8. Upload with No category stores null and does not appear in categorized spend.
9. Documents with null `document_date` use `created_at` as fallback for dashboard period matching.
10. Company A category spend remains invisible to Company B through company filters and RLS.
11. Dashboard updates through the existing realtime provider without app restart.
12. VLM extraction and product extraction behavior remains unchanged.