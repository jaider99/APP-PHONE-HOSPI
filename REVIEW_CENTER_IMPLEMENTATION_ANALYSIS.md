# REVIEW_CENTER_IMPLEMENTATION_ANALYSIS

Date: 2026-06-02

## 1. Existing App Architecture

HospiDash is a Flutter + Riverpod + GoRouter app backed by Supabase. Feature code is organized under `lib/features/<feature>/...` with data models, repositories/services, presentation providers, screens, and widgets. Shared operational providers live in `lib/providers`, and Supabase access is centralized through `SupabaseService.client`.

Relevant patterns already in the project:

- Tenant scope comes from `companyIdProvider` in `lib/providers/company_provider.dart`.
- Repositories receive `SupabaseClient` and every query includes `.eq('company_id', companyId)`.
- Realtime providers use `StreamProvider.autoDispose` and Supabase `onPostgresChanges` with a `company_id` filter.
- Dashboard metrics are fetched through `DashboardGridRepository` and rendered by `DashboardIntelligenceGrid`.
- Main app navigation lives in `lib/core/router/app_router.dart` inside a `ShellRoute` using `MainScaffold`.

The Review Center should follow the same structure:

```text
lib/features/review_center/
  data/models/
  data/repositories/
  presentation/providers/
  presentation/screens/
  presentation/widgets/
```

## 2. Existing Tables

Existing schema already exposes most reviewable signals. The Review Center should not duplicate source data.

| Area | Existing Table(s) | Useful Fields |
| --- | --- | --- |
| Documents | `documents` | `status`, `notes`, `extraction_clean`, `document_type`, `category_id`, `ai_category_id`, `category_confidence`, `is_duplicate`, `duplicate_of`, `provider_id`, `total_amount`, `tax_amount`, `merge_status`, `merge_confidence`, `deleted_at` |
| Line items | `document_items` | `product_id`, `description`, `quantity`, `unit_price`, `line_total`, `matched_automatically`, `confidence_score`, `normalized_description`, `supplier_id` |
| Expenses | `expenses` | `document_id`, `category_id`, `status`, `notes`, `total_amount`, `supplier_name` |
| Products | `products`, `product_aliases`, `product_prices`, `product_price_stats` | product identity, alias learning, observed prices, baseline stats |
| Suppliers | `providers`, `supplier_aliases` | supplier/provider identity and OCR alias mapping |
| Categories | `categories`, `category_learning` | active categories, AI prediction and confirmed category history |
| Price anomalies | `price_anomalies` | `resolved`, `resolution_status`, `severity`, `deviation_percent`, `explanation`, `product_id`, `document_id` |
| Duplicates | `documents`, `document_merges` | `is_duplicate`, `duplicate_of`, `merge_status='review'`, merge audit trail |
| Tenancy | `companies`, `company_users`, `profiles` | membership and current company context |
| Audit | `activity_logs` | sensitive operation history and metadata |

No existing physical review queue table exists.

## 3. Existing Services

Services/repositories to reuse:

- Document extraction and retry: `BackgroundExtractionService`, `ExtractionService`, and document providers in `lib/providers/documents_provider.dart`.
- Product matching: `ProductMatcherService`, `ProductRepository`, `find_product_alias_match`, `find_product_candidates` RPCs.
- Price anomaly resolution: `ProductRepository.resolvePriceAnomaly()` calls `resolve_price_anomaly` RPC.
- Category prediction/learning: `CategoryAIService`, `record_category_learning` RPC, document category fields.
- Supplier/provider creation and lookup: `ProvidersRepository`, `resolve_supplier` RPC.
- Audit: `record_security_audit_event` / `activity_logs` already exist in SQL.

The Review Center should orchestrate these systems, not reimplement them.

## 4. Existing AI Extraction Flow

Current flow:

```text
Flutter upload
  -> Supabase Storage
  -> documents row status='processing'
  -> background extraction
  -> process-document Edge Function
  -> OpenRouter VLM
  -> parse/normalize JSON
  -> documents status='completed' or 'flagged'/'failed'
  -> document_items inserted
  -> product recognition kicked off separately
```

Review Center should treat extraction failures as source signals:

- `documents.status IN ('flagged', 'failed')`
- `documents.notes` contains safe error details
- `documents.document_type = 'unknown'`
- missing required extracted fields such as `total_amount` or `provider_id`

It should call existing retry/re-extraction paths instead of duplicating AI calls.

## 5. Existing Product Recognition Flow

Product matching currently uses `document_items` plus product alias/fuzzy RPCs:

- `document_items.product_id IS NULL` means a line item is unmatched.
- `document_items.confidence_score` captures match confidence.
- `document_items.matched_automatically` indicates automatic matching.
- There is no explicit pending confirmation table today.

MVP should generate review items for unmatched or low-confidence `document_items`. Action handling can start with navigating to the source document/product context, then Phase 2 can add a dedicated product matching bottom sheet.

## 6. Existing Price Anomaly Flow

`price_anomalies` already has a mature workflow:

