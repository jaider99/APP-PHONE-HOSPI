# PROJECT_CONTEXT

## 1. Purpose
Single source of truth for HospiDash architecture, technical decisions, implementation status, and execution priorities.

This document is the canonical onboarding and planning artifact for engineering work.

## 2. Product Overview
- Product: HospiDash
- Type: Multi-tenant hospitality SaaS
- Platforms: Flutter mobile (iOS, Android)
- Backend: Supabase (Auth, Postgres, Storage, RLS)
- AI: OpenRouter VLM (NVIDIA Nemotron Nano 12B VL)
- State management: Riverpod
- Navigation: GoRouter
- Pattern: Feature-first clean architecture

## 3. Scope (Current Modules)
In-scope modules for current delivery wave:
- Dashboard
- Sales
- Documents (AI extraction)
- Providers
- Orders
- Expenses (expense capture form + category model + expense record lifecycle)

## 4. High-Level System Architecture
```text
Flutter App
  -> Supabase Auth (session)
  -> Supabase Postgres (tenant-scoped CRUD)
  -> Supabase Storage (document binaries)
  -> Extraction Pipeline (AI OCR + parsing)
  -> Reactive UI updates via Riverpod invalidation
```

Implementation anchors:
- Routing shell and auth redirects: lib/core/router/app_router.dart
- Upload + extraction orchestration: lib/providers/documents_provider.dart
- Expense submission UI and state: lib/features/expenses/presentation/screens/expense_form_screen.dart, lib/features/expenses/presentation/providers/expense_form_provider.dart
- Expense/category data access: lib/features/expenses/data/services/expense_service.dart
- Edge extraction function (currently active path): supabase/functions/process-document/index.ts

## 5. Multi-Tenancy Model
### 5.1 Tenant Unit
- Tenant = one company
- Tenant key = company_id (UUID)

### 5.2 Isolation Rules (Non-Negotiable)
- Every business table must include company_id
- Every read/write query must be tenant-scoped
- RLS must enforce tenant boundaries server-side even if client misses filters

### 5.3 Membership Mapping
- company_users maps user_id <-> company_id with role and active status
- profiles.current_company_id stores active company context

### 5.4 RLS Strategy
Defined in migration: supabase/migrations/00002_row_level_security.sql
- Helper functions:
  - public.get_current_company_id()
  - public.user_belongs_to_company(uuid)
  - public.user_has_role_in_company(uuid, text[])
  - public.user_is_company_admin(uuid)
- RLS enabled and forced for core tables (companies, profiles, company_users, providers, products, documents, document_items, orders, order_items, sales, activity_logs)

Additional helper in expenses/categories migration:
- public.user_company_ids() returns UUID[] for policy checks

## 6. Authentication and Access
- Auth provider: Supabase Auth (email/password; OAuth optional)
- Registration flow: 3-step onboarding in app_router guards
  - /register/company-id
  - /register/company-details
  - /register/user-account
- Post-login company resolution:
  - profiles.current_company_id + company_users membership
- Future planned: biometric unlock (local_auth dependency already present)

## 7. Document Processing Pipeline
## 7.1 Target Architecture (Required)
1. User captures photo or selects file (image/PDF)
2. Expense form opens before upload with metadata inputs:
   - category
   - document_type
   - payment_method
   - purchase_order_id
   - incident
   - is_paid
3. User taps Upload Expense
4. System:
   - uploads file to Supabase Storage
   - inserts documents row with status='processing'
   - runs extraction service
5. Extraction service responsibilities:
   - PDF -> image conversion (pdfx)
   - image compression
   - OpenRouter HTTP call with model nvidia/nemotron-nano-12b-v2-vl:free
6. Persist extraction results:
   - update documents status (completed/flagged)
   - insert document_items
7. UI auto-refreshes via provider invalidation

### 7.2 Hard Rules
- NO supabase.functions.invoke() in extraction pipeline
- NO Supabase Edge Functions in extraction pipeline
- API key currently handled in-app (temporary, high-risk posture)

### 7.3 Current Implementation Drift (as of 2026-04-22)
- Current code path still invokes Edge Function process-document from Flutter:
  - lib/providers/documents_provider.dart
- Server pipeline exists at:
  - supabase/functions/process-document/index.ts
- This is a known architecture mismatch to be removed in upcoming refactor.

## 8. Storage Contract
- Bucket: documents
- Path format: company_id/document_id/file.ext
- Current upload API: StorageService.uploadDocument(...)

## 9. Database Architecture
## 9.1 Core Tables
- companies
- profiles
- company_users
- providers
- products
- documents
- document_items
- orders
- order_items
- sales
- activity_logs

Base schema migration:
- supabase/migrations/00001_multi_tenant_schema.sql

### 9.2 Expenses + Categories Extension
Migration:
- supabase/migrations/20260422_expenses_and_categories.sql

Adds:
- categories (company-scoped, icon/color/sort metadata)
- expenses (linked to documents and categories)
- documents.expense_id FK
- RLS policies via user_company_ids()
- default category seeding (existing + new companies)

Seeded default expense categories:
- Raw Materials
- Drinks
- Cleaning
- Consumables
- Administrative services
- Marketing and communication
- Rent
- Finance
- Maintenance
- Logistics
- Utilities
- Other

## 10. Technical Decision Log (ADR-Style)
### [DEC-001] Feature-first Flutter structure with Riverpod
- Status: Accepted
- Reason: keeps module boundaries clear and testable
- Impact: providers and UI are colocated by feature (dashboard/sales/documents/providers/orders/expenses)

### [DEC-002] GoRouter shell-based navigation with auth-aware redirects
- Status: Accepted
- Reason: centralized route guard logic and bottom-nav shell
- Impact: consistent protected-route behavior and modular screens

### [DEC-003] Strict company-scoped persistence with Supabase RLS
- Status: Accepted
- Reason: enforce tenant isolation at DB layer
- Impact: all tables and queries include company_id, policy checks mandatory

### [DEC-004] Expense flow opens form before upload
- Status: Accepted
- Reason: metadata capture should happen before network operations
- Impact: user can set category/type/payment attributes pre-upload

### [DEC-005] Map-serialized GoRouter extras for complex args
- Status: Accepted
- Reason: avoid GoRouter complex-type codec warnings
- Impact: ExpenseFormArgs uses toMap/fromMap during navigation

### [DEC-006] No Edge Functions in extraction pipeline
- Status: Target Accepted (not yet fully implemented)
- Reason: simplify control path and remove function-runtime failure mode
- Impact: pending refactor to direct OpenRouter HTTP extraction service