- `resolved boolean`
- `resolution_status` in `open`, `resolved`, `ignored`, `baseline_approved`
- `severity` enum: `low`, `medium`, `high`, `critical`
- `resolve_price_anomaly` RPC updates the anomaly and audit trail.

Review Center should create `price_anomaly` items where:

```sql
resolved = false AND resolution_status = 'open'
```

Actions should call the existing resolution RPC through the product repository or a focused Review Center repository method.

## 7. Existing Duplicate Detection Logic

Duplicate detection exists in database triggers and document fields:

- `documents.is_duplicate`
- `documents.duplicate_of`
- normalized supplier/document number fields
- `documents.merge_status = 'review'`
- `document_merges` records merge decisions
- existing `DocumentMergeReviewScreen` exists under `/documents/review-queue`

MVP should generate `duplicate_document` items from:

- `is_duplicate = true`
- or `merge_status = 'review'`

Primary action should navigate to existing duplicate/document review surfaces. Do not auto-delete or auto-merge.

## 8. Existing Category Logic

Category logic uses:

- `documents.category_id` for confirmed category
- `documents.ai_category_id` for suggestion
- `documents.category_confidence` for confidence
- `categories` table for company-scoped active categories
- `category_learning` for supplier/keyword learning

Review triggers:

- `category_id IS NULL`
- `ai_category_id IS NOT NULL AND category_id IS NULL`
- `category_confidence < threshold` (recommended threshold: 0.75)

MVP can create `missing_category` review items and resolve them by updating the document category in the source table. A full category picker can be reused or added in Phase 2.

## 9. Existing Document Status Logic

Dart enum currently supports:

```text
processing
completed
flagged
failed
```

Database and UI also use `merge_status` values:

```text
none
merged
review
```

There is no stable `needs_review` document status in the current schema, even though product language sometimes says "needs review". Review Center should not introduce a new document status as part of MVP. It should map existing source states to review items.

## 10. Existing Provider/Supplier Logic

The database table is `providers`, but product/UI language often says supplier. Existing supplier intelligence includes:

- `providers` table
- `supplier_aliases` table
- `resolve_supplier` RPC
- `ProvidersRepository` for manual provider creation

Review trigger:

- `documents.provider_id IS NULL` with an extracted `supplier_name` in `extraction_clean` or raw supplier text.

MVP can create `unknown_supplier` review items but action handling may initially route to the document or provider screen. Dedicated supplier matching is Phase 2.

## 11. Best Implementation Strategy

Use the hybrid model:

1. Physical `review_items` table for inbox state, resolution, ignore/dismiss, audit, and realtime.
2. SQL RPCs that derive review items from existing source tables.
3. Flutter repository/providers/screens that only read real `review_items` data.
4. Dashboard count backed by `review_items`, not derived ad hoc in the UI.

This avoids stale client-only logic while preserving user decisions like "ignore" and "resolved".

## 12. What Should Be Reused

Reuse:

- `companyIdProvider` for tenant context.
- Existing document retry/re-extraction flow.
- Existing duplicate merge review screen.
- Existing price anomaly RPC.
- Existing category/source document update logic where available.
- Existing dashboard grid style and route structure.
- Existing realtime provider pattern.
- Existing `user_company_ids()` RLS helper.
- Existing `update_updated_at_column()` trigger function.

## 13. What Should Not Be Duplicated

Do not duplicate:

- OpenRouter or extraction calls.
- Product fuzzy matching algorithms.
- Price anomaly resolution logic.
- Supplier/provider matching logic.
- Category learning logic.
- Tenant membership checks in client-only code.
- Notification data separate from review items.

## 14. Required Migrations

Create a migration that adds:

1. `review_items` table.
2. Check constraints for `review_type`, `severity`, and `status`.
3. Unique key: `(company_id, review_type, source_table, source_id)`.
4. Indexes for company/status/type/severity/source.
5. `updated_at` trigger using existing `update_updated_at_column()`.
6. RLS using `company_id = ANY(public.user_company_ids())`.
7. RPCs:
   - `sync_review_items_for_document(p_document_id uuid)`
   - `sync_review_items_for_company(p_company_id uuid)`
   - `resolve_review_item(p_review_item_id uuid, p_action text, p_payload jsonb default '{}'::jsonb)`

Do not add a `document_pages` table or new product/supplier workflow tables in MVP.

## 15. UI/UX Plan

The UI should be an operational inbox, not a marketing page.

Style direction: use the attached Digital Atelier design system and current dashboard/editorial widgets:

- high whitespace
- monochrome editorial palette
- rounded cards
- soft tonal surfaces
- no mock data
- action-first cards

Screen:

```text
Review Center
Items that need your attention

Summary strip:
Open | Critical | AI review | Price alerts

Filters:
All | Documents | Products | Suppliers | Categories | Price alerts | Failed

Cards:
icon + severity + title + description + source context + date
primary action + secondary action
```

MVP actions:

- Retry for failed extraction.
- Assign category for missing category (route/source document first if no picker is already reusable).
- Review duplicate (navigate to duplicate/document review).
- Review/resolve price anomaly.
- Ignore/mark resolved for all item types.