## 11. Current State
### 11.1 Fully Working
- Multi-tenant base schema and core RLS migration set exists
- Registration flow routes and guards are in place
- Expense form opens before upload and supports metadata inputs
- Categories + expenses schema migration authored
- Category model includes color/sort metadata for UI
- Category dropdown supports visual color markers
- Documents list now has a realtime stream-backed source for tenant-scoped document updates, so processing/completed/flagged state changes propagate without manual refresh
- Document detail sheet: image preview loads instantly via signed URL stored at upload time
- Document detail sheet: PDF preview shows tappable card with fullscreen pdfx viewer
- Document detail sheet: all extracted fields (supplier, type, doc#, date, total, tax) render from DB columns with extraction_clean fallback
- AI extraction pipeline hardened: confidence-gated fields, OCR grounding checks, per-document logging
- process-document edge function deployed to production (project qbvfeizmcuctmhrxkvbx)
- process-document redeployed on 2026-05-14 with extraction_started_at claim logic to skip duplicate invocations; matching DB migration has been applied in the target Supabase environment
- process-document redeployed again on 2026-05-14 after the PDF handoff rewrite; current payload is documentId + companyId + imageUrl + currency
- process-document edge function now normalizes Spanish invoice dates (dd/mm/yyyy, dd-mm-yyyy, dd.mm.yyyy, and Spanish month-name formats) before persistence
- process-document now performs robust document-type classification with a classification-first VLM prompt, deterministic factura/albaran heuristics, raw_text extraction, and low-confidence fallback text classification
- PDF background extraction now preserves the original document folder contract: original PDF stays at company_id/document_id/original.pdf and rendered JPEG uploads back into the same company_id/document_id folder
- ExtractionService now logs and surfaces real Supabase FunctionException payloads instead of only the exception type, making function-side failures diagnosable from Flutter logs and documents.notes
- classify-document-type edge function deployed: secure text-only OpenRouter fallback for document-type detection; Flutter validates and persists final document_type without exposing API keys client-side
- process-document now also owns tenant-scoped category prediction and learning; documents store category_id, ai_category_id, and category_confidence
- classify-expense edge function deployed: assigns category_id + confidence (high/medium/low) via mistral-7b-instruct:free; company_id derived server-side, never client-trusted
- recognize-products edge function deployed: per-line-item alias/fuzzy/AI product matching, product creation, price history recording, and async AI image generation via Pollinations.ai → Supabase Storage
- Product recognition pipeline restored on the expense upload path: _runExtractionForExpense() now invokes recognize-products after process-document completes
- Product intelligence migration 20260510 applied to production: product_aliases, document_items.normalized_description, product_prices.supplier_id/date, exact alias RPC, fuzzy candidate RPC
- Product recognition pipeline complete end-to-end: DB migration applied, edge function deployed, Flutter screens built and routed
- PDF uploads now follow the same non-blocking contract as images in Flutter: upload + document insert return immediately, then PDF rendering/OCR preparation/extraction continue in a detached background path
- Products catalogue screen: 2-column grid with debounced search, category filter chips, CachedNetworkImage, skeleton loading, empty state
- Product detail screen: hero image, metadata chips, fl_chart price history line chart, recent purchases list, aliases, supplier breakdown, and pricing insights
- Products route added to GoRouter (/products shell, /products/:id fullscreen); product/stock access remains available through routed actions while the shell navigation currently focuses on the four primary destinations (Home, Sales, Docs, Orders)
- Supplier Intelligence UI is implemented in Flutter with routed supplier detail navigation
- Dashboard intelligence section built (IntelligenceSection widget) with category breakdown + top products cards; backing intelligence analytics migrations are applied
- Expenses screen now shows correct category breakdown; PGRST200 FK ambiguity resolved ([ISSUE-024])
- Product price anomaly engine is implemented and migration-backed: SQL migration, Edge Function detection hook, Flutter providers/models, realtime listeners, product health card, anomaly-highlighted price chart, supplier comparison badges, and anomaly timeline/resolution UI
- Security audit and remediation roadmap now exist as canonical security artifacts: `security_audit_report.md` and `SECURITY_REMEDIATION_ROADMAP.md`
- Security remediation through P3.5 is implemented in code: process-document auth/tenant hardening, redacted logging, fail-closed storage auth, tenant-filtered queries, step-up authentication, environment hardening, realtime exposure reduction, Edge Function input validation/rate limiting, and Edge Function type-check restoration
- OpenRouter-backed Edge Functions now use bounded request parsing and rate limiting helpers: `supabase/functions/_shared/request.ts` and `supabase/functions/_shared/rate_limit.ts`
- Edge Functions no longer contain `// @ts-nocheck` or TypeScript ignore directives under `supabase/functions`; focused Deno checks pass for the patched function set
- P4.1 tenant isolation testing has started with a fail-fast SQL harness at `supabase/testing/p4_1_rls_storage_isolation.sql` and run notes in `supabase/testing/README.md`
- P4.2 CI security gates are authored in `.github/workflows/security-ci.yml` with local scripts under `scripts/security/`; Deno and RLS lint gates pass locally, while Flutter analyze and forbidden-pattern gates currently fail on existing analyzer debt and unresolved Flutter OpenRouter/public URL/long signed URL findings
- P4.3 security runbooks are authored under `doc/security/`, including incident response for leaked signed URLs, AI key compromise, tenant data exposure triage, storage policy rollback, and release security sign-off
- P4.4 tenant-scoped audit logging is authored in code: `activity_logs` is extended/hardened for redacted append-only audit events, sensitive DB operations have triggers/RPC logging, Edge AI functions record request/denial/failure audit events, and Flutter storage services audit signed URL generation plus storage policy failures
- Supabase migrations through the 2026-05-29 delete cleanup hardening batch have been applied manually in the Supabase SQL Editor; there are no remaining migration-apply tasks in the current backlog
- 2026-05-28 neobank UI correction pass is implemented in Flutter: `debugShowCheckedModeBanner` disabled, floating nav restored as an icon-only capsule, scanner capture actions use existing `CameraUploadService` paths, and dashboard/header/KPI/chart styling now follows a cleaner Sora/DM Mono fintech direction
- 2026-05-28 animation audit and implementation roadmap is authored in `ANIMATION_AUDIT.md`; no motion runtime changes from that roadmap have been implemented yet
- 2026-05-29 FAB regression fix is implemented: Dashboard/Documents now use a route-aware `FloatingActionHub`, Dashboard quick actions are restored, Upload expense opens nested scanner actions, and modal dismissal no longer pops the GoRouter root navigator ([ISSUE-026])
- 2026-05-29 document delete auth flow is corrected in Flutter: delete uses a premium confirmation sheet, typed local-auth results, optional local auth by default when unavailable/not configured, Android/iOS `local_auth` platform prerequisites, safe debug tracing, tenant-scoped verification, and existing storage/RPC deletion paths ([ISSUE-027])
- 2026-05-29 document detail Extracted Products section now uses a premium neobank-style `ExtractedProductsCard` with real `DocumentLineItem` data, Plus Jakarta Sans/Manrope typography, tabular currency figures, skeleton/empty/error states, and no backend/query changes ([ISSUE-028])
- 2026-05-29 dashboard chart floating components are upgraded to a real-data 2x2 `DashboardIntelligenceGrid` with Expenses, Results, Sales, and Documents tiles; queries remain tenant-scoped by `company_id`, reuse the chart period, preserve VAT metadata, and do not touch Supabase schema/extraction/OpenRouter logic
- 2026-05-29 premium FAB UI/UX polish is implemented: `PremiumFAB` is now a circular charcoal `#151515` control with haptics/press scale, and `FloatingActionHub` now presents the existing FAB actions through a blurred, staggered, animated quick-action overlay while preserving all current callbacks/routes/upload flows
- 2026-06-01 premium floating shell navigation is implemented: `AppBottomNav` now renders a glassmorphism four-icon rail (Home, Sales, Docs, Orders) with split blurred pill segments, true center FAB gap, icon-only semantics labels, off-white `#F9F9F9` canvas, and centered existing screen FAB actions; no Supabase, extraction, realtime, auth, storage, or `company_id` logic changed
- 2026-06-02 Review Center / Action Inbox is implemented end-to-end: `review_items` table with tenant RLS, sync RPCs (`sync_review_items_for_company`, `sync_review_items_for_document`), and `resolve_review_item` RPC backed by the existing `record_security_audit_event` audit helper; Flutter feature at `lib/features/review_center/` with model/repository/providers/screen; route `/review-center` wired in GoRouter; dashboard intelligence grid extended with a real "Needs review" tile backed by live `review_items` counts including critical count; realtime subscription invalidates dashboard on `review_items` changes; sync preserves ignored/dismissed status across re-syncs; all actions (retry, resolve, ignore, dismiss) are tenant-scoped and audit-logged; no mock data anywhere in the feature
- 2026-06-03 Documents search bar visual refactor is implemented: `lib/features/documents/presentation/widgets/document_search_bar.dart` now exposes a dedicated `DigitalAtelierSearchBar` while preserving the existing `DocumentSearchBar` public API; the widget keeps the `DocumentsScreen` controller/callback contract unchanged, replaces the old Material decoration shell with a premium pill layout, and adds focus/press micro-interactions without touching search logic, providers, filters, document fetching, extraction, or state management
- 2026-06-03 dashboard intelligence data-chain fix is implemented: `DASHBOARD_INTELLIGENCE_PIPELINE_ANALYSIS.md` documents the extraction-to-dashboard chain; `IntelligenceService` now queries productized line-item/category spend and top products by the selected rolling `ChartPeriod` instead of the hard-coded calendar-month analytics views; dashboard intelligence providers now watch chart period plus tenant-filtered realtime changes on documents, document_items, products, product_prices, and categories; no dashboard UI, extraction, upload, auth, storage, FAB, or navigation code changed ([ISSUE-030])
- 2026-06-04 multi-tenant security audit artifacts are now part of the project record: `MULTITENANT_SECURITY_AUDIT.md` and `MULTITENANT_SECURITY_TEST_PLAN.md` were authored as the canonical audit/test-plan pair, confirming the current highest-priority tenant-isolation gaps before remediation work continues
- 2026-06-04 Phase 2 document-storage hardening has started in production code: fresh preview/open/background-extraction/process-document paths now prefer `file_path` over stored URLs, new document/page metadata writes stop persisting most durable URL fields, and legacy URL fallback remains intentionally alive for older rows during the migration window
- 2026-06-06 extraction finalization UUID failures are fixed in the live Supabase database: `activity_logs`, `documents`, `document_items`, `products`, `providers`, and `supplier_aliases` now use `gen_random_uuid()` on the active extraction path, and `prevent_duplicate_provider()` no longer calls `uuid_generate_v4()` during supplier resolution ([ISSUE-031])
- 2026-06-13 Sales module foundation and Connect POS are implemented and deployed: `supabase/migrations/20260613_sales_module_foundation.sql` adds sales imports/items, POS provider catalog, token-protected POS connections, request tracking, token-free `pos_connection_status`, RLS/FORCE RLS, indexes, triggers, realtime, and `get_sales_summary`; Flutter Sales now has a real dashboard/import/connect flow; `connect-pos` and `disconnect-pos` Edge Functions are deployed to project `qbvfeizmcuctmhrxkvbx` ([ISSUE-032])
- 2026-06-13 Connect POS now uses a country-first, no-fake-integration contract: users choose country, see localized POS options, can configure only Custom POS, can request coming-soon providers, and raw Supabase function 404s are mapped to user-safe copy; the backend derives `company_id` server-side and validates provider/country against `pos_provider_catalog`
- 2026-06-13 Sales import 500 root cause analysis and fix are complete: `SALES_IMPORT_FAILURE_ANALYSIS.md` documents the Flutter upload path, storage path, Edge Function stages, live schema mismatch, and validation checklist; `process-sales-import` now writes `sales_imports.extraction_raw/extraction_clean` instead of a nonexistent `metadata` column, stores item source metadata in `sales_items.metadata` instead of nonexistent `sales_items.source_type`, normalizes unsupported sales channels to `unknown`, flags unsupported PDFs/unclear extractions without fake rows, returns safe structured `{error, stage}` failures, and is deployed as version 2 on project `qbvfeizmcuctmhrxkvbx`; Flutter now invokes the canonical `sales_import_id` contract and no longer overwrites server-side import notes on function responses ([ISSUE-033])
- 2026-06-13 Sales dashboard sync and CRUD fix is complete: `SALES_DASHBOARD_SYNC_AND_CRUD_ANALYSIS.md` documents the canonical data flow and root cause; `process-sales-import` now parses day-first sales report dates before JavaScript fallback and is deployed as version 3; `supabase/migrations/20260613_sales_dashboard_sync_and_crud.sql` is applied to production with corrected summary math, tenant/admin-scoped sales/import/POS RPCs, and a backfill that moved the completed June import out of January; Sales UI now exposes import record management, sale edit/delete, and POS disconnect/delete actions backed by step-up auth and provider invalidation ([ISSUE-034])
- 2026-06-13 Smart POS integration architecture is implemented and deployed: `POS_INTEGRATIONS_SMART_CONNECTION_ANALYSIS.md` records the official-provider research and no-fake-integration strategy; `supabase/migrations/20260613_pos_smart_connection_modes.sql` adds explicit provider capabilities (`connection_mode`, `connection_status`, `has_backend_adapter`, docs/notes), import metadata, `pos_connections.connection_mode`, and a refreshed token-free status view; Flutter Connect POS now groups providers into honest smart options, routes unsupported/native-not-ready providers to provider-prefilled sales report import, and never asks for POS API credentials; `connect-pos` creates import-mode Custom POS connections or request rows only, and `sync-pos-sales` derives company server-side and refuses providers without live adapters ([ISSUE-035])
- 2026-06-13 Sales destructive actions now follow the optional local-auth policy: `sales_screen.dart` calls `StepUpAuthService.requireStepUp(required: false)` for sales import delete, sale delete, POS disconnect, and POS connection delete, so emulator/device local-auth unavailability no longer blocks the already-confirmed tenant-scoped Supabase/RLS delete paths ([ISSUE-036])
- 2026-06-14 Sales delete post-step-up handling is hardened: `SALES_DELETE_FAILURE_ANALYSIS.md` confirms skipped optional step-up is not an error; `SalesRepository` now logs redacted delete RPC stages and maps PostgREST permission/not-found/FK/network failures to safe `SalesDeleteException` messages; `sales_screen.dart` no longer shows raw Supabase delete errors in SnackBars ([ISSUE-036])
- 2026-06-15 owner/manager registration no longer fails with raw `P0001: Unauthorized` after auth signup: `REGISTRATION_UNAUTHORIZED_RPC_ANALYSIS.md` documents the session/RPC/audit-trigger root cause; Flutter now pauses company setup when signup returns no session, resumes after OTP verification when state is preserved, routes authenticated users without a company back to setup, and keeps `CompanyService.createCompany` compatible with the RPC JSON return; `supabase/migrations/20260615_secure_registration_rpc_session_fix.sql` replaces registration RPCs so ownership/membership derives from `auth.uid()`, removes client `p_user_id` authority, revokes anon/PUBLIC execute, and keeps the audit trail intact for pending manager self-requests ([ISSUE-037])
- 2026-06-15 Dashboard Spend by Category is reconnected to selected upload categories: `CATEGORY_INTELLIGENCE_CONNECTION_ANALYSIS.md` documents the upload/state/database/extraction/dashboard trace; `IntelligenceService` now uses the explicit `categories!documents_category_id_fkey` embed for `documents.category_id`, applies `document_date ?? created_at` period matching for document fallback spend, and logs safe per-source row counts/totals instead of swallowing the PostgREST relationship ambiguity into an empty state ([ISSUE-038])
- 2026-06-18 Review Center is restored as a real operational inbox: `REVIEW_CENTER_PIPELINE_ANALYSIS.md` documents the screen/providers/repository/RPC pipeline and live root cause (`sync_review_items_for_company` referenced nonexistent `documents.supplier_name`); `supabase/migrations/20260618_review_center_operational_inbox_fix.sql` fixes the generator, expands real operational review types, forces RLS on `review_items`, adds sales/POS source rules, corrects decimal product-match confidence handling, and the active company now has persisted open items for product matching, price anomalies, failed sales import, and POS setup follow-up ([ISSUE-039])
- 2026-06-19 app boot no longer blocks the Flutter UI on development storage verification: `APP_BOOT_SPLASH_HANG_ANALYSIS.md` traces the boot sequence and proves `main()` awaited `StorageService.verifyStorageConfig()` before `runApp()`, where an auth token refresh could hang after `[StorageService] Auth: session exists`; Flutter now mounts before the storage check, storage/auth calls have timeouts, biometric startup checks are bounded, and router company/pending-approval guards fall back to a recoverable Bootstrap screen instead of indefinite loading ([ISSUE-040])
- 2026-06-19 deferred storage verification no longer performs a client-side startup bucket list: `STORAGE_VERIFICATION_TIMEOUT_ANALYSIS.md` traces the post-splash timeout to `StorageVerify stage=check_bucket`, specifically `POST /storage/v1/object/list/documents` from Flutter; startup verification now returns a typed soft health result, skips broad bucket listing, does not force auth refresh, and leaves document/sales uploads to validate storage on demand with existing tenant-scoped upload errors ([ISSUE-041])
- 2026-06-19 Review Center heavy-use freeze risk is mitigated in Flutter: `APP_PERFORMANCE_FREEZE_ANALYSIS.md` documents emulator/device availability, debug/profile startup findings, live Review Center volume, duplicate checks, indexes, Riverpod/realtime fanout, and the root cause risk; Review Center now debounces realtime bursts, rate-limits automatic screen-entry sync, keeps manual refresh explicit, bounds the initial open-item fetch to 120 rows, and logs safe timing/row counts for fetch/count/sync without changing Supabase schema, RLS, extraction, sales import, bottom nav, or FAB ([ISSUE-042])

### 11.2 Partially Implemented
- Expense tracker aggregation model/service exists (category summaries), UI tracker screen not yet built
- Existing documents uploaded before 2026-04-26 have public (broken) file_url; preview falls back to on-demand signed URL via file_path
- product_prices and product_aliases are populated only for documents processed after the 20260424/20260510 product migrations; older document_items may still have no price history or alias history until reprocessed
- Product UI now expects category names from category_id relations and supplier-aware price history; older rows with sparse product/category linkage will show reduced intelligence until backfilled or reprocessed
- The expense/upload path is non-blocking after submit, but very large PDFs may still feel slow before the expense form opens because the picker currently reads the full file into memory with readAsBytes()
- P3.4 Edge Function rate limiting is instance-local defense-in-depth for Supabase Edge isolates; runtime validation is pending, and a distributed limiter remains a future hardening option if abuse pressure appears across warm isolate boundaries
- P4.1 RLS/storage regression suite is authored but still needs execution against the now-updated Supabase environment
- P4.4 audit logging migration is applied; runtime validation must confirm event creation, redaction, tenant visibility, and blocked direct authenticated writes to `activity_logs`
- Document delete cleanup hardening migration is applied; runtime validation must confirm related-row cleanup, storage handling, and permission-denied behavior in the target environment
- Sales/POS runtime smoke testing is still pending in the app UI after backend validation: verify `/sales`, `/sales/import`, `/sales/connect-pos`, Custom POS import-mode setup, provider-prefilled report import, request persistence for non-live providers, import record edit/delete, sale edit/delete, POS disconnect/delete with optional local-auth unavailable, realtime refresh, and tenant isolation against at least two companies
- Premium motion system is partially implemented locally for dashboard floating components and FAB interactions; the reusable shared motion primitives from `ANIMATION_AUDIT.md` (`AppPressable`, `FadeSlideIn`, `StaggeredList`, `AnimatedValue`, `AnimatedStatusSwitcher`, reduced-motion helpers) are still pending as a consolidation step
- `SECURITY_FIX_IMPACT_ANALYSIS.md` has been authored for the compatibility-first remediation phase, but the current markdown file contains duplicated content and should be cleaned before treating it as a polished artifact
- Document storage hardening is mid-migration: fresh document inserts/background metadata now rely on `file_path` as the durable reference, but runtime validation, bucket privatization, and final retirement of legacy URL fields are still pending

### 11.3 Broken / At Risk
- Extraction architecture mismatch: edge-function invocation still active despite target rule (DEC-006)
- In-app API key handling (if used directly) is insecure for production and must be replaced
- Environment drift risk is reduced after the 2026-05-29 SQL Editor migration batch, but runtime smoke testing is still required to confirm every deployed Edge Function and Flutter query matches the target schema
- Supabase migration history was previously desynchronised (schema_migrations table empty); migrations are now applied manually via SQL Editor, but the duplicate 20260330 local migration conflict still needs cleanup for healthier future CLI workflows
- DEC-006 remains intentionally violated in production: both process-document and recognize-products are still Edge-Function-based, and PROJECT_CONTEXT's extraction target architecture is now stale relative to the deployed system
- P3.5 code is complete and P4.2 now adds CI enforcement for Edge Function `deno check`; a full green CI run is pending because Flutter analyzer debt and security grep findings from earlier phases still need remediation
- Global Supabase CLI is not installed, but `npx supabase` works in this workspace and is linked to production project `qbvfeizmcuctmhrxkvbx`; avoid broad `supabase db push` until older pending local migrations are reconciled
- The `documents` storage bucket remains public today; anonymous object exposure risk is still open until the path-first migration is runtime-validated and the private-bucket cutover is executed
- Multi-tenant audit findings MT-002 to MT-004 are not remediated yet: registration RPCs still trust caller-supplied `p_user_id`, `review_items` still lacks `FORCE ROW LEVEL SECURITY`, and document flows still retain legacy URL fallback for compatibility
- Previously flagged PDF rows that failed during UUID finalization need re-extraction/finalization after the 2026-06-06 supplier UUID fix; the database trigger path is validated, but old flagged document statuses will not self-heal automatically

## 12. Issues Log
### [ISSUE-001] Company not persisted during registration
- Cause: missing/incorrect post-auth insert linkage for tenant membership
- Fix: registration and migration fixes added (including multi-tenant registration hotfix migrations)
- Status: Resolved

### [ISSUE-002] GoRouter warning for complex ExpenseFormArgs extra
- Cause: object passed directly as route extra
- Fix: ExpenseFormArgs serialized with toMap()/fromMap()
- Status: Resolved

### [ISSUE-003] Expense form preview showed only Add Page card
- Cause: selected file not rendered when pages list empty
- Fix: initial page seeding + fallback selected-document thumbnail widget
- Status: Resolved

### [ISSUE-004] categories table missing (PGRST205)
- Cause: migration was not applied in the target Supabase environment at the time
- Fix: graceful fallback in app + migration 20260422 created
- Status: Resolved after migration application

### [ISSUE-005] expenses table missing (PGRST205)
- Cause: migration was not applied in the target Supabase environment at the time
- Fix: submitExpenseFlow fallback to document-only path when expenses table absent
- Status: Resolved after migration application

### [ISSUE-006] PDF extraction failed with edge function 500
- Cause: raw PDF reached server path that cannot process certain PDFs
- Fix: added PDF->PNG conversion in submitExpenseFlow before upload
- Status: Resolved in app code (verify on-device)

### [ISSUE-007] Postgrest 42703: column documents.supplier_name does not exist
- Cause: query selected supplier_name from documents table; column belongs to expenses/extraction payload
- Fix: removed supplier_name from documents select and read it from extraction_clean when updating expense
- Status: Resolved

### [ISSUE-008] Hallucinated supplier names appearing across unrelated documents
- Cause: VLM prompt was permissive; no grounding check; model reused context from previous calls
- Fix: rewrote process-document with strict confidence-schema, OCR transcript grounding validation, confidence threshold (0.3), per-document log isolation, no-signal guard (flags if all key fields null)
- Status: Resolved

### [ISSUE-009] Document detail sheet showed black preview area
- Cause: storage bucket is private; file_url stored as public URL was inaccessible; Supabase Dart SDK createSignedUrl rewrites host causing 404
- Fix: documentPreviewUrlProvider uses raw HTTP getSignedUrl; isPdf extended to check filename extension; StorageService.uploadDocument now generates 1-year signed URL at upload time and stores it as file_url
- Status: Resolved

### [ISSUE-010] PDF preview rendered black via pdfx thumbnail
- Cause: pdfx page.render() returned null/black bytes in the provider; ref.watch inside async FutureProvider broke Riverpod lifecycle
- Fix: replaced broken thumbnail provider with _PdfPreviewCard (tappable) + _PdfViewerPage (fullscreen PdfViewPinch); documentPdfBytesProvider downloads bytes via signed URL on tap
- Status: Resolved

### [ISSUE-011] Extracted fields not showing in document detail (Type: Unknown, empty supplier/total/date)
- Cause: DocumentModel.fromJson did not read extraction_clean fallback; filePath field missing from model; document_number regex ^[A-Z0-9\-\/]{5,}$ rejected valid Spanish invoice formats; confidence threshold 0.5 nulled mid-range VLM scores
- Fix: added filePath to DocumentModel; all 6 extracted fields resolve with extraction_clean fallback; confidence threshold lowered to 0.3; document_number validation relaxed to minimum 2 printable characters
- Status: Resolved

### [ISSUE-012] Preview slow to appear after upload
- Cause: signed URL generated on-demand per view; one extra network round-trip every time detail sheet opens
- Fix: StorageService.uploadDocument generates 1-year signed URL immediately after upload and stores it as file_url; _PreviewSection detects token= in fileUrl and renders Image.network directly with zero extra fetch
- Status: Resolved

### [ISSUE-013] Supplier Intelligence migration failed on apply
- Cause: 20260505_supplier_intelligence.sql attempted an invalid mixed GIN index including uuid columns
- Fix: replaced the broken index strategy with a raw-name GIN index and a separate exact-match btree index on company_id + lower(trim(raw_name))
- Status: Resolved

### [ISSUE-014] Spanish invoice dates were parsed incorrectly by extraction
- Cause: the AI pipeline returned locale-formatted dates that were not normalized before persistence, especially day/month/year Spanish formats
- Fix: added deterministic server-side date normalization in process-document for numeric Spanish formats and Spanish month-name expressions, then redeployed the edge function
- Status: Resolved

### [ISSUE-015] Duplicate invoices could be uploaded and counted twice
- Cause: there was no shared normalization or DB-backed duplicate guard for invoice number + supplier combinations, and analytics queries still counted duplicate documents
- Fix: added normalized duplicate fields, duplicate detection logic in process-document and Flutter upload flow, duplicate-safe analytics filters, duplicate badges/detail UI, and a dedicated duplicate-guard migration
- Status: Resolved in code and migration-backed; runtime duplicate-upload verification still recommended

### [ISSUE-016] Expense uploads stopped turning line items into products
- Cause: _runExtractionForExpense() in lib/providers/documents_provider.dart waited for process-document but never invoked recognize-products, so document_items in that path were never matched or created as products
- Fix: restored recognize-products invocation in the expense upload path and redeployed the recognizer against the new matching pipeline
- Status: Resolved

### [ISSUE-017] Product intelligence migration failed on the linked remote database
- Cause: the remote schema was missing product_prices, lacked uuid_generate_v4() support, and the alias backfill INSERT had a detached ON CONFLICT clause
- Fix: made 20260510_product_intelligence_pipeline.sql self-healing (creates product_prices if absent, uses pgcrypto/gen_random_uuid(), and adds valid conflict-safe alias backfill + RLS policy creation)
- Status: Resolved

### [ISSUE-018] PDF uploads still blocked the expense form after image uploads had been made non-blocking
- Cause: submitExpenseFlow() and uploadDocument() still awaited client-side PDF conversion (pdfx render + merge) before returning to the UI, so the expense form spinner stayed visible until preprocessing/extraction finished
- Fix: split the flow into fast UI phase (upload raw file + insert documents row + return immediately) and detached background phase (_processDocumentBackground) that performs PDF preprocessing, storage replacement, extraction, timeout handling, and flagged fallback after navigation
- Status: Resolved

### [ISSUE-019] Background PDF preprocessing failed and flagged documents immediately after the async refactor
- Cause: pdfx rendering was moved into compute(), but pdfx uses a Flutter MethodChannel (io.scer.pdf_renderer) and cannot run inside a background isolate
- Fix: moved PdfDocument.openData()/page.render() back onto the main isolate inside the detached background task, kept page limiting (max 3 pages), and preserved async/non-blocking UX by running all PDF work only after the UI has already navigated away
- Status: Resolved

### [ISSUE-020] Expense success snackbar overflowed on narrow screens
- Cause: the snackbar content row in expense_form_screen.dart used an unconstrained Text beside an icon, so long success messages overflowed horizontally
- Fix: wrapped snackbar text in Expanded and added maxLines/ellipsis handling
- Status: Resolved

### [ISSUE-021] process-document returned FunctionException during PDF background extraction
- Cause: the rewritten edge function attempted to update documents.supplier_name, but that column does not exist on the documents table; Flutter also collapsed non-2xx function responses to a generic FunctionException without logging the real payload
- Fix: removed the invalid supplier_name document-column write from supabase/functions/process-document/index.ts, improved lib/services/extraction_service.dart to log and rethrow the real FunctionException details, and updated lib/services/background_extraction_service.dart to persist the full exception text in documents.notes when flagging
- Status: Resolved in code and redeployed; verify on-device after applying pending schema migrations

### [ISSUE-022] Document type detection was unreliable for Factura vs Albaran
- Cause: the VLM prompt did not force classification strongly enough, raw OCR text was not persisted for deterministic validation, and the pipeline trusted AI document_type too much when confidence was weak
- Fix: rewrote the process-document prompt for strict classification-first extraction, added raw_text + ai_document_type to extraction_clean, added deterministic server-side and Dart-side document-type heuristics, created secure fallback Edge Function supabase/functions/classify-document-type/index.ts for low-confidence text-only classification, and redeployed both functions
- Status: Resolved in code and redeployed; verify on-device with known Factura and Albaran samples

### [ISSUE-023] All dashboard expenses showed "Uncategorized" despite category picker working
- Cause: Three-part bug in the category pipeline:
  1. lib/providers/documents_provider.dart submitExpenseFlow() inserted into documents table WITHOUT including category_id — user-selected category was only written to expenses.category_id, never to documents.category_id
  2. lib/features/expenses/data/services/expense_service.dart fetchDocumentCategorySummaries() queried documents.category_id which was always null, so 100% of spend landed in "Uncategorized"
  3. lib/providers/documents_provider.dart _syncExpenseAfterExtraction() would have overwritten user-selected expenses.category_id with any AI-derived documents.category_id (no user-wins guard)
- Fix:
  1. Added `if (categoryId != null) 'category_id': categoryId` to the documents.insert() in submitExpenseFlow() — category_id now written to both documents and expenses at upload time
  2. Changed fetchDocumentCategorySummaries() select to `'total_amount, category_id, expenses(category_id)'` — uses expenses.category_id (user's choice) with documents.category_id as fallback; fixes old records uploaded before this fix
  3. In _syncExpenseAfterExtraction() added a pre-read of expenses.category_id; AI-derived category is only applied if the expense has no existing category (user-selected category always wins)
- Files changed: lib/providers/documents_provider.dart, lib/features/expenses/data/services/expense_service.dart
- Status: Resolved

### [ISSUE-024] Expenses screen showed "No expenses yet" / empty category breakdown
- Cause: `fetchDocumentCategorySummaries()` in `lib/features/expenses/data/services/expense_service.dart` used `.select('total_amount, category_id, expenses(category_id)')`. PostgREST detected two FK paths between documents and expenses (`documents.expense_id → expenses.id` AND `expenses.document_id → documents.id`), threw PGRST200 ambiguity error which was caught silently, and returned `[]`
- Fix: changed the embed to `expenses!expense_id(category_id)` — pins the forward FK `documents.expense_id → expenses.id` unambiguously; also fixed the Dart cast from List to single Map
- Files changed: `lib/features/expenses/data/services/expense_service.dart`
- Status: Resolved

### [ISSUE-025] Category not propagated to sibling documents from the same supplier
- Cause: When a user categorizes one document from supplier X, no mechanism existed to apply that category to other documents from the same supplier. Three structural gaps:
  1. `process-document` edge function never reads or sets `category_id`
  2. `auto_resolve_supplier` trigger resolves `provider_id` on completion but ignores category
  3. At upload time the user's `category_id` is set but `provider_id` is still NULL — so sibling lookup was impossible at that moment
- Fix: Created `supabase/migrations/20260517b_category_propagation.sql` with:
  1. `sync_provider_category_trigger_fn()` — AFTER UPDATE OF `category_id`/`provider_id` on documents: Case A pushes a newly-set category to all uncategorized siblings; Case B pulls confirmed category from siblings when `provider_id` just resolved
  2. `backfill_provider_categories(p_company_id UUID)` RPC — idempotent, tenant-safe (requires company_id + membership check for authenticated callers; skips check for postgres/supabase_admin superuser roles); callable from Flutter anytime
  3. Runs `SELECT backfill_provider_categories()` at migration time to fix all existing data immediately
- Status: Resolved; migration applied manually in Supabase SQL Editor on 2026-05-29, runtime propagation verification still recommended

### [ISSUE-026] FAB upload/gallery actions could black-screen by popping the root route
- Cause: `ScannerActionSheet` was shown on the nearest navigator but dismissed with `Navigator.of(parentContext, rootNavigator: true).pop()`, which could pop the GoRouter root route instead of the sheet. Dashboard quick actions were also removed during the scanner-first rewrite.
- Fix: Added `lib/shared/fab/` typed route-aware action hub (`AppFabAction`, action groups/registry/scanner actions, `FloatingActionHub`); Dashboard now restores Upload expense, Expense tracker, Providers, Products, Orders, and Documents actions; Upload expense opens nested Upload file/Camera/Photo library/Manually actions; Documents opens directly to capture actions. Hardened legacy scanner sheet to dismiss with the sheet context before calling `CameraUploadService`.
- Status: Resolved in code; verify with a fresh app restart on device/emulator

### [ISSUE-027] Document delete showed misleading authentication-cancel message
- Cause: `BiometricService.authenticate()` returned raw `bool` and collapsed user cancellation, auth unavailable/not configured, failed auth, and platform exceptions into `false`. `StepUpAuthService.requireStepUp()` converted every false result into `Authentication was cancelled. No changes were made.`, so delete returned before Supabase and showed the wrong message.
- Fix: Added `lib/core/security/local_auth_service.dart` with typed `LocalAuthResult`; refactored `StepUpAuthService` to distinguish cancelled/failed/unavailable/notConfigured/error/skipped; document delete now treats local auth as optional by default when unavailable/not configured; replaced document delete alert with a premium confirmation sheet; added safe `[DELETE]` tracing; updated `DocumentDeleteService` to separate auth, permission, storage, and Supabase errors; added `supabase/migrations/20260529_document_delete_cleanup_hardening.sql` to extend tenant-scoped cleanup while preserving `delete_document_cascade(uuid, uuid)`.
- Status: Resolved in Flutter code; DB cleanup hardening migration applied manually in Supabase SQL Editor on 2026-05-29; on-device/runtime delete matrix still recommended

### [ISSUE-028] Extracted Products detail section looked like an old table
- Cause: `DocumentDetailSheet` rendered extracted line items through a private `_LineItemsTable` with a gray header bar, small 12px typography, hard row borders, raw decimal prices, and no premium financial hierarchy.
- Fix: Added `lib/features/documents/presentation/widgets/extracted_products_card.dart` and integrated it into `DocumentDetailSheet`; the new card maps real `DocumentLineItem` data, uses Plus Jakarta Sans/Manrope typography, tabular figures, European currency formatting, soft row surfaces, skeleton/empty/error states, and accessible row semantics.
- Status: Resolved; UI-only change with no Supabase, extraction, edit, delete, OpenRouter, product matching, or `company_id` logic changes

### [ISSUE-029] Documents search bar did not match the Digital Atelier visual spec
- Cause: `DocumentSearchBar` still used a legacy Material `TextField` decoration shell (`prefixIcon`/padding/shadow mix) that did not match the required neobank pill geometry, spacing, typography, or interaction model, even though the underlying search wiring already worked.
- Fix: Rebuilt `lib/features/documents/presentation/widgets/document_search_bar.dart` as a dedicated `DigitalAtelierSearchBar`, kept `DocumentSearchBar` as the public wrapper, preserved the existing `TextEditingController` and `onChanged` callback from `DocumentsScreen`, replaced the visual layer with an explicit icon + spacing + expanded `TextField` row, and added subtle focus/press animation states.
- Status: Resolved; focused `flutter analyze --no-fatal-infos lib/features/documents/presentation/widgets/document_search_bar.dart` passed

### [ISSUE-030] Dashboard Spend by Category and Top Products showed empty despite extracted documents/products
- Cause: Dashboard intelligence widgets were still provider-connected, but their data layer read `v_category_intelligence` and `v_top_products_by_spend`, whose `current_month_spent` fields are hard-coded to calendar month via `date_trunc('month', CURRENT_DATE)`. The working dashboard expense chart/grid use rolling `ChartPeriod.oneMonth` (last 30 days), so valid prior-calendar-month invoice/product rows could appear in total expenses while category/top-product cards stayed empty. Spend by Category was also coupled to `documents.category_id` instead of the productized `document_items -> product_prices -> products.category_id -> categories` chain, and the intelligence providers did not watch product/product_price/document_item realtime changes.
- Fix: Added `DASHBOARD_INTELLIGENCE_PIPELINE_ANALYSIS.md`; updated `lib/services/intelligence_service.dart` so category and top-product dashboard queries are tenant-scoped, period-aware, and use product price/category relationships with a non-double-counting document-category fallback; updated `lib/features/dashboard/providers/intelligence_providers.dart` so category/top-product providers watch `chartPeriodProvider` and a tenant-filtered dashboard intelligence realtime stream across documents, document_items, products, product_prices, and categories.
- Status: Resolved in code; focused `flutter analyze --no-fatal-infos lib/services/intelligence_service.dart lib/features/dashboard/providers/intelligence_providers.dart` passed; runtime verification with real uploaded invoice/product/category data remains recommended

### [ISSUE-031] PDF extraction completed items but failed parent finalization with `uuid_generate_v4()`
- Cause: After the first UUID-default fix, document item extraction was working but the final parent `documents.status = completed` update fired `auto_resolve_supplier_trigger_fn()`. That trigger calls `resolve_supplier()` under `SET search_path TO public`; when a new supplier/provider was needed, `providers` insert fired `prevent_duplicate_provider()`, which still called unqualified `uuid_generate_v4()`. `providers.id` and `supplier_aliases.id` also still had `uuid_generate_v4()` defaults.
- Fix: Authored `REMAINING_UUID_GENERATION_FAILURE_ANALYSIS.md`; added and applied `supabase/migrations/20260606_fix_supplier_uuid_generation.sql`, changing `providers.id` and `supplier_aliases.id` defaults to `gen_random_uuid()` and replacing both `uuid_generate_v4()` calls inside `prevent_duplicate_provider()` with `gen_random_uuid()`.
- Status: Resolved in the live database; rollback reproduction of the exact document finalization path now succeeds and returns a `provider_id`; re-extract previously flagged documents so their parent status/notes are refreshed

### [ISSUE-032] Connect POS exposed raw missing-function errors and implied unsupported integrations
- Cause: Flutter called `connect-pos` directly from the old dropdown screen, the function was not deployed in the linked Supabase project, and the old function contract trusted client-supplied `companyId` and inserted a pending connection for any provider. This could surface raw Supabase 404/function errors and make unavailable POS integrations look operational.
- Fix: Authored `POS_CONNECTION_ARCHITECTURE_ANALYSIS.md`; added a POS provider catalog/request schema to `20260613_sales_module_foundation.sql`; rebuilt Connect POS as a country-first flow; changed Flutter to call `connect-pos` with `country_code` + `provider`; added friendly `PosConnectionResult`/exception handling; rewrote `connect-pos` to derive active company server-side, validate provider/country from `pos_provider_catalog`, create only custom pending-configuration records, and save coming-soon provider requests without faking success; deployed `connect-pos` and `disconnect-pos` via `npx supabase functions deploy`.
- Status: Resolved in code and deployed to production project `qbvfeizmcuctmhrxkvbx`; remote verification confirms both functions are `ACTIVE`, `pos_provider_catalog` contains 15 providers, and `pos_connection_status` exposes token-free connection columns. Runtime app smoke testing remains recommended.

### [ISSUE-034] Completed Sales imports did not update Sales/Main dashboard revenue and lacked edit/delete/manage actions
- Cause: The import wrote canonical `sales` and `sales_items` rows, but `process-sales-import` used JavaScript `Date.parse()` for numeric report dates. The live June report values `01/06/26` and `13/06/26` were normalized into January (`2026-01-06`), while both Sales and Main dashboards filter `sales.sale_date` for the current June period. UI rows for imports and POS connections were static, and POS disconnect trusted a client `companyId`.
- Fix: Authored `SALES_DASHBOARD_SYNC_AND_CRUD_ANALYSIS.md`; patched `process-sales-import` with deterministic day-first numeric date parsing; deployed `process-sales-import` version 3; applied `supabase/migrations/20260613_sales_dashboard_sync_and_crud.sql` with summary `SUM(transaction_count)` math, tenant/admin-scoped `update_sales_record`, `delete_sales_record`, `delete_sales_import`, and `delete_pos_connection` RPCs, helper backfill logic, and corrected the affected completed import to `period_start=2026-06-01`, `period_end=2026-06-13`, `sales.sale_date=2026-06-13`; hardened `disconnect-pos` to derive company from the connection row, require owner/admin, clear stored POS tokens, and return safe errors; added Sales repository/provider/UI support for import management, sale edit/delete, POS disconnect/delete, `sales_items` realtime, dashboard invalidation, and step-up auth actions.
- Status: Resolved in code, database, and deployed functions; live direct aggregate for company `e70aabbf-679d-4270-aaf6-bb8a8c25babe` now returns June gross `42564.70`, net `4256.01`, tax `46820.71`, transaction count `1`, and January zero. Focused Flutter analyzer and Deno checks pass. Runtime app smoke testing remains recommended for destructive actions and cross-tenant denial.

### [ISSUE-035] POS provider catalog still looked like integrations even though no native adapters exist
- Cause: Provider definitions and the live catalog could only express old `status`/`connection_type` values, and Flutter showed a flat provider list with request-style CTAs. The backend had no native provider adapters, `connect-pos` created pending custom credential records or request rows only, and `sync-pos-sales` accepted a client-supplied `companyId` before inserting placeholder sync jobs.
- Fix: Authored `POS_INTEGRATIONS_SMART_CONNECTION_ANALYSIS.md` before coding; added `supabase/migrations/20260613_pos_smart_connection_modes.sql` with provider capability fields, import metadata, `pos_connections.connection_mode`, and token-free view refresh; updated Flutter provider definitions and Connect POS UI to separate live adapter readiness from official API availability, make report import the primary fallback, and pass provider context into `ImportSalesScreen`; rewrote `connect-pos` to create only import-mode Custom POS connections or safe request rows with import fallback; hardened `sync-pos-sales` to derive active company server-side, verify the connection belongs to that tenant, and refuse providers with `has_backend_adapter=false`.
- Status: Resolved in code and deployed to project `qbvfeizmcuctmhrxkvbx`; live catalog verification shows all named providers have `has_backend_adapter=false`, Custom POS is `connection_mode='custom'`/`connection_status='import_only'`, and every provider supports file import fallback. Focused Flutter analyzer and Deno checks pass. Runtime app smoke testing remains recommended.

### [ISSUE-036] Sales delete/POS actions were misdiagnosed at the optional step-up log and exposed raw post-step-up errors
- Cause: Sales/POS destructive actions originally needed optional local auth for emulator/device-unavailable cases; after that fix, the warning `Step-up skipped (local auth unavailable, not required) for delete_sales_data` became an allowed pass-through, not an error. The remaining failure risk was after step-up: repository delete RPCs had no stage logging or safe PostgREST mapping, and `sales_screen.dart` displayed raw `$error` strings if permission, not-found, FK, or network failures occurred.
- Fix: Authored `SALES_DELETE_FAILURE_ANALYSIS.md`; confirmed live `sales`/`sales_items` were empty while failed `sales_imports` remained, and rollback-tested `delete_sales_import(...)` successfully as the live owner. Kept `requireStepUp(required: false)`, left RLS/RPC hard-delete semantics intact, added redacted delete-stage logging and safe `SalesDeleteException` mapping in `SalesRepository`, and changed Sales delete SnackBars to show friendly messages instead of raw Supabase errors.
- Status: Resolved in Flutter code; focused `flutter analyze lib/features/sales/data/repositories/sales_repository.dart lib/features/sales/presentation/screens/sales_screen.dart` passes. Runtime smoke testing remains recommended for owner/admin success, non-admin denial, unavailable-local-auth emulator path, dashboard refresh, and failed-import delete.

### [ISSUE-037] Owner registration failed after auth signup with `P0001: Unauthorized`
- Cause: Email-confirmation signup created `auth.users` and a profile but returned no authenticated session, while `RegistrationService.registerAsOwner()` immediately called `create_company_with_owner`. The live top-level RPC still trusted client `p_user_id` and did not itself raise `Unauthorized`; the insert into `company_users` fired `audit_company_users_sensitive_changes()`, which called `record_security_audit_event()`, where `auth.uid()` was null and raised `Unauthorized`, rolling back company/member/profile-current-company setup. Manager self-registration had the same session-timing and client-user-id authority risk.
- Fix: Authored `REGISTRATION_UNAUTHORIZED_RPC_ANALYSIS.md`; added safe signup session logs; changed Flutter registration to return an email-verification-pending result instead of calling RPCs with no session; after OTP verification, preserved registration state calls the secure setup RPC; authenticated users without a company route back to setup; updated the secondary `CompanyService.createCompany` caller to parse the secure RPC JSON result; added `supabase/migrations/20260615_secure_registration_rpc_session_fix.sql` so `create_company_with_owner` and `join_company_as_manager` derive `v_user_id := auth.uid()`, remove `p_user_id`, upsert missing profiles, revoke anon/PUBLIC execute, and keep a narrow audit allowance for pending manager self-access requests.
- Status: Resolved in Flutter code and applied to linked Supabase project `qbvfeizmcuctmhrxkvbx`; live verification shows registration RPCs have no `p_user_id`, `search_path=public, auth`, only authenticated/postgres/service_role EXECUTE grants, anon execution denied with `42501`, and rollback-only authenticated owner setup creates the company/member/profile chain inside the transaction then rolls back. Focused analyzer has no Dart errors; existing style/info warnings remain in the registration slice. Runtime owner/manager signup smoke testing remains recommended.

### [ISSUE-038] Dashboard Spend by Category returned empty despite selected upload categories
- Cause: Upload flow stored selected category IDs correctly in `documents.category_id` and `expenses.category_id`, and `process-document` preserved `documents.category_id`. The dashboard source was `IntelligenceService.fetchCategoryIntelligence`, which queried `documents` with an ambiguous PostgREST embed `categories(...)`. Live schema has both `documents.category_id` and `documents.ai_category_id` foreign keys to `categories`, so PostgREST returned `PGRST201`/HTTP 300 Multiple Choices. The service caught the error and returned `[]`, causing `No categorised expenses this month.` despite live current-period categorized documents.
- Fix: Authored `CATEGORY_INTELLIGENCE_CONNECTION_ANALYSIS.md`; changed the document fallback select to `categories!documents_category_id_fkey(...)`; preserved the canonical category spend logic of product-level `product_prices`/`products.category_id` first and document-level `documents.category_id` fallback; added exact `document_date ?? created_at` range matching for fallback rows; added safe `[CategoryIntelligence]` logs with company ID, periods, source table, row counts, totals, and errors.
- Status: Resolved in Flutter code; live investigation confirmed current-period categorized documents exist for company `e70aabbf-679d-4270-aaf6-bb8a8c25babe` (Raw Materials `808.16`, Drinks `1075.85` under current filters), and focused `flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/intelligence_service.dart` passes. Runtime dashboard smoke testing remains recommended after a real Drinks upload/extraction.

### [ISSUE-039] Review Center showed “All clear” while real operational signals existed
- Cause: Review Center correctly read only `review_items`, but live `review_items` was empty because `public.sync_review_items_for_company(uuid)` crashed before insertion with `ERROR 42703: column d.supplier_name does not exist`. The stale sync function also lacked sales/POS generation and used a product-match confidence threshold that treated decimal scores like `0.93` as lower than `75`, which would overcount high-confidence matches.
- Fix: Authored `REVIEW_CENTER_PIPELINE_ANALYSIS.md`; added and applied `supabase/migrations/20260618_review_center_operational_inbox_fix.sql` to remove nonexistent `documents.supplier_name` references, use live schema fields (`normalized_supplier`, extraction JSON, live sales/POS columns), expand `review_items_type_check` for real operational types, force RLS on `review_items`, generate rows from failed sales imports and POS setup/connection issues, and correct product confidence handling for both decimal and percentage score scales. Flutter Review Center now recognizes sales/POS/price variation/baseline review types, filters Sales/POS/Prices separately, counts AI/price groups from type helpers, routes Sales/POS items to the right app surfaces, and shows sync errors instead of a misleading empty state.
- Status: Resolved in code and applied to linked Supabase project `qbvfeizmcuctmhrxkvbx`; rollback and persisted sync validation for company `e70aabbf-679d-4270-aaf6-bb8a8c25babe` generated `28` open real items: `23` product-match reviews, `2` price anomalies, `1` failed sales import, and `2` POS setup follow-ups. Unauthenticated sync is denied with `42501`. Focused Flutter analyzer passes for the modified Review Center files.

### [ISSUE-040] App stayed on native Flutter splash after install/run
- Cause: `main()` awaited the development-only `StorageService.verifyStorageConfig()` before calling `runApp()`. The verifier called `_resolveAccessToken()`, which awaited Supabase `auth.refreshSession()` for near-expired/stale sessions without a timeout, then performed a storage bucket HTTP check without a timeout. The observed logs stopped at `[StorageService] Auth: session exists` and `supabase.auth: INFO: Refresh session`, before the `[BOOT] before runApp` stage could be reached, so no Flutter UI was mounted.
- Fix: Authored `APP_BOOT_SPLASH_HANG_ANALYSIS.md`; changed `main.dart` to call `runApp()` immediately after env + Supabase initialization, then start storage verification after the first frame with an 8-second timeout and safe redacted warning logs. Added storage auth/HTTP timeouts to `StorageService`, bounded auth biometric startup probes, bounded company/pending-approval Supabase queries, and added a `/bootstrap-recovery` route with Retry and Sign out actions for route-guard timeout/failure.
- Status: Resolved in Flutter code; focused analyzer passes for `lib/main.dart`, `lib/services/storage_service.dart`, `lib/core/router/app_router.dart`, `lib/providers/company_provider.dart`, and `lib/providers/auth_provider.dart`; analysis/context markdown diagnostics are clean. Android emulator smoke test with an existing session reproduced the storage verification timeout after mount: logs reached `[BOOT] before runApp`, `[BOOT] after runApp`, GoRouter initialized `/sign-in`, and only then deferred storage verification timed out safely after 8 seconds.

### [ISSUE-041] Deferred storage verification timed out after Flutter mounted
- Cause: After the splash fix, the remaining timeout came from deferred `StorageService.verifyStorageConfig()`, not app boot. Temporary stage instrumentation proved `_resolveAccessToken()` completed and the slow step was `StorageVerify stage=check_bucket`: Flutter posted to `/storage/v1/object/list/documents` as a client-side root object-list probe. For a private multi-tenant bucket, that probe is not a reliable or necessary startup check and can be slow, denied, or policy-dependent even when tenant-scoped uploads are the correct validation path.
- Fix: Authored `STORAGE_VERIFICATION_TIMEOUT_ANALYSIS.md`; converted `verifyStorageConfig()` to return `StorageHealthResult`/`StorageHealthStatus`; removed startup auth-token resolution, forced refresh, and the client-side bucket object-list HTTP call; changed deferred startup handling to log typed debug/status output instead of `[BOOT] Deferred storage verification failed` warnings. Real `uploadDocument()` and `uploadSalesImport()` continue using authenticated tenant-scoped paths and existing explicit upload error mapping.
- Status: Resolved in Flutter code; focused analyzer passes for `lib/main.dart` and `lib/services/storage_service.dart`. Android emulator smoke test with an existing session showed `[StorageVerify] stage=start`, auth session present, `stage=check_policy`, `stage=complete`, `Startup bucket listing skipped; uploads validate storage on demand.`, and `[BOOT] after deferred verifyStorageConfig status=skipped stage=complete` with no timeout or bucket-check warning.

### [ISSUE-042] Review Center could freeze under heavy sync/realtime load
- Cause: `APP_PERFORMANCE_FREEZE_ANALYSIS.md` found no live duplicate-row issue: active company Review Center data had `28` open rows, `28` distinct sources, zero duplicate groups, a unique `(company_id, review_type, source_table, source_id)` constraint, and supporting indexes. The app-side risk was a sync/realtime/provider burst: opening Review Center auto-ran sync, sync invalidated item/count providers, the sync RPC could update rows and emit realtime events, realtime emitted once per payload without debounce, and item/count providers refetched unbounded open rows.
- Fix: Review Center now logs safe fetch/count/sync timings, bounds the initial open-item fetch to `120`, debounces Review Center realtime emissions by `600ms`, removes the sync provider watch from `build`, rate-limits screen-entry auto-sync with a `2` minute cooldown, and keeps pull-to-refresh as an explicit forced sync. No database schema, RLS, sales import, extraction, OpenRouter/VLM, bottom nav, or FAB code was changed.
- Status: Resolved in Flutter code for the identified app-side burst risk; focused analyzer passes for `lib/features/review_center/data/repositories/review_center_repository.dart`, `lib/features/review_center/presentation/providers/review_center_providers.dart`, and `lib/features/review_center/presentation/screens/review_center_screen.dart`. Patched Android profile run builds, installs, launches, and exposes DevTools, while still showing emulator startup skipped-frame logs (`Skipped 275 frames`), so separate startup/emulator profiling remains recommended if startup jank continues.

## 13. Recent Changes
### 2026-06-19 — Review Center heavy-use freeze mitigation
- Created `APP_PERFORMANCE_FREEZE_ANALYSIS.md` before performance code changes, documenting tested scenarios, unavailable physical/iOS targets, Android emulator debug/profile evidence, live Review Center data volume, duplicate checks, schema/index state, Riverpod/realtime fanout, main-isolate risks, root cause, minimal safe fix, and validation checklist.
- Confirmed live Review Center data does not support a duplicate-data root cause: active company had `28` open review items, `28` distinct sources, zero duplicate groups, and an existing unique source constraint plus supporting indexes.
- Updated Review Center repository/provider/screen code so screen-entry auto-sync is cooldown-gated, realtime bursts are debounced, the initial open-item fetch is bounded to `120`, manual pull-to-refresh still forces sync, and safe timing/row-count logs exist for fetch/count/sync.
- Validation completed: focused `flutter analyze lib/features/review_center/data/repositories/review_center_repository.dart lib/features/review_center/presentation/providers/review_center_providers.dart lib/features/review_center/presentation/screens/review_center_screen.dart` passes; Android profile run with the patched app builds, installs, launches, and exposes DevTools. The emulator still logs a startup skipped-frame burst, which is tracked separately from the Review Center burst fix.

### 2026-06-19 — Storage verification timeout cleanup
- Created `STORAGE_VERIFICATION_TIMEOUT_ANALYSIS.md` before coding, tracing `_startDeferredStartupChecks`, `verifyStorageConfig`, `_resolveAccessToken`, the exact object-list endpoint, auth-refresh risk, client permissions, root cause, minimal safe fix, files to modify/avoid, and validation checklist.
- Added temporary verifier stage instrumentation and confirmed on the Android emulator that `resolve_token` completed quickly while `check_bucket` timed out on the Flutter client-side `POST /storage/v1/object/list/documents` startup probe.
- Updated `lib/services/storage_service.dart` so `verifyStorageConfig()` returns `StorageHealthResult`/`StorageHealthStatus`, avoids forced token refresh, skips startup bucket listing, and reports that uploads validate storage on demand.
- Updated `lib/main.dart` so deferred startup checks consume the typed health result and no longer log scary warning stack traces for expected soft health outcomes.
- Validation completed: focused `flutter analyze lib/main.dart lib/services/storage_service.dart` passes with no issues; emulator startup reaches Flutter/GoRouter normally and logs `status=skipped stage=complete` for storage health with no timeout, no `check_bucket`, and no `[StorageService] Bucket check error`.

### 2026-06-19 — App boot splash hang fix
- Created `APP_BOOT_SPLASH_HANG_ANALYSIS.md` before coding, tracing `main()`, every awaited future before `runApp()`, storage verification, Supabase auth refresh, GoRouter redirects, company/profile resolution, provider loading risks, exact stop stage, root cause, minimal safe fix, files to modify/avoid, and validation checklist.
- Confirmed the observed logs stop inside development storage verification before `[BOOT] before runApp`, specifically after `_resolveAccessToken()` starts Supabase session refresh from `StorageService.verifyStorageConfig()`.
- Updated `lib/main.dart` so `runApp(const ProviderScope(child: HospiDashApp()))` happens before storage verification; the debug storage check now starts after the first frame, has an 8-second timeout, and logs redacted warnings without blocking UI mount.
- Updated `lib/services/storage_service.dart` with bounded auth refresh, upload, signed URL, delete, sales import upload, and debug bucket-check HTTP calls so storage/network delays cannot hang boot or upload flows indefinitely.
- Updated `lib/providers/auth_provider.dart`, `lib/providers/company_provider.dart`, and `lib/core/router/app_router.dart` so biometric startup probes, company/pending-approval queries, and redirect futures have controlled timeouts; route-guard failures go to `/bootstrap-recovery` with Retry and Sign out actions.
- Validation completed: focused `flutter analyze lib/main.dart lib/services/storage_service.dart lib/core/router/app_router.dart lib/providers/company_provider.dart lib/providers/auth_provider.dart` passes with no issues; `APP_BOOT_SPLASH_HANG_ANALYSIS.md` and `PROJECT_CONTEXT.md` diagnostics are clean; `flutter run --dart-define-from-file=env/dev.json -d emulator-5554` reached `[BOOT] before runApp`, `[BOOT] after runApp`, GoRouter route initialization, and `/sign-in` before deferred storage verification timed out safely after 8 seconds.

### 2026-06-18 — Review Center operational inbox fix
- Created `REVIEW_CENTER_PIPELINE_ANALYSIS.md` before coding, tracing the Review Center route, widget tree, providers, repository, `review_items` table, realtime subscription, sync RPC, filters/counts, source signal map, root cause, minimal safe fix, files to modify/avoid, and validation checklist.
- Reproduced the live failure as the active company owner in a rollback transaction: `sync_review_items_for_company` raised `42703` on nonexistent `documents.supplier_name`, leaving `review_items` empty even though real price anomaly, product-match, sales import, and POS setup signals existed.
- Added and applied `supabase/migrations/20260618_review_center_operational_inbox_fix.sql`: expanded the review type constraint, forced RLS on `review_items`, rewrote `sync_review_items_for_company` against live columns, preserved ignored/dismissed rows on resync, auto-resolves stale source conditions, adds failed sales import and POS setup/connection generation, and fixes product-match confidence thresholds for decimal scores.
- Updated Review Center Flutter model/repository/providers/screen so new operational types parse and render, filters include Prices/Sales/POS, count groups include product/supplier/sales AI review and price variation/baseline review, and the screen does not show “All clear” while sync is loading or failed.
- Validation completed: migration file applied cleanly to the linked project; rollback and persisted sync generated `28` open real review items for the active company (`23` product-match, `2` price anomaly, `1` failed sales import, `2` POS setup); unauthenticated sync is denied with `42501`; focused Flutter analyzer passes for the modified Review Center files.

### 2026-06-15 — Category intelligence connection fix
- Created `CATEGORY_INTELLIGENCE_CONNECTION_ANALYSIS.md` before coding, tracing the category model, upload dropdown, `ExpenseFormState.categoryId`, `submitExpenseFlow` payload, `documents.category_id`/`expenses.category_id` persistence, extraction finalization, dashboard intelligence source, date filters, RLS posture, root cause, minimal fix, and validation checklist.
- Confirmed live categories are company-scoped and active for company `e70aabbf-679d-4270-aaf6-bb8a8c25babe`; `No category` is represented as null in Flutter, not as a category row.
- Confirmed recent uploads store selected categories in `documents.category_id`; `process-document` does not update `category_id`, so extraction preserves user-selected categories.
- Reproduced the dashboard failure through PostgREST: `documents` embeds to `categories(...)` return `PGRST201` because both `documents_category_id_fkey` and `documents_ai_category_id_fkey` exist.
- Updated `lib/services/intelligence_service.dart` so document fallback spend embeds `categories!documents_category_id_fkey(...)`, uses `document_date ?? created_at` for selected-period matching, and logs safe source row counts/totals/errors for category intelligence.
- Validation completed: explicit FK-qualified embed no longer triggers the ambiguity, live SQL shows eligible categorized spend, VS Code diagnostics are clean for the analysis and service files, and focused Flutter analyzer passes for `lib/services/intelligence_service.dart`.

### 2026-06-15 — Registration Unauthorized RPC/session fix
- Created `REGISTRATION_UNAUTHORIZED_RPC_ANALYSIS.md` before coding, tracing Flutter signup, Supabase Auth session timing, live RPC definitions, audit-trigger side effects, `auth.uid()` visibility, profile/company dependencies, exact root cause, minimal safe fix, files to modify/avoid, and validation checklist.
- Confirmed the failed auth user `433b2cd8-768d-4cfa-ae08-76da8faf2190` exists, is not confirmed, has a profile, and has no `company_users` row; the linked DB does not expose `auth.config`, but the failed user state and existing auth wrapper prove email-verification/no-session signup behavior.
- Updated `lib/services/registration_service.dart` to log user/session/currentUser/access-token presence safely, avoid token logging, stop calling registration RPCs when `signUp` returns no session, map Unauthorized to setup-session copy, and call secure RPCs without `p_user_id`.
- Updated registration result/provider/UI/OTP/router flow so signup with no session routes to OTP/email verification, then completes preserved owner or manager setup once a session exists; authenticated users with no company and no pending manager membership route to company setup rather than a broken dashboard; the secondary `CompanyService.createCompany` caller now reads `company_id` from the RPC JSON result.
- Added and applied `supabase/migrations/20260615_secure_registration_rpc_session_fix.sql`: `create_company_with_owner` and `join_company_as_manager` now derive user identity from `auth.uid()`, use `SECURITY DEFINER SET search_path = public, auth`, upsert profile/current company safely, revoke anon/PUBLIC execute, and preserve audit logging including pending manager self-access requests.
- Validation completed: live definitions/grants verified, anon execution denied with `42501`, rollback-only authenticated owner setup succeeded inside the transaction and rolled back, and focused Flutter analyzer reports no errors though existing info/warning lints remain.

### 2026-06-14 — Sales delete post-step-up diagnostics and safe errors
- Created `SALES_DELETE_FAILURE_ANALYSIS.md` before code changes, tracing the delete UI, confirmation, optional step-up semantics, repository RPCs, Sales tables, hard-delete behavior, related `sales_items`, import relations, RLS, dashboard invalidation, exact root cause, minimal safe fix, files to modify/avoid, and validation checklist.
- Confirmed `StepUpAuthService.requireStepUp(required: false)` already returns normally for skipped local auth; the log is informational and deletion should continue afterward.
- Inspected live Supabase delete RPC definitions and RLS; `delete_sales_record` deletes `sales_items` by `sale_id`, deletes `sales`, and recalculates import totals, while `delete_sales_import` deletes `sales_items`, `sales`, then `sales_imports`, all scoped by `company_id` and guarded by `user_is_company_admin`.
- Live read-only checks showed production currently has zero `sales` and zero `sales_items`, with failed `sales_imports` remaining; rollback-only simulation of `delete_sales_import` as the owner removed the import inside the transaction and then rolled back.
- Updated `lib/features/sales/data/repositories/sales_repository.dart` with `SalesDeleteException`, redacted delete-stage logs, and safe PostgREST mapping for permission (`42501`), not-found (`P0002`), FK (`23503`), and generic failures.
- Updated `lib/features/sales/presentation/screens/sales_screen.dart` so import delete, sale delete, POS disconnect, and POS delete SnackBars use safe mapped messages instead of raw `$error` text.
- Validation completed: `flutter analyze lib/features/sales/data/repositories/sales_repository.dart lib/features/sales/presentation/screens/sales_screen.dart` passed; VS Code diagnostics report no errors for the analysis file and touched Dart files.

### 2026-06-13 — Sales destructive step-up fallback
- Investigated the runtime warning `Step-up authentication unavailable for delete_sales_data` using the established delete-flow debugging pattern.
- Confirmed the root cause was a policy mismatch: document delete already treats local auth as optional when unavailable/not configured, while Sales delete/POS management still used the default required local-auth gate.
- Updated `lib/features/sales/presentation/screens/sales_screen.dart` so sales import delete, sales record delete, POS disconnect, and POS connection delete call `requireStepUp(required: false)` after the destructive confirmation sheet.
- Mandatory deletion controls remain server-side: user session, active company/tenant scoping, owner/admin requirements where applicable, RPC/function authorization, and RLS are still the gates that enforce access.
- Validation completed: `flutter analyze lib/features/sales/presentation/screens/sales_screen.dart` passed with no issues; VS Code diagnostics reported no errors for the touched file.

### 2026-06-13 — Sales dashboard sync, backfill, and CRUD actions
- Authored `SALES_DASHBOARD_SYNC_AND_CRUD_ANALYSIS.md` before implementation, covering the 23 required sections: current import flow, written tables, dashboard query sources, zero-revenue root cause, status/company/realtime/provider invalidation checks, CRUD gaps, RLS impact, minimal safe fix, files to modify/avoid, and validation checklist.
- Confirmed the live completed import `c3e2be7b-2ce0-4be3-8d28-07e5c365049d` had nonzero `sales` and 12 `sales_items` rows but was stored under `sale_date=2026-01-06`; direct aggregate showed June 2026 revenue zero and January 2026 gross `42564.70` before the fix.
- Patched and deployed `supabase/functions/process-sales-import/index.ts`:
  - ISO dates remain unchanged
  - numeric `dd/mm/yy`, `dd-mm-yyyy`, and `dd.mm.yy` report dates are parsed day-first before any JavaScript fallback
  - deployed to project `qbvfeizmcuctmhrxkvbx` as `process-sales-import` version 3
- Added and applied `supabase/migrations/20260613_sales_dashboard_sync_and_crud.sql` with `npx supabase db query --linked --file ...`:
  - `get_sales_summary` now sums `transaction_count` and computes average ticket from gross / transaction count
  - tenant/admin-scoped RPCs added for sale update/delete, sales import delete cascade, and POS connection delete
  - live backfill corrected the affected import and moved revenue into the June dashboard period
- Hardened and redeployed `supabase/functions/disconnect-pos/index.ts`:
  - accepts connection id, derives `company_id` from `pos_connections`, requires owner/admin, clears encrypted tokens, sets `credentials_status=none`, and returns safe public errors
  - deployed as `disconnect-pos` version 3
- Implemented Flutter Sales management actions:
  - `SalesRepository` now supports imported sales fetch, sale update/delete, sales import delete, POS disconnect, and POS delete
  - `sales_providers.dart` now watches `sales_items`, exposes `importedSalesProvider`, and centralizes Sales/Main dashboard invalidation
  - `sales_screen.dart` adds row overflow menus, an import management sheet, sale edit form, delete confirmations, POS disconnect/delete actions, and step-up auth gates
  - `dashboard_grid_repository.dart` now counts aggregate imported sales with `transaction_count`; dashboard realtime also watches `sales_imports` and `sales_items`
- Validation completed:
  - `deno check supabase/functions/process-sales-import/index.ts` passed
  - `deno check supabase/functions/disconnect-pos/index.ts` passed
  - focused Flutter analyze passed for touched Sales/Dashboard/step-up files
  - remote RPC install check confirms `get_sales_summary`, `update_sales_record`, `delete_sales_record`, `delete_sales_import`, and `delete_pos_connection`
  - direct live aggregate for June 2026 returns gross `42564.70`, net `4256.01`, tax `46820.71`, transaction count `1`; January 2026 is now zero for the corrected import
- Files intentionally not touched: `process-document`, document extraction/upload, product matching, supplier intelligence, auth flows, unrelated RLS, OpenRouter document VLM, Products/Documents UI, bottom navigation, and FAB.
- Remaining runtime follow-up: smoke-test Sales import management and POS destructive actions in-app with an authenticated owner/admin and verify cross-tenant denial with a second company.

### 2026-06-13 — Sales foundation + country-first Connect POS deployed
- Authored `POS_CONNECTION_ARCHITECTURE_ANALYSIS.md` before implementation, documenting the existing Flutter flow, the 404 source, local vs deployed Edge Function status, country-first provider architecture, security constraints, MVP scope, deployment checklist, and files to avoid touching.
- Implemented the Sales/POS database foundation in `supabase/migrations/20260613_sales_module_foundation.sql`:
  - `sales_imports`, `sales_items`, upgraded `sales` transaction/import fields, compatibility trigger, indexes, RLS/FORCE RLS, storage policies for `sales-imports`, and `get_sales_summary(uuid, date, date)` RPC
  - `pos_provider_catalog` seeded with 15 providers across Spain, US, UK, France, Italy, Germany, Colombia, Mexico, Portugal, Netherlands, and Other
  - enriched `pos_connections` with `provider_key`, `provider_name`, `country_code`, `connection_type`, `credentials_status`, and `created_by`; token columns remain only in `pos_connections`
  - `pos_connection_requests` for coming-soon/request-access flows
  - token-free `public.pos_connection_status` view for Flutter reads
  - realtime publication entries for `sales_imports`, `sales_items`, `pos_connections`, and `pos_sync_jobs`
- Fixed the remote migration apply issue discovered during deployment:
  - Initial `npx supabase db query --linked --file supabase/migrations/20260613_sales_module_foundation.sql` failed because `CREATE OR REPLACE VIEW public.pos_connection_status` could not change an existing view column order (`status` -> `provider_key`)
  - Updated the migration to `DROP VIEW IF EXISTS public.pos_connection_status; CREATE VIEW ...` before reapplying
  - Reapplied the migration successfully using `npx supabase db query --linked --file ...`
  - Marked only migration version `20260613` as applied with `npx supabase migration repair --linked --status applied 20260613`
  - Avoided `supabase db push` because many older unrelated local migrations are still pending and one local migration filename (`20260517b_category_propagation.sql`) does not match the CLI timestamp pattern
- Implemented the Flutter Sales module foundation:
  - `lib/features/sales/data/models/`: sales summary/import/item/POS connection models plus `PosConnectionResult` and the country/provider registry
  - `lib/features/sales/data/repositories/sales_repository.dart`: tenant-scoped summary/import/POS reads, sales report upload path, `process-sales-import` invocation, and safe `connect-pos` error mapping
  - `lib/features/sales/presentation/providers/sales_providers.dart`: Riverpod providers plus tenant-filtered realtime invalidation for `sales_imports`, `sales`, `pos_sync_jobs`, and `pos_connections`
  - `lib/features/sales/presentation/screens/`: Sales dashboard, sales import screen, and country-first Connect POS screen
  - `lib/core/router/app_router.dart`: `/sales`, `/sales/connect-pos`, and `/sales/import` routes
- Rebuilt Connect POS as a serious SaaS integration flow:
  - users select country first and see relevant providers only
  - `Custom POS` creates a pending configuration record
  - coming-soon providers save a request and never claim connection success
  - raw Supabase function 404s are mapped to “POS connection service is not deployed yet. Please try again later.”
  - no US-only hardcoding, no fake OAuth success, no direct POS secrets accepted in Flutter
- Hardened and deployed POS Edge Functions:
  - `supabase/functions/connect-pos/index.ts` now accepts only `country_code` and `provider`, authenticates the JWT, derives active company from `profiles.current_company_id`/`company_users`, validates catalog/country support, creates only valid custom pending connections, stores coming-soon requests, and returns structured user-safe messages
  - `supabase/functions/disconnect-pos/index.ts` now writes `disconnected` instead of the invalid `revoked` status
  - Deployed both with `npx supabase functions deploy connect-pos` and `npx supabase functions deploy disconnect-pos`
- Remote deployment verification completed:
  - `npx supabase functions list` shows `connect-pos` and `disconnect-pos` as `ACTIVE` on project `qbvfeizmcuctmhrxkvbx`
  - `select count(*) from public.pos_provider_catalog` returns `15`
  - `public.pos_connection_status` exposes expected token-free columns: `id`, `company_id`, `provider`, `provider_key`, `provider_name`, `country_code`, `status`, `connection_type`, `credentials_status`, `external_account_id`, `last_sync_at`, `sync_status`, `metadata`, `created_at`, `updated_at`
- Validation completed:
  - focused `dart analyze` passed for the touched Sales/POS Dart slice and router
  - `deno check supabase/functions/connect-pos/index.ts` passed
  - `deno check supabase/functions/disconnect-pos/index.ts` passed
  - VS Code diagnostics reported no errors for the touched Dart, SQL, TypeScript, and Markdown files
- Files intentionally not touched for this work: `process-document`, OpenRouter/VLM extraction, document extraction code, products, dashboard, auth UI, storage, bottom navigation, and FAB.
- Remaining runtime follow-up: smoke-test the app against the live project for country selection, Custom POS configuration, coming-soon request persistence, sales import upload, realtime POS status refresh, and cross-tenant isolation.

### 2026-06-06 — Extraction finalization UUID fixes
- Investigated the remaining live error after extracted products were visible but parent PDFs still showed:
  - `Extraction error: Failed to finalize document extraction: function uuid_generate_v4() does not exist`
- Authored `REMAINING_UUID_GENERATION_FAILURE_ANALYSIS.md` before coding, documenting why OpenRouter/PDF extraction and `document_items` persistence were already working, the exact failing finalization operation, live database defaults/functions still referencing `uuid_generate_v4()`, the trigger chain from `documents` completion into supplier/provider resolution, and the safe DB-only fix.
- Confirmed by rollback reproduction that the actual remaining failure path was `process-document` final parent update -> `documents` `auto_resolve_supplier` BEFORE UPDATE trigger -> `auto_resolve_supplier_trigger_fn()` -> `resolve_supplier()` -> `providers` insert -> `prevent_duplicate_provider()` calling unqualified `uuid_generate_v4()` under the restricted supplier-resolution path.
- Added and applied `supabase/migrations/20260606_fix_supplier_uuid_generation.sql` to the linked Supabase project:
  - `public.providers.id` default changed to `gen_random_uuid()`
  - `public.supplier_aliases.id` default changed to `gen_random_uuid()`
  - `public.prevent_duplicate_provider()` now uses `gen_random_uuid()` instead of `uuid_generate_v4()`
- Earlier same-day extraction UUID hardening also applied `supabase/migrations/20260606_fix_uuid_defaults_for_extraction.sql`, moving extraction-involved defaults for `activity_logs`, `documents`, `document_items`, and `products` to `gen_random_uuid()`.
- Validation completed:
  - live extraction-path defaults now use `gen_random_uuid()` for `activity_logs`, `documents`, `document_items`, `products`, `providers`, and `supplier_aliases`
  - live function search no longer finds application-owned `uuid_generate_v4()` references; only the extension function itself remains
  - the exact rollback `documents` completion update that previously failed now succeeds and returns a resolved `provider_id`
  - `deno check supabase/functions/process-document/index.ts` passed
- No Flutter files, OpenRouter prompts/parsing, PDF rendering/upload logic, product matching, storage policies, RLS policies, or UI code were changed for this fix.
- Remaining runtime follow-up: re-extract or re-finalize the previously flagged PDF documents, because already-flagged rows will not automatically update their parent status/notes after the database fix.

### 2026-06-04 — Multi-tenant security audit + Phase 2 path-first document hardening
- Authored the new security planning artifacts requested for the current remediation wave:
  - `MULTITENANT_SECURITY_AUDIT.md`: full multi-tenant audit with confirmed findings, surface-by-surface review, and remediation order
  - `MULTITENANT_SECURITY_TEST_PLAN.md`: tenant-isolation/storage/auth/runtime validation plan aligned to the audit findings
  - `SECURITY_FIX_IMPACT_ANALYSIS.md`: compatibility-first impact analysis for the document/storage remediation sequence; content is correct, but the current file needs a cleanup pass because it contains duplicated sections
- Confirmed the main currently active security findings blocking the next storage/privacy phase:
  - `documents` bucket is still public
  - `public.create_company_with_owner(...)` and `public.join_company_as_manager(...)` are `SECURITY DEFINER` and still trust caller-supplied `p_user_id`
  - `review_items` has RLS enabled but still lacks `FORCE ROW LEVEL SECURITY`
  - document upload/extraction/preview historically depended on durable URL fields, which had to be reduced before a private-bucket cutover
- Implemented the first compatibility-safe Phase 2 code slice to make document handling path-first while preserving legacy reads:
  - `lib/features/documents/presentation/screens/documents_screen.dart`: document open/preload now prefers `file_path` via `documentPreviewUrlProvider` before falling back to legacy `fileUrl`
  - `lib/features/documents/presentation/widgets/document_detail_sheet.dart`: image/PDF preview now prefers signed URLs resolved from `file_path`; legacy signed `fileUrl` remains as fallback for older rows
  - `lib/providers/documents_provider.dart`: optimistic documents now carry `filePath`; fresh document inserts no longer persist `file_url`; new multi-page metadata no longer writes page `file_url`
  - `lib/services/background_extraction_service.dart`: background extraction now treats `file_path` as the durable source, no longer persists `rendered_image_url`, and persists fallback `file_path` if a re-upload is required
  - `supabase/functions/process-document/index.ts`: server-side source resolution now selects/signs `file_path` first and logs whenever legacy URL fallback (`file_url`, `rendered_image_url`, page URLs) is used
- Important implementation note discovered during this work:
  - `lib/services/extraction_service.dart` still invokes `process-document` with `documentId`; the old `imageUrl` parameter was not actually part of the Edge Function request body, so URL persistence could be reduced safely without changing the server contract
- Validation completed for the touched code paths:
  - `flutter analyze --no-fatal-infos lib/providers/documents_provider.dart lib/services/background_extraction_service.dart` passed with no errors; only info-level lint items remain
  - `get_errors` on `supabase/functions/process-document/index.ts` reported no diagnostics after the path-first changes
- Remaining follow-up after today:
  - run runtime smoke tests for image upload, PDF upload, multi-page extraction, and re-extract against the new `file_path`-first write path
  - clean the duplicated content inside `SECURITY_FIX_IMPACT_ANALYSIS.md`
  - do not flip bucket privacy or harden the registration RPCs until the current compatibility validation passes

### 2026-06-03 — Dashboard intelligence data-chain fix
- Performed systematic debugging and documented the full dashboard intelligence chain in `DASHBOARD_INTELLIGENCE_PIPELINE_ANALYSIS.md`:
  - mapped document upload, VLM extraction, `process-document`, `documents`, `document_items`, `recognize-products`, `products`, `product_prices`, categories, suppliers, analytics queries, Riverpod providers, and dashboard widgets
  - confirmed the dashboard UI was not static: `IntelligenceSection` still watches `categoryIntelligenceProvider` and `topProductsDashboardProvider`
  - identified the root cause as a data-layer mismatch between calendar-month SQL views and the dashboard's rolling `ChartPeriod`, plus category spend not following the productized line-item category path
- Applied the minimal production-safe fix without touching UI, upload, extraction, storage, auth, FAB, navigation, OpenRouter prompts, or mock data:
  - `lib/services/intelligence_service.dart`: `fetchCategoryIntelligence()` and `fetchTopProducts()` now accept `ChartPeriod`, compute the same rolling date windows as the working chart/grid, and keep every query tenant-scoped by `company_id`
  - category spend now aggregates `product_prices -> products.category_id -> categories`; categorized completed documents are used only as fallback when they do not already have productized price rows for that period
  - top products now rank by period-scoped `product_prices` spend instead of the SQL view's hard-coded `current_month_spent`
  - `lib/features/dashboard/providers/intelligence_providers.dart`: added `dashboardIntelligenceRealtimeProvider` for tenant-filtered changes on `documents`, `document_items`, `products`, `product_prices`, and `categories`; category/top-product providers now watch it and `chartPeriodProvider`
- Validation:
  - `flutter analyze --no-fatal-infos lib/services/intelligence_service.dart lib/features/dashboard/providers/intelligence_providers.dart` passed with no issues
- Runtime QA still recommended:
  - upload/use a real invoice with supplier and items such as Campari/Gin/Wine, confirm product creation/price history, confirm Drinks category spend and Top Products update, then switch company and confirm no cross-tenant data leakage

### 2026-06-03 — Documents search bar Digital Atelier refactor
- Rebuilt only the visual layer of `lib/features/documents/presentation/widgets/document_search_bar.dart` to match the Digital Atelier / premium fintech search component spec:
  - introduced `DigitalAtelierSearchBar` as the owning widget and kept `DocumentSearchBar` as the public wrapper used by `lib/features/documents/presentation/screens/documents_screen.dart`
  - preserved the existing `TextEditingController` and `ValueChanged<String>` contract from `DocumentsScreen`; no changes were made to debounce, filtering, providers, Supabase queries, state management, document list rendering, or AI extraction
  - replaced the Material `InputDecoration` prefix/suffix treatment with an explicit row layout: search icon, fixed spacing, and expanded `TextField`
  - updated the search surface to the approved pill geometry and typography: 72px height, 24px outer spacing, 28px internal padding, white surface, no border/outline/underline, Manrope 18, muted icon/hint color, and soft ambient shadow
  - added lightweight micro-interactions using a local `FocusNode`, `AnimatedContainer`, and `AnimatedScale` for focus lift and press feedback
- Validation:
  - `flutter analyze --no-fatal-infos lib/features/documents/presentation/widgets/document_search_bar.dart` passed with no issues

### 2026-06-02 — Review Center / Action Inbox
- Implemented a production control-tower "Review Center" feature backed entirely by real source tables (documents, document_items, price_anomalies, providers):
  - Added `supabase/migrations/20260602_review_center.sql`:
    - `public.review_items` table: tenant-scoped, typed constraints (10 review types, 5 severities, 5 statuses), unique source constraint `(company_id, review_type, source_table, source_id)`, updated_at trigger, RLS select/insert/update policies via `user_company_ids()`
    - `sync_review_items_for_company(uuid)` RPC: derives items from failed/flagged documents, missing categories, duplicate documents, unknown document types, unmatched suppliers, missing totals, low-confidence product matches, and open price anomalies; ON CONFLICT preserves ignored/dismissed status so user decisions survive re-syncs; auto-resolves items whose source condition has cleared
    - `sync_review_items_for_document(uuid)` RPC: delegates to company sync after tenant-checking the document
    - `resolve_review_item(uuid, text, jsonb)` RPC: handles resolve/ignore/dismiss/retry actions, writes through `record_security_audit_event` for audit trail
    - `review_items` added to `supabase_realtime` publication
  - Added Flutter feature under `lib/features/review_center/`:
    - `data/models/review_item.dart`: `ReviewType`, `ReviewSeverity`, `ReviewStatus` enums with labels/serialisation; `ReviewItem.fromJson` with fallback handling; `ReviewItemCounts`
    - `data/repositories/review_center_repository.dart`: `fetchOpenItems` (with optional type filter), `fetchCounts`, `syncCompanyReviewItems`, `resolveItem`, `ignoreItem`, `retryItem` (re-invokes `ExtractionService` for failed docs), `resolvePriceAnomaly`
    - `presentation/providers/review_center_providers.dart`: `reviewCenterRealtimeProvider`, `reviewItemsProvider`, `reviewItemCountsProvider`, `syncReviewItemsProvider`, `selectedReviewFilterProvider` (`ReviewCenterFilter` enum)
    - `presentation/screens/review_center_screen.dart`: pull-to-refresh, summary strip (open/critical/AI review/prices), horizontal filter chips, severity-toned cards with icon/type/title/description/timestamp/source, primary action button (retry/assign/review/match/open by type), resolve (✓) and ignore (✗) icon buttons, source navigation to document/products/providers routes
  - Wired `/review-center` route in `lib/core/router/app_router.dart`
  - Extended dashboard intelligence grid:
    - `DashboardGridMetrics`: added `reviewOpenCount`, `reviewCriticalCount`
    - `DashboardGridRepository._fetchReviewRows`: queries `review_items` for open items by company; tolerates missing table via `_isMissingRelation`
    - `DashboardGridProvider`: watches `reviewCenterRealtimeProvider` so review changes invalidate the dashboard metrics
    - `DashboardIntelligenceGrid`: new `_DashboardReviewTile` rendered below the 2×2 grid — shows live open count, critical badge, color-toned icon (green=clear, amber=open, red=critical), and routes to `/review-center` on tap
    - `DashboardScreen` passes `onReviewTap` → `AppRoutes.reviewCenter`
  - Removed unused `import 'package:flutter/services.dart'` from `lib/main.dart` (leftover from auth hardening)
- Validation:
  - Focused `get_errors` on all 12 touched Dart and SQL files: no errors
  - `flutter analyze` completed: no new errors or warnings introduced; remaining warnings are pre-existing in unrelated files
  - Migration applied status: **not yet applied**; apply via Supabase SQL Editor before testing the live feature

### 2026-06-01 — Premium glass floating navigation
- Reworked the shell bottom navigation to match the provided Digital Atelier reference:
  - `lib/shared/ui/app_bottom_nav.dart` now renders a semi-transparent white glassmorphism pill with high-intensity `BackdropFilter` blur, extreme radius, soft ambient shadow, icon-only cells, and gray minimalist line icons
  - The nav is split into left/right glass segments with a true center gap so the charcoal `#151515` plus FAB visually breaks the top edge instead of sitting under a continuous bar
  - Visible shell destinations are now Home, Sales, Docs, and Orders; labels remain available through semantics only
- Updated shell/scaffold placement without changing business callbacks:
  - `lib/shared/widgets/main_scaffold.dart` overlays the floating nav on the off-white `#F9F9F9` shell canvas
  - `lib/shared/ui/app_scaffold.dart` centers existing per-screen FABs by default, so Dashboard/Documents/Sales/Orders keep their current actions while visually integrating with the new center plus button
  - Products/stock routes remain available through existing routed actions; no backend, Supabase, extraction, realtime, storage, auth, or tenant-isolation code was touched
- Validation completed locally:
  - `dart analyze lib\shared\ui\app_bottom_nav.dart lib\shared\widgets\main_scaffold.dart` passed with no issues
  - `lib/shared/ui/app_scaffold.dart` reports no editor diagnostics; wider analyzer output in that file still contains pre-existing info-level style hints unrelated to the FAB placement change

### 2026-05-29 — Dashboard intelligence grid + premium FAB motion polish
- Replaced the old two-card dashboard chart KPI row with a real-data 2x2 floating grid:
  - Added `lib/features/dashboard/data/models/dashboard_grid_metrics.dart`
  - Added `lib/features/dashboard/data/repositories/dashboard_grid_repository.dart`
  - Added `lib/features/dashboard/presentation/providers/dashboard_grid_provider.dart`
  - Added `lib/features/dashboard/presentation/widgets/dashboard_intelligence_grid.dart`
  - Updated `lib/features/dashboard/presentation/screens/dashboard_screen.dart` to render `DashboardIntelligenceGrid` below `ExpenseLineChart`
- Dashboard grid behavior:
  - Tiles: Expenses, Results, Sales, Documents
  - Uses `chartPeriodProvider` so metrics follow the existing chart period selector
  - Resolves tenant context through `companyIdProvider`; all Supabase reads include explicit `.eq('company_id', companyId)`
  - Expenses use completed, non-duplicate, non-merged, non-deleted documents; VAT/tax remains visible as Expenses metadata
  - Sales reads tenant `sales` rows first and falls back to completed tenant `orders` when needed; Results is Sales minus Expenses
  - Documents tile summarizes processed/pending/failed document status for the selected period
  - Expenses/Sales/Documents tiles route to existing routes; Results opens a lightweight detail sheet because no dedicated Results route exists
- Realtime/motion details:
  - `lib/providers/expense_chart_provider.dart` now exposes shared `documentMetricRealtimeProvider` so chart/grid document metric refreshes reuse one stream
  - Dashboard grid adds only sales/order realtime listening for the sales-side metrics
  - Grid UI follows the provided floating-card design guide: white rounded cards on off-white, no borders, soft shadow, icon top-left, label bottom-left, skeleton/error states, press scale, fade/slide entry, and `AnimatedSwitcher` metric updates
- Premium FAB presentation polish completed without changing business logic:
  - Updated `lib/shared/ui/premium_fab.dart` to a circular 60/64px charcoal FAB (`#151515`) with centered white plus, no label, no border, soft 30px ambient shadow, semantics label, light haptics, and 80ms/140ms press/release scale
  - Updated `lib/shared/fab/floating_action_hub.dart` to present the existing `AppFabAction` callbacks in a blurred quick-action overlay with dark scrim, staggered row entrance, press feedback, medium open haptic, tap-outside close, swipe-down close, back behavior, and a rotating close FAB that turns plus into an x
  - Preserved every existing action source: `fab_action_registry.dart` and `scanner_fab_actions.dart` remain the business callback definitions for Upload expense, Upload file, Camera, Photo library, Manually, Expense tracker, Providers, Products, Orders, and Documents
- Validation completed locally:
  - `dart format` completed for touched dashboard/FAB files
  - Focused `flutter analyze` passed with no issues for the dashboard grid slice
  - Focused `flutter analyze` passed with no issues for `lib/shared/ui/premium_fab.dart`, `lib/shared/fab/floating_action_hub.dart`, `lib/shared/fab/fab_action_registry.dart`, and `lib/shared/fab/scanner_fab_actions.dart`
  - Broader FAB call-site analyzer pass reported only pre-existing style warnings in unrelated screen files; no FAB route/provider/type regressions were introduced

### 2026-05-29 — Migration backlog closed + document detail UI polish
- Supabase migration status updated after manual SQL Editor application:
  - All pending Supabase migrations referenced in this context through `supabase/migrations/20260529_document_delete_cleanup_hardening.sql` are now applied in the target environment
  - Prioritized next steps no longer include migration-apply tasks; they now focus on runtime verification, CI gates, on-device smoke tests, and feature polish
  - Remaining database work is validation, not schema application: RLS/storage isolation suite, audit event checks, realtime exposure checks, delete cleanup checks, intelligence/category/anomaly smoke tests, and async extraction smoke tests
- Finalized the document delete behavior after the first local-auth fix still showed `Authentication is unavailable. Use your device passcode or try again.`:
  - Root cause: `LocalAuthentication.authenticate(biometricOnly: false)` can still throw unavailable/not-enrolled/passcode-not-set on emulator/devices without configured local credentials; the previous fix only loosened the precheck and did not handle the thrown platform result as optional
  - `lib/core/security/local_auth_service.dart`: added `LocalAuthResult.skipped` plus a `required` flag; unavailable/notConfigured/unexpected errors become `skipped` when local auth is optional
  - `lib/services/step_up_auth_service.dart`: `requireStepUp()` accepts `required`; skipped optional auth logs and continues instead of throwing a snackbar-driving exception
  - `lib/features/documents/data/services/document_delete_service.dart`: document delete calls `requireStepUp(required: false)` so confirmation + Supabase session + `company_id` + RLS are the mandatory gates, while local auth remains opt-in/mandatory only if future policy enables it
  - Android/iOS `local_auth` prerequisites remain in place: `FlutterFragmentActivity`, biometric permissions, and `NSFaceIDUsageDescription`
- Redesigned the Document Detail Extracted Products section as a premium finance card:
  - Added `lib/features/documents/presentation/widgets/extracted_products_card.dart`
  - Replaced the old private `_LineItemsTable` in `lib/features/documents/presentation/widgets/document_detail_sheet.dart`
  - The new component uses real `DocumentLineItem` data, soft white card surface, 36px radius, no hard dividers, Plus Jakarta Sans headers, Manrope body/numbers, tabular currency figures, skeleton/empty/error states, and row semantics
- Validation completed locally:
  - `flutter build apk --debug` passed after the local-auth platform changes
  - `dart format` completed for touched Dart files
  - VS Code diagnostics reported no errors for the touched delete/auth/UI files
  - `flutter analyze lib\features\documents\presentation\widgets\extracted_products_card.dart` passed with no issues
  - Focused analyzer over the full document detail sheet still reports pre-existing info-level style warnings in that older file; no blocking diagnostics were introduced

### 2026-05-29 — FAB action hub + document delete auth fix
- Fixed the FAB/navigation regression introduced by the scanner-first FAB rewrite:
  - Added typed FAB action architecture under `lib/shared/fab/`: `app_fab_action.dart`, `app_fab_action_group.dart`, `scanner_fab_actions.dart`, `fab_action_registry.dart`, and `floating_action_hub.dart`
  - `lib/features/dashboard/presentation/screens/dashboard_screen.dart`: Dashboard FAB now opens route-aware quick actions and restores Upload expense, Expense tracker, Providers, Products, Orders, and Documents
  - `lib/features/documents/presentation/screens/documents_screen.dart`: Documents FAB opens directly to Upload file, Camera, Photo library, and Manually actions
  - `lib/shared/ui/scanner_action_sheet.dart`: legacy sheet now dismisses using the sheet context, not `rootNavigator`, preventing GoRouter from popping the last page and black-screening
- Fixed the document delete authentication flow after root-cause investigation:
  - Root cause: `BiometricService.authenticate()` collapsed cancel/unavailable/platform failures into raw `false`, and `StepUpAuthService` mapped all false values to `Authentication was cancelled. No changes were made.` before Supabase deletion was reached
  - Added `lib/core/security/local_auth_service.dart` with typed `LocalAuthResult` values: success, cancelled, failed, unavailable, notConfigured, error
  - Refactored `lib/services/step_up_auth_service.dart` to use typed local-auth results and delete-specific user messages
  - `lib/features/documents/presentation/widgets/document_detail_sheet.dart`: replaced AlertDialog with a premium confirmation bottom sheet, added loading guard and safe delete-flow debug tracing
  - `lib/features/documents/data/services/document_delete_service.dart`: added tenant-scoped verification logs, local-auth/Supabase/storage tracing, permission-denied classification, storage path ownership checks, and clearer retry-friendly errors
  - Added `supabase/migrations/20260529_document_delete_cleanup_hardening.sql`: preserves `delete_document_cascade(uuid, uuid)` but expands tenant-scoped cleanup for optional product intelligence and duplicate metadata tables when present
- Validation completed locally:
  - `dart format` completed for all touched Dart files
  - VS Code diagnostics reported no errors for the changed Dart files
  - Exact old snackbar string `Authentication was cancelled. No changes were made.` no longer appears under `lib/**/*.dart`
  - Targeted `dart analyze` hung at `Analyzing...` with no findings, consistent with earlier workspace analyzer hangs; process was killed
  - Database migration was later applied manually via Supabase SQL Editor on 2026-05-29; runtime validation remains to be done because local Supabase/psql tooling is unavailable in this workspace

### 2026-05-28 — Neobank UI correction + animation audit roadmap
- Applied a focused neobank UI correction pass without touching Supabase, extraction, realtime, or tenant-isolation logic:
  - `lib/main.dart`: disabled Flutter's debug banner via `debugShowCheckedModeBanner: false`
  - `lib/core/theme/editorial_theme.dart`: refreshed palette toward off-white/white/charcoal/muted gray with Sora display/UI typography and DM Mono tabular numerics
  - `lib/shared/ui/app_bottom_nav.dart`: rebuilt the bottom nav as a floating icon-only capsule with soft active icon pill; labels remain available only for semantics
  - `lib/shared/ui/premium_fab.dart`: rebuilt FAB as a charcoal rounded action with 0.97 press feedback
  - `lib/shared/ui/scanner_action_sheet.dart`: added scanner-first action sheet with Scan receipt / Upload file / Choose from library / Enter manually actions; all camera/file/gallery paths continue through `CameraUploadService`
  - `lib/features/dashboard/presentation/screens/dashboard_screen.dart`: replaced generic quick-actions FAB menu with `ScannerActionSheet.show(context, ref)`, added a lighter greeting header, and preserved dashboard analytics/provider/document flows
  - `lib/features/documents/presentation/screens/documents_screen.dart`: unified the Documents FAB with the same scanner sheet and manual-entry callback
  - `lib/widgets/expenses/chart_period_selector.dart`, `lib/widgets/expenses/chart_kpi_cards.dart`, and `lib/widgets/expenses/expense_line_chart.dart`: softened period selector, KPI card, and chart styling to better match premium fintech/neobank references
- Validation completed for this UI slice:
  - VS Code diagnostics reported no errors for the touched UI/theme files
  - A full `flutter analyze --no-pub` attempt hung in the terminal and was killed; project-wide analyzer debt is already tracked separately under P4.2
- Authored `ANIMATION_AUDIT.md` as Phase 1 of the premium motion work:
  - Includes animation inventory, screen-by-screen motion map, Current behavior / Problem / Better behavior / Why table, Before / After / Why table, proposed `AppMotion` token system, shared motion component plan, implementation phases, reduced-motion strategy, performance risks, and QA checklist
  - No runtime motion-system implementation was started yet; Phase 2 should implement the shared motion primitives before further screen-level animation polish

### 2026-05-28 — "Quiet Hospitality" editorial redesign completed (Phases 5–9) + font system fix
- Completed the 9-phase warm-bone editorial redesign across every routed feature surface:
  - **Phase 5 — Documents:** `document_card.dart` and `document_stats_row.dart` flattened to hairline borders; `StatusBadge(dot: true)` for processing/completed/flagged states
  - **Phase 6 — Expenses:** `expense_tracker_screen.dart` rewritten (~270 lines) as a single hairline-row `AppCard` breakdown with `FinancialValue` hero, `StatusBadge` percentages, and 3px progress bars; `expense_form_screen.dart` migrated to `AppTopBar` + `AppScaffold(bottomBar: _StickyCTA)`; dead `_Header` class removed
  - **Phase 7 — Products list:** `product_list_screen.dart` rewritten with hairline grid cards, `Wrap` of `StatusBadge` stats, horizontal `CategoryChip` filter, `MetricText(small)` pricing, `AppEmptyState` / `ErrorState` / skeleton grid; `product_detail_screen.dart` (1350 lines) intentionally left untouched
  - **Phase 8 — Suppliers / Sales / Orders:** `providers_screen.dart` rewritten with `DataRowItem` + `PriceTrendIndicator` rows in a single `AppCard`; `sales_screen.dart` and `orders_screen.dart` rebuilt as editorial placeholders with `PremiumFAB`; `supplier_detail_screen.dart` (755 lines) and orphaned `sales_tracker_screen.dart` (462 lines) left untouched
  - **Phase 9 — Auth + cleanup:** `login_screen.dart` rewritten (~440 lines) with flat `_BrandMark` (64×64 accent square), custom `_EditorialField` (hairline → accent focus border, lowercase eyebrow labels), flat 52px accent submit button, hairline divider, and `_SocialButton` Google/Apple outlines; deleted three orphaned widgets: `lib/features/dashboard/presentation/widgets/floating_navigation_pill.dart`, `lib/features/dashboard/presentation/widgets/dashboard_header.dart`, `lib/features/documents/presentation/widgets/document_action_bar.dart`
- Fixed runtime red-screen error `Exception: No font family by name 'Geist' was found`:
  - Cause: `google_fonts ^6.2.1` does not ship the Geist / Geist Mono families (added in a later package version); `GoogleFonts.getFont('Geist', ...)` returned a `TextStyle` referencing an unregistered family which Flutter rejected at paint time
  - Fix iteration in `lib/core/theme/editorial_theme.dart`: `_sans()` migrated Geist → Inter → DM Sans → **Sora** (final); `_mono()` migrated Geist Mono → JetBrains Mono → **DM Mono** (final, preserves `FontFeature.tabularFigures()`); `sansFontName` / `monoFontName` constants updated to match
  - Final typography stack: **Fraunces** (display serif) + **Sora** (UI sans) + **DM Mono** (numerics, tabular figures)
- Verified `flutter test test/widget_test.dart` and workspace-wide `get_errors` on `lib/` reported no errors after each phase

### 2026-05-27 — P4.4 sensitive-operation audit logging authored
- Added `supabase/migrations/20260527_audit_sensitive_operations.sql`:
  - Extends `activity_logs` with `outcome`, `correlation_id`, and sanitized `metadata`
  - Adds `record_security_audit_event(...)` plus `redact_audit_payload(...)`
  - Replaces broad `activity_logs` policies with tenant SELECT plus security-definer append paths, and revokes direct authenticated INSERT/UPDATE/DELETE
  - Adds database audit coverage for document delete, member invite/role/remove, company settings change, anomaly resolution, document category override, and expense category override
- Added `supabase/functions/_shared/audit.ts` and wired AI-backed Edge Functions:
  - `process-document`
  - `classify-expense`
  - `recognize-products`
- Patched Flutter storage services to audit signed URL generation and storage authorization/policy failures without storing signed URLs or object paths.
- Validation completed locally:
  - VS Code diagnostics report no issues for the new audit migration or touched storage files
  - `python scripts/security/check_migration_rls.py` passed for 19 tenant tables
  - `deno check` passed for the touched Edge Functions and shared helpers
  - Focused Flutter analyzer still reports only existing info-level redundant-argument lints in `lib/core/services/storage_service.dart`
- Database apply and runtime audit assertions remain pending because local Supabase/psql tooling is unavailable in this workspace.

### 2026-05-27 — P4.3 security runbooks authored
- Added `doc/security/README.md` as the security runbook index and operating rules.
- Added incident/operational runbooks:
  - `doc/security/runbooks/leaked_signed_url_incident.md`
  - `doc/security/runbooks/ai_key_compromise.md`
  - `doc/security/runbooks/tenant_data_exposure_triage.md`
  - `doc/security/runbooks/storage_policy_rollback.md`
- Added `doc/security/release_security_checklist.md` for production release-owner and security-reviewer sign-off.
- Validation completed locally:
  - VS Code diagnostics report no issues for the new runbook/checklist files
  - Roadmap status updated; release-owner sign-off remains pending before treating P4.3 as fully done

### 2026-05-27 — P4.2 CI security gates started
- Added `.github/workflows/security-ci.yml` with five security jobs:
  - `flutter analyze`
  - `deno check` for `process-document`, `classify-document-type`, `classify-expense`, `recognize-products`, and shared Edge Function helpers
  - dependency freshness check via `flutter pub outdated` and OSV vulnerability scan against `pubspec.lock`
  - forbidden Flutter pattern checks
  - migration RLS lint for tenant tables with `company_id`
- Added `scripts/security/check_forbidden_patterns.ps1`:
  - Blocks Flutter `OPENROUTER_API_KEY`, direct `openrouter.ai/api`, `SUPABASE_SERVICE_ROLE_KEY`, `getPublicUrl()`, and long signed URL TTL patterns
  - Currently fails as expected on unresolved earlier findings in duplicate merge and document storage URL handling
- Added `scripts/security/check_migration_rls.py`:
  - Scans Supabase migrations for public tables created with `company_id`
  - Requires migration coverage for `ENABLE ROW LEVEL SECURITY`, `FORCE ROW LEVEL SECURITY`, and at least one policy
- Validation completed locally:
  - VS Code diagnostics report no issues for the new workflow/scripts or updated tracker files
  - `python scripts/security/check_migration_rls.py` passed for 19 tenant tables
  - `deno check supabase/functions/process-document/index.ts supabase/functions/classify-document-type/index.ts supabase/functions/classify-expense/index.ts supabase/functions/recognize-products/index.ts supabase/functions/_shared/request.ts supabase/functions/_shared/rate_limit.ts supabase/functions/_shared/redact.ts` passed
  - `scripts/security/check_forbidden_patterns.ps1` fails with four expected finding groups until P1.3/P2.1/P1.2-style storage and AI remediations are completed
  - `flutter analyze` fails on existing project analyzer debt: 615 issues reported locally, mostly info-level lints plus warnings

### 2026-05-27 — P3.5 Edge Function type-check restoration
- Completed P3.5 from `SECURITY_REMEDIATION_ROADMAP.md`:
  - Removed the remaining `// @ts-nocheck` from `supabase/functions/classify-document-type/index.ts`
  - Added typed OpenRouter chat response and classifier extraction guards so the fallback classifier type-checks without suppressions
  - Confirmed no `// @ts-nocheck`, `@ts-ignore`, or `@ts-expect-error` directives remain under `supabase/functions/**/*.ts`
- Validation completed:
  - `deno check supabase/functions/classify-document-type/index.ts supabase/functions/process-document/index.ts supabase/functions/_shared/request.ts supabase/functions/_shared/rate_limit.ts supabase/functions/_shared/redact.ts` passed
  - `deno check supabase/functions/process-document/index.ts supabase/functions/classify-document-type/index.ts supabase/functions/classify-expense/index.ts supabase/functions/recognize-products/index.ts supabase/functions/_shared/request.ts supabase/functions/_shared/rate_limit.ts supabase/functions/_shared/redact.ts` passed
- CI note:
  - No existing `.github/workflows` or Deno config was found locally, so CI enforcement remains a P4.2 follow-up rather than part of this code slice

### 2026-05-27 — P4.1 RLS and storage isolation testing started
- Added `supabase/testing/p4_1_rls_storage_isolation.sql`:
  - Seeds two companies/users inside a transaction and rolls back on success
  - Simulates an authenticated Company A user via `request.jwt.claim.sub`
  - Checks tenant-table metadata for RLS, `FORCE ROW LEVEL SECURITY`, and at least one policy on every public table with `company_id`
  - Verifies representative cross-tenant SELECT/UPDATE/DELETE/INSERT denial for providers, products, documents, document_items, categories, expenses, and supplier_aliases
  - Verifies document storage object path isolation for `company_id/document_id/file.ext`
- Added `supabase/migrations/20260527_force_rls_expense_supplier_tables.sql`:
  - Enables and forces RLS on `categories`, `expenses`, and `supplier_aliases`
  - Reasserts tenant policies with the project-standard `company_id = ANY(public.user_company_ids())` pattern
- Added `supabase/testing/README.md` with execution instructions and expected `ROLLBACK` success behavior
- Validation completed locally:
  - VS Code diagnostics report no issues for the new SQL, migration, and README files
  - Database execution is pending because local psql/Supabase DB tooling is unavailable in this workspace

### 2026-05-24 — Security audit and remediation through P3.4
- Created `security_audit_report.md` as the full security audit artifact and `SECURITY_REMEDIATION_ROADMAP.md` as the step-by-step remediation tracker
- Completed P1.1 code hardening for `supabase/functions/process-document/index.ts`:
  - Requires caller JWT, validates the user via Supabase Auth, derives document/company access through RLS, and only uses service-role operations after tenant context is established
  - Rejects unsupported request fields, removes client-trusted image/company payloads, adds image fetch timeout and max byte-size controls, and avoids raw OpenRouter error body exposure
- Completed P2/P3 remediation slices in code:
  - Added Edge Function redaction helper `supabase/functions/_shared/redact.ts`
  - Removed anon bearer fallback from storage operations so storage calls fail closed without a session
  - Added explicit tenant filters to document/activity access paths
  - Added step-up authentication for sensitive Flutter actions such as document delete, company/member changes, anomaly resolution, and baseline approval
  - Hardened environment configuration with required `APP_ENV`, Supabase URL/key validation, no production development defaults, and README build instructions
  - Reduced realtime exposure by removing duplicate document subscriptions, narrowing client realtime filters, and authoring `supabase/migrations/20260524_harden_realtime_exposure.sql` for unused `sales`/`orders` publication reduction
- Completed P3.4 Edge Function input validation and rate limiting:
  - Added `supabase/functions/_shared/request.ts` for bounded JSON reads, content-length checks, object-only payloads, unknown-field rejection, and required string validation
  - Added `supabase/functions/_shared/rate_limit.ts` for per-user/per-company instance-local throttling with redacted denial logs and `Retry-After` responses
  - Patched `process-document`, `classify-document-type`, `classify-expense`, and `recognize-products` to use shared request guards and rate limits before OpenRouter-backed work
  - `classify-document-type` now requires POST + valid JWT, caps raw text input, uses an OpenRouter timeout, and returns generic classifier failures instead of raw upstream bodies
- Authored security migrations, later applied manually via Supabase SQL Editor on 2026-05-29:
  - `supabase/migrations/20260524_lock_down_dashboard_stats.sql` revokes raw materialized-view access and exposes a tenant-filtered secure view
  - `supabase/migrations/20260524_harden_realtime_exposure.sql` removes unused `sales`/`orders` realtime publication exposure and resets replica identity
- Validation completed:
  - `deno check supabase/functions/process-document/index.ts supabase/functions/classify-document-type/index.ts supabase/functions/classify-expense/index.ts supabase/functions/recognize-products/index.ts supabase/functions/_shared/request.ts supabase/functions/_shared/rate_limit.ts supabase/functions/_shared/redact.ts` passed
  - Focused Flutter analyzer checks passed for touched security slices; some larger files still carry pre-existing info-level lint debt
  - Cross-tenant runtime validation remains pending because local Supabase CLI/psql validation is unavailable

### 2026-05-19 — Price anomaly detection engine
- Created `supabase/migrations/20260519_price_anomaly_engine.sql` (applied manually via Supabase SQL Editor on 2026-05-29):
  - Adds tenant-scoped `price_anomalies` table with anomaly type, product/supplier/document links, current/expected price, deviation %, severity, confidence, heuristic details, AI explanation/confidence, and resolution fields
  - Adds tenant-scoped `product_price_stats` cache table with sample count, supplier count, average/median/stddev/min/max price, last supplier/price/date, 30-day trend metrics, quantity stats, and approved baseline fields
  - Adds tenant-scoped `product_purchase_fingerprints` table for duplicate price-pattern detection using document-level product/quantity/price hashes
  - Adds RLS + FORCE RLS policies for all new tables using `company_id = ANY(public.user_company_ids())`
  - Adds `refresh_product_price_stats(company_id, product_id)` RPC and `resolve_price_anomaly(company_id, anomaly_id, status, note)` RPC; refresh is guarded for authenticated callers and service/migration-safe
  - Adds `price_anomalies` and `product_price_stats` to `supabase_realtime` publication when available
- Updated `supabase/functions/recognize-products/index.ts`:
  - After `product_prices.upsert()`, collects price observations and runs non-blocking background anomaly detection via `EdgeRuntime.waitUntil` when available
  - Implements deterministic rules for price spikes, supplier overpricing, 30-day inflation trend, quantity anomalies, and duplicate price patterns
  - Uses OpenRouter `mistralai/mistral-small-3.1-24b-instruct:free` only after heuristic detection for user-facing explanation/severity/confidence refinement; heuristics remain source of truth
  - Refreshes cached stats per product and inserts idempotent `price_anomalies` rows keyed by `(company_id, product_price_id, anomaly_type)`
- Added Flutter anomaly data layer:
  - `lib/features/products/data/models/price_anomaly_model.dart`
  - `lib/features/products/data/models/product_price_stats_model.dart`
  - Extended `ProductRepository` with tenant-scoped `fetchPriceStats`, `fetchPriceAnomalies`, and `resolvePriceAnomaly`; also fixed product detail fetch to require `company_id`
  - Extended product realtime provider to listen to `price_anomalies` and `product_price_stats`
- Upgraded `lib/features/products/presentation/screens/product_detail_screen.dart`:
  - Adds Price Health card showing OK/WATCH/WARNING, top open anomaly, confidence, and cached stats fallback
  - Highlights anomalous price points in the fl_chart price history and draws an average-price reference line
  - Enhances supplier comparison with best-price/highest supplier labels
  - Adds anomaly timeline with severity/confidence/deviation badges and actions: Resolve, Ignore, Approve baseline

### 2026-05-17 — Intelligence analytics system
- Created `supabase/migrations/20260517_intelligence_analytics.sql` (applied manually via Supabase SQL Editor on 2026-05-29):
  - Adds `document_items.supplier_id UUID REFERENCES providers(id) ON DELETE SET NULL` + index
  - Creates `v_category_intelligence` view: per-category aggregated metrics (total_documents, total_spent, current_month_spent, prior_month_spent, last_document_date) with `security_invoker = true`
  - Creates `v_top_products_by_spend` view: top products by spend with category name/color, supplier name, latest/min/max price, purchase_count, current/prior month spend with `security_invoker = true`
  - Adds performance indexes: `idx_documents_company_category_status_date`, `idx_product_prices_product_date_company`
- Updated `supabase/functions/recognize-products/index.ts`: added `supplier_id: documentRow.provider_id ?? null` to the `document_items.update()` call so each extracted line item is linked to its originating supplier; redeploy if the latest production function does not include this patch
- Created `lib/services/intelligence_models.dart`: `CategoryIntelligence` and `ProductIntelligenceSummary` data models mapped from the two new views; both have `fromJson` factories and computed helpers (monthDelta, isTrendUp, priceVariancePct)
- Created `lib/services/intelligence_service.dart`: `IntelligenceService` with `fetchCategoryIntelligence(companyId)`, `fetchTopProducts(companyId, {limit, includeAllTime})`, `fetchPriceVarianceAlerts(companyId, {threshold, limit})`; all queries are tenant-scoped; PGRST205/42P01 errors degrade gracefully to empty list if an environment lacks the expected views
- Created `lib/features/dashboard/providers/intelligence_providers.dart`: Riverpod providers — `intelligenceServiceProvider`, `categoryIntelligenceProvider`, `topProductsDashboardProvider`, `topProductsAllTimeProvider`, `priceVarianceAlertsProvider`
- Created `lib/features/dashboard/presentation/widgets/intelligence_section.dart`: `IntelligenceSection` ConsumerWidget with two EtherealCards — category breakdown (colored dot + progress bar + MoM trend arrow) and top 5 products (avatar/image + name + supplier + spend); matches existing editorial/ethereal design system
- Updated `lib/features/dashboard/presentation/screens/dashboard_screen.dart`: added `IntelligenceSection` sliver between ChartKpiCards and TopProvidersSection
- Fixed `lib/features/expenses/data/services/expense_service.dart` ([ISSUE-024]): changed expenses embed from `expenses(category_id)` to `expenses!expense_id(category_id)` to pin the FK hint and resolve PGRST200 ambiguity; fixed Dart cast from List to single Map
- Created `supabase/migrations/20260517b_category_propagation.sql` ([ISSUE-025]):
  - `sync_provider_category_trigger_fn()` trigger function: AFTER UPDATE OF `category_id`/`provider_id` on documents — propagates confirmed category to all uncategorized siblings from the same provider; never overwrites; re-entrant safe; propagates to linked expenses via `expenses.document_id`
  - `sync_provider_category` trigger: AFTER UPDATE OF `category_id, provider_id ON documents`
  - `backfill_provider_categories(p_company_id UUID)` RPC: idempotent backfill; authenticated callers must supply `company_id` and pass membership check; postgres/supabase_admin roles bypass the check (migration-safe); GRANT EXECUTE to authenticated
  - Runs `SELECT backfill_provider_categories()` at migration time to fix all existing records immediately (e.g. the uncategorized Escola Vins invoice)

**Runtime checklist:**
```bash
# 1. Confirm v_category_intelligence and v_top_products_by_spend return tenant-scoped data
# 2. Confirm category propagation/backfill worked for existing supplier siblings
# 3. Redeploy recognize-products if production does not include the supplier_id patch:
npx supabase functions deploy recognize-products
```

### 2026-05-14 (session 2)
- Fixed the category pipeline end to end ([ISSUE-023]):
  - lib/providers/documents_provider.dart: added `category_id` to the documents.insert() in submitExpenseFlow() so user-selected category is persisted to BOTH documents and expenses tables immediately at upload time; added `[CATEGORY]` debug print for traceability
  - lib/features/expenses/data/services/expense_service.dart: changed fetchDocumentCategorySummaries() to select `expenses(category_id)` alongside documents.category_id; Dart mapping now uses expenses.category_id first (user's explicit choice) and falls back to documents.category_id (AI-derived); this also corrects old records uploaded before today's fix
  - lib/providers/documents_provider.dart: in _syncExpenseAfterExtraction() added a read of the expense's existing category_id before the update; AI-derived document category is only propagated to the expense if the expense has no category yet — user's choice can never be overwritten

### 2026-05-14
- Hardened document-type classification end to end:
  - Updated supabase/functions/process-document/index.ts with a classification-first hospitality document prompt that forces invoice vs delivery_note vs expense_ticket decisions before extraction
  - Added raw_text, ai_document_type, heuristic overrides, and low-confidence fallback text classification inside the server extraction flow
  - Created and deployed supabase/functions/classify-document-type/index.ts as a secure text-only OpenRouter proxy for fallback classification
  - Updated lib/services/extraction_service.dart to log AI/final type decisions, re-apply deterministic document-type validation from raw_text, and persist final document_type with tenant-scoped filters
  - Deployed process-document and classify-document-type to production project qbvfeizmcuctmhrxkvbx
- Fixed the PDF extraction handoff contract end to end:
  - Added deterministic rendered-image upload under the original document folder contract: company_id/document_id/original.pdf for the source PDF and company_id/document_id/*_rendered.jpg for the OCR/VLM image
  - Added lib/services/background_extraction_service.dart to render PDF page 1, upload the rendered JPEG back into the same document folder, persist rendered_image_url, and invoke process-document with documentId + companyId + imageUrl + currency
  - Extended StorageService.uploadDocument() so callers can force uploads into an existing document_id folder instead of always generating a new UUID
  - Added SUPABASE_MIGRATION.sql with documents.rendered_image_url and flag_stale_processing_documents()
- Fixed function-side error visibility and a new 500 regression:
  - Updated lib/services/extraction_service.dart so Supabase FunctionException details are logged and propagated instead of being flattened to just the runtime type
  - Updated lib/services/background_extraction_service.dart so flagged documents store the full exception text in notes
  - Removed the invalid documents.supplier_name update from supabase/functions/process-document/index.ts after it caused function-side failures during PDF extraction
  - Redeployed process-document successfully via npx supabase functions deploy process-document
- Refactored document upload orchestration toward truly non-blocking background extraction:
  - Added a realtime stream-backed documents provider so document cards update live as rows move through processing/completed/flagged states
  - Removed the old expense extraction polling loop and replaced it with a detached background worker that updates documents/expenses after extraction instead of holding the submit UI open
  - Added a shared extraction-start claim on the Flutter side and matching extraction_started_at claim logic in supabase/functions/process-document/index.ts to reduce duplicate execution
- Added supabase/migrations/20260514_async_background_extraction.sql:
  - Adds documents.extraction_started_at TIMESTAMPTZ
  - Adds company/status/extraction_started_at index for processing lookups
  - Migration was later applied manually via Supabase SQL Editor on 2026-05-29
- Redeployed process-document to production project qbvfeizmcuctmhrxkvbx:
  - Deploy succeeded via npx supabase functions deploy process-document
  - DB push did not succeed at the time; production schema was later updated manually via Supabase SQL Editor on 2026-05-29
- Fixed the PDF upload UX regression end to end:
  - submitExpenseFlow() and uploadDocument() now upload raw PDFs immediately, insert documents.status='processing', return control to the UI, and start a background task after navigation
  - Background PDF processing now converts PDFs to OCR images, replaces the stored document payload, applies a 3-page cap, enforces a 60s timeout, and only then invokes extraction
  - Corrected the first async PDF refactor after discovering pdfx cannot run inside compute() because it is MethodChannel-backed; PDF rendering now stays on the main isolate but only after navigation, preserving fast UI behavior
- Fixed UI regressions discovered during the refactor:
  - Product detail metadata chip layout hardened to avoid wrapped-row overflow
  - Expense form snackbar message row now constrains long text correctly and no longer overflows on narrow screens

### 2026-05-07
- Implemented tenant-scoped category learning end to end:
  - Added supabase/migrations/20260509_category_learning_system.sql with documents.category_id, documents.ai_category_id, documents.category_confidence, category_learning table, RLS, and RPCs for correction recording and accuracy reporting
  - Moved category prediction into supabase/functions/process-document/index.ts using supplier history, keyword history, and AI fallback; manual category edits now record learning signals per company
  - Updated Flutter document/expense flows to carry category suggestion state, confidence handling, and manual correction recording
- Restored and hardened the product pipeline:
  - Fixed lib/providers/documents_provider.dart so _runExtractionForExpense() invokes recognize-products after process-document completes
  - Added supabase/migrations/20260510_product_intelligence_pipeline.sql with product_aliases, document_items.normalized_description, product_prices supplier/date enrichment, exact alias RPC, fuzzy candidate RPC, and remote-schema self-healing for missing product_prices
  - Reworked supabase/functions/recognize-products/index.ts to match products via alias -> fuzzy candidates -> AI disambiguation -> create, persist aliases, update normalized item descriptions, and upsert supplier-aware price history
  - Deployed recognize-products to production project qbvfeizmcuctmhrxkvbx and successfully applied 20260510_product_intelligence_pipeline.sql to the linked database after compatibility fixes
- Expanded the Flutter product intelligence UI:
  - Added product_normalizer.dart and product_matcher_service.dart
  - Extended product models/repository/providers to support resolved category names, aliases, supplier-aware price history, supplier breakdown, and pricing insights
  - Updated product list/detail screens so catalogue stats, aliases, supplier breakdown, and pricing insights render from the new product intelligence data

### 2026-05-04
- Implemented Supplier Intelligence across SQL, data providers, and Flutter UI:
  - Repaired supabase/migrations/20260505_supplier_intelligence.sql after the invalid GIN index failure
  - Added supplier alias normalization and supplier resolution support for fuzzy matching and spend aggregation
  - Rebuilt the suppliers list screen, created supplier detail screen, and routed /providers/:id in GoRouter
- Hardened the extraction pipeline for Spanish invoices:
  - Updated supabase/functions/process-document/index.ts with deterministic Spanish date normalization for dd/mm/yyyy and Spanish month-name formats
  - Cleaned supplier-name OCR noise handling and redeployed process-document to production project qbvfeizmcuctmhrxkvbx
- Implemented Duplicate Invoice Guard end to end in code:
  - Added supabase/migrations/20260506_duplicate_invoice_guard.sql with duplicate columns, normalization helpers, duplicate trigger, backfill, and supplier-intelligence view exclusion for duplicates
  - Updated process-document to compute normalized document identifiers and mark duplicate documents server-side
  - Updated Flutter document/expense flows with UploadDocumentResult, duplicate confirmation modal, duplicate-safe analytics filters, duplicate badges on cards, and duplicate detail warning with View original
  - Added shared duplicate utilities and document management services in Flutter to support duplicate handling and re-extract/delete flows cleanly
  - Validated the touched Dart and edge-function files; remaining flutter analyze output for the touched files is lint/info level only
- Created migration supabase/migrations/20260424_product_recognition.sql (applied manually via SQL Editor):
  - Added image_url TEXT and category_id UUID FK to products table
  - Created product_prices table (id, company_id, product_id, document_id, document_item_id, price, quantity, unit, observed_at)
  - GIN trgm index on products.name_normalized for fuzzy matching
  - find_product_by_similarity(company_id, normalized_name, threshold) RPC function
  - RLS policy on product_prices via user_company_ids()
  - products storage bucket (public, 5 MB limit, image/* types) with upload/read/service-role policies
- Created and deployed supabase/functions/recognize-products/index.ts:
  - Same JWT + RLS auth pattern as classify-expense (company_id derived from documents, never client-supplied)
  - Local regex normalization + batch AI normalization via mistral-7b-instruct:free (falls back to regex on failure)
  - Fuzzy product match via find_product_by_similarity() RPC (threshold 0.35)
  - Creates new product when no match; handles unique constraint conflicts with fallback re-fetch
  - Updates document_items.product_id, matched_automatically=true, confidence_score
  - Inserts product_prices record per item (unit_price or line_total/quantity)
  - Fire-and-forget image generation: Pollinations.ai flux model 512×512 → Supabase Storage → products.image_url
- Created supabase/migrations/20260423_classify_expense_confidence.sql and deployed classify-expense edge function:
  - Adds category_confidence TEXT CHECK ('high'|'medium'|'low') column to expenses
  - Assigns category_id + confidence to expenses; company_id derived from DB, never client-supplied
- Updated lib/services/extraction_service.dart:
  - Chains classify-expense then recognize-products fire-and-forget after process-document succeeds (both non-blocking)
- Created Flutter data layer for products feature:
  - lib/features/products/data/models/product_model.dart — immutable, fromJson/toJson/copyWith
  - lib/features/products/data/models/product_price_model.dart — immutable, fromJson
  - lib/features/products/data/repositories/product_repository.dart — fetchProducts (search+category filter), fetchProductById, fetchPriceHistory, fetchCategories
  - lib/features/products/providers/product_providers.dart — productsProvider, productDetailProvider.family, productPriceHistoryProvider.family, productCategoriesProvider; productSearchQueryProvider + productCategoryFilterProvider StateProviders
- Created lib/features/products/presentation/screens/product_list_screen.dart:
  - 2-column SliverGrid, debounced search bar (400ms), horizontal animated category chips
  - CachedNetworkImage product cards with placeholder; skeleton loading, empty state, error state
- Created lib/features/products/presentation/screens/product_detail_screen.dart:
  - SliverAppBar hero image (CachedNetworkImage with fallback)
  - Product metadata chips (unit price, unit, SKU, current stock)
  - fl_chart LineChart price history (barWidth: 2.5, area gradient, dot painters, tooltip)
  - Recent purchases list (newest-first, up to 10 rows)
- Updated lib/core/router/app_router.dart:
  - AppRoutes.products = '/products', AppRoutes.productDetail = '/products/:id'
  - GoRoute for /products (NoTransitionPage in shell) and /products/:id (fullscreen, outside shell)
- Updated lib/shared/widgets/main_scaffold.dart: products added as tab index 5
- Updated floating_navigation_pill.dart: tab 4 renamed Suppliers (storefront icon), tab 5 added Stock (inventory_2 icon)
- Repaired supabase migration history desync:
  - All 15 pre-existing migrations marked applied via supabase migration repair --status applied
  - 20260424 applied manually in SQL Editor then marked applied
  - Duplicate 20260330_create_registration_tables is a known local-only artifact; does not block future pushes

### 2026-04-26
- Hardened process-document edge function against hallucination:
  - Strict confidence-schema extraction (each field returns {value, confidence})
  - OCR transcript grounding: supplier_name nulled if not found in raw OCR text
  - Confidence threshold lowered to 0.3 (free-tier VLM returns mid-range scores)
  - document_number regex relaxed to accept any string ≥ 2 chars (Spanish invoice formats)
  - Per-document log prefix [Extraction][doc=...][file=...] on all 4 key log points
  - No-signal guard: marks document flagged instead of persisting all-null extraction
  - Deployed to production (project qbvfeizmcuctmhrxkvbx, exit 0)
- Fixed document preview pipeline:
  - documentPreviewUrlProvider reverted to raw HTTP getSignedUrl (Supabase SDK rewrites host → 404)
  - getSignedUrl hardened: handles both signedURL/signedUrl response keys, relative and absolute URLs, logs raw response for debugging
  - isPdf extended: fileType == 'application/pdf' || fileType == 'pdf' || fileName.endsWith('.pdf')
  - StorageService.uploadDocument now generates 1-year signed URL immediately post-upload; stored as file_url in DB and optimistic model — preview is instant on re-open
- Replaced broken PDF thumbnail with tappable card + fullscreen viewer:
  - _PdfPreviewCard: shows PDF icon + filename, downloads bytes on tap
  - _PdfViewerPage: fullscreen PdfViewPinch with close button
  - documentPdfBytesProvider: simple HTTP GET via signed URL (no broken ref.watch-in-async pattern)
- DocumentModel updated:
  - Added filePath field (reads file_path from DB)
  - All 6 extracted fields (supplier, type, number, date, total, tax, currency) resolve with extraction_clean JSONB fallback
  - displayTitle returns 'Unknown supplier' instead of filename when supplier is null
  - copyWith updated with filePath
- Document detail sheet metadata now always shows all rows (supplier, type, doc#, date, total, tax) regardless of null state
- Provider invalidation after extraction: ref.invalidate on documentsProvider + documentDetailProvider
- Created lib/services/extraction_service.dart: stateless isolated extraction trigger wrapper

### 2026-04-22
- Added migration supabase/migrations/20260422_expenses_and_categories.sql
  - new categories table
  - new expenses table
  - documents.expense_id FK
  - RLS policies with user_company_ids()
  - seeded default categories and new-company trigger
- Updated expense category model/service to support:
  - color_hex
  - parent_id
  - sort_order
  - is_active
  - category summary aggregation model
- Updated expense form UI with category color-dot labels
- Fixed runtime crash selecting non-existent documents.supplier_name
- Fixed expense upload path to convert PDF->PNG before storage upload in submitExpenseFlow

## 14. Prioritized Next Steps
1. Runtime-verify the deployed Sales/POS flow: `/sales`, `/sales/import`, `/sales/connect-pos`, country filtering, Custom POS pending configuration, coming-soon request persistence, friendly missing-function/error messages, realtime POS status refresh, and no cross-tenant visibility between two companies
2. Runtime-verify the applied Supabase security migrations: dashboard stats lockdown, realtime exposure hardening, forced RLS on expenses/categories/supplier aliases, audit logging, and document delete cleanup hardening
3. Execute `supabase/testing/p4_1_rls_storage_isolation.sql` in the Supabase SQL Editor or a disposable staging database and fix any `P4.1 failed:` findings
4. Extend P4.1 coverage to exposed tenant RPCs with wrong `p_company_id` fixtures, including anomaly/category/document management RPCs and the Sales/POS RPC/function surface
5. Runtime-test audit creation/redaction for document delete, signed URL generation, AI requests, POS connection requests, role/member changes, company settings changes, anomaly resolution, category overrides, and storage policy failures
6. Run on-device delete verification: cancel confirmation, optional local-auth unavailable emulator path, successful delete, storage-missing path, storage failure, RLS/permission denied, and double-tap prevention
7. Runtime-test Edge Function P3.4/P3.5 hardening: oversized payload rejection, repeated-request rate limiting, JWT enforcement, classifier behavior, and no raw upstream error leakage
8. Redeploy `recognize-products` if the latest deployed version does not include the `supplier_id` patch, anomaly detection hook, P3.4 request guards, and P4.4 audit events
9. Verify the anomaly engine with a known product (e.g. Campari): upload/recognize a higher-priced supplier invoice and confirm `price_anomalies` receives price spike/supplier overpricing rows scoped to the active company
10. Verify intelligence analytics and dashboard metrics now return tenant-scoped data: `v_category_intelligence`, `v_top_products_by_spend`, dashboard IntelligenceSection cards, and the new Expenses/Results/Sales/Documents `DashboardIntelligenceGrid`
11. Verify category propagation/backfill on a known supplier with uncategorized sibling documents (e.g. Escola Vins) and confirm user-selected categories are not overwritten
12. Re-extract or re-finalize the previously flagged PDFs affected by the 2026-06-06 UUID issue and confirm the parent document moves out of the UUID-error notes path while extracted products remain visible
13. Run end-to-end verification for the async expense upload path with both image and PDF inputs: confirm immediate navigation, live processing state, `rendered_image_url` persistence, `extraction_started_at` guard behavior, background completion/flagged transitions, and successful line-item/product recognition
14. Verify on-device that a PDF upload produces a rendered image under `company_id/document_id`, invokes `process-document` with a non-null imageUrl, and reaches OpenRouter successfully
15. Verify on-device that known `ALBARÁN` samples persist as `delivery_note`, known `FACTURA` samples persist as `invoice`, and low-confidence classifications trigger the fallback classifier without leaving document_type as `unknown`
16. Resolve the current P4.2 forbidden-pattern gate failures by removing Flutter OpenRouter duplicate-merge usage, removing generic document `getPublicUrl()` fallback, and replacing one-year document signed URLs with short-lived on-demand URLs
17. Run the full P4.2 workflow in CI after the known forbidden-pattern findings and Flutter analyzer debt are fixed, then mark P4.2 green
18. Get release-owner/security-reviewer sign-off on `doc/security/release_security_checklist.md` before the next production deploy
19. Build expense tracker screen using category summary aggregation and totals (aggregation provider already exists)
20. Re-trigger extraction on existing documents uploaded before 2026-04-26 and before the 20260510 product migration so old rows gain product_prices, aliases, normalized descriptions, richer product/category links, and anomaly history
21. Add manual review flow for ambiguous product matches instead of always falling through to product creation when confidence is weak
22. Remove supabase.functions.invoke('process-document') path from app or formally update DEC-006 / Section 7 to match the deployed Edge-Function architecture
23. Add extraction retry and idempotency guardrails (network failures, partial updates)
24. Remove the remaining pre-form PDF bottleneck by stopping camera_upload_service.dart from eagerly reading large PDFs into memory before navigation; move PDF byte loading later or stream from path
25. Add product editing UI: update unit_price, unit_type, category, stock level
26. Clean up duplicate 20260330_create_registration_tables local migration file and the invalid `20260517b_category_propagation.sql` filename so future CLI migration workflows are less fragile
27. Reconcile older pending local Supabase migrations before using broad `npx supabase db push`; today only `20260613` was directly applied and repaired as applied
28. Add integration tests for:
    - tenant isolation per table
    - expense upload end-to-end
  - Sales/POS connection request tenant isolation and no-fake-integration behavior
    - duplicate invoice guard (unique, duplicate, and analytics exclusion cases)
    - product recognition pipeline (match / create / price insert)
    - product alias matching / candidate selection / price-history upsert
    - price anomaly engine (spike, supplier overpricing, quantity anomaly, duplicate fingerprint, tenant isolation)
29. Move AI key handling to secure backend pattern before production rollout
30. Implement `ANIMATION_AUDIT.md` Phase 2: extend `AppMotion` with the premium fintech token aliases and add shared motion primitives under `lib/shared/motion/` (`MotionConfig`, reduced-motion helpers, `AppPressable`, `FadeSlideIn`, `StaggeredList`, `AnimatedValue`, `AnimatedStatusSwitcher`)
31. Implement `ANIMATION_AUDIT.md` Phase 3 consolidation: migrate remaining floating nav, legacy scanner sheet rows, and generic bottom sheets onto shared motion primitives; the new FAB overlay already has local premium motion and should be folded into shared primitives later without changing callbacks
32. Implement `ANIMATION_AUDIT.md` Phase 4-6: dashboard period/chart/value polish, scanner/upload state polish, and document/product/supplier status/chart transitions; avoid reanimating realtime rows and do not touch extraction internals
33. Run motion QA from `ANIMATION_AUDIT.md`: reduced-motion behavior, Android emulator/device jank check, FAB open/close smoothness, scanner flow smoke test, document realtime status transitions, and focused analyzer checks for touched UI files
34. On-device visual QA for the 2026-06-01 glass shell navigation: confirm four-icon layout, centered FAB overlap, safe-area spacing, route taps, Dashboard/Documents FAB overlays, and Product/Stock access through existing routed actions
35. On-device visual QA for the 2026-06-03 Documents search bar refresh: confirm pill sizing, icon/text alignment, focus shadow lift, and that the existing debounced search flow still runs through `_searchController` + `_onSearchChanged` unchanged
36. Runtime-verify the 2026-06-03 dashboard intelligence data-chain fix with real tenant data: upload/use an invoice with supplier La Ribera and items Campari/Gin/Wine, confirm Documents extracted, Products/product price history updated, Drinks category spend appears, Top Products includes Campari, Supplier Intelligence remains connected, Review Center only contains uncertain items, and switching company shows no leaked intelligence rows

## 15. Operational Update Protocol
When command is: Update PROJECT_CONTEXT.md
- Modify existing file; never rewrite from scratch
- Append a new dated item under Recent Changes
- Update these sections in place:
  - Current State
  - Prioritized Next Steps
  - Issues Log (if new defect/regression discovered)
- Keep decisions immutable unless explicitly superseded; if superseded:
  - mark old decision as Superseded
  - add replacement decision with rationale

## 16. Quick Verification Checklist
- Is every new table company-scoped and protected by RLS?
- Does every app query include company_id or rely on equivalent secure server enforcement?
- Does expense upload still open form before upload?
- Is extraction pipeline aligned with DEC-006 (no Edge Functions)?
- Were new bugs logged with ISSUE-id, cause, fix, and status?