## 16. Realtime Plan

Subscribe to `review_items` with `company_id` filter.

On insert/update/delete:

- invalidate open item provider
- invalidate count provider
- invalidate dashboard metrics/count provider

Use a single `reviewCenterRealtimeProvider` and dispose the channel when the provider is disposed.

Add `review_items` to Supabase realtime publication if the project restricts realtime tables.

## 17. Permission and RLS Plan

Policies:

- `SELECT`: authenticated users can see rows where `company_id = ANY(public.user_company_ids())`.
- `UPDATE`: authenticated users can update rows where `company_id = ANY(public.user_company_ids())`.
- `INSERT`: authenticated users can insert rows only for companies they belong to. Server-side RPCs also enforce the source company.
- `DELETE`: not needed for MVP; use `status='dismissed'`/`ignored` instead.

RPCs must not trust client company ID blindly:

- document sync derives company_id from `documents`.
- item resolution checks the row is visible through RLS/membership.
- audit metadata should exclude OCR text, signed URLs, and raw invoice content.

## 18. MVP Scope

MVP deliverables:

1. `review_items` table and RLS.
2. Sync RPCs for documents, company, and item resolution.
3. Signals:
   - failed/flagged documents
   - missing category
   - duplicate document / merge review
   - unknown document type
   - unknown supplier
   - unmatched/low-confidence product line item
   - unresolved price anomaly
4. Flutter model/repository/providers.
5. Review Center screen with real data.
6. Realtime subscription.
7. Route `/review-center`.
8. Dashboard tile/count backed by real open review item count.
9. Basic actions: resolve, ignore, retry/navigate for source-specific work.

## 19. Future Phases

Phase 2:

- Dedicated category picker inside review cards.
- Product matching bottom sheet using `ProductMatcherService`.
- Supplier matching bottom sheet using `ProvidersRepository` / `resolve_supplier`.
- Low-confidence field editor for extraction fields.
- Bulk actions.
- Notification badges powered by `review_items`.

Phase 3:

- Assignment and SLA tracking.
- Multi-user collaboration.
- Review item comments.
- AI-suggested resolution bundles.
- Analytics for recurring operational issues.

## Signal Map

| Signal | Source Table | Condition | Review Type | User Action | Existing Service To Reuse |
| --- | --- | --- | --- | --- | --- |
| Extraction failed | `documents` | `status IN ('failed','flagged')` | `failed_extraction` | Retry, edit manually, ignore | `BackgroundExtractionService`, `ExtractionService`, document retry UI |
| Document needs review | `documents` | `merge_status='review'` or incomplete completed document | `document_needs_review` | Open document/review queue | Existing document detail + merge review screen |
| Duplicate document | `documents` | `is_duplicate=true OR merge_status='review'` | `duplicate_document` | Review duplicate, keep both, ignore | Duplicate guard + `DocumentMergeReviewScreen` |
| Unknown document type | `documents` | `document_type IS NULL OR document_type='unknown'` | `unknown_document_type` | Review fields | Document detail/correction flow |
| Missing category | `documents` | `category_id IS NULL` | `missing_category` | Assign category, use AI suggestion, ignore | category fields + category learning RPC |
| Low category confidence | `documents` | `ai_category_id IS NOT NULL AND category_confidence < 0.75` | `missing_category` | Confirm category | `CategoryAIService`, `record_category_learning` |
| Unknown supplier | `documents` | `provider_id IS NULL` | `unknown_supplier` | Match/create supplier, ignore | `ProvidersRepository`, `resolve_supplier` RPC |
| Missing total | `documents` | `status='completed' AND total_amount IS NULL` | `low_confidence_field` | Review fields | Document detail/manual edit |
| Product unmatched | `document_items` | `product_id IS NULL` | `product_match_review` | Match product, create product, ignore | `ProductMatcherService`, product repository |
| Low product match confidence | `document_items` | `product_id IS NOT NULL AND confidence_score < 75` | `product_match_review` | Confirm match | Product matching services |
| Price anomaly | `price_anomalies` | `resolved=false AND resolution_status='open'` | `price_anomaly` | Resolve, ignore, approve baseline | `ProductRepository.resolvePriceAnomaly()` / `resolve_price_anomaly` RPC |

## Risk Analysis

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Review items become stale | Users see resolved problems | Sync RPC resolves stale items when source condition disappears |
| Duplicate items | Inbox noise | Unique key on company/type/source/source_id with `ON CONFLICT` updates |
| Tenant leakage | Critical security breach | RLS with `user_company_ids()`, all Flutter queries include `company_id` |
| Overbuilding actions | Delays MVP | MVP uses navigate/resolve/ignore; dedicated editors in Phase 2 |
| Realtime exposure missing | Dashboard/counts stale | Add `review_items` to realtime publication if required |
| Source systems use inconsistent names | Bad routing/actions | Normalize in Review Center model enums and metadata |

## Implementation Decision

Proceed with a hybrid physical `review_items` model. Implement the MVP as a real Supabase-backed feature, generated from existing source signals, with no mock data and no disconnected UI.
