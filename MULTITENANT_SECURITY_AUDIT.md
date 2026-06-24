# Multi-Tenant Security Audit

Date: 2026-06-04
Scope: repository-backed audit only; no fixes applied
Method: read-only review of Supabase migrations, Flutter query surfaces, storage usage, Edge Functions, realtime subscriptions, and tenant test harnesses

## Executive Summary

HospiDash has a strong multi-tenant foundation. Most tenant tables are company-scoped, the Flutter app generally resolves company context centrally, major Edge Functions derive company access from RLS-visible rows before using service-role access, and the repo contains a real tenant-isolation regression harness.

However, the current repository state is not production-ready for strict multi-tenant isolation because two confirmed issues materially weaken the boundary:

1. A critical authorization flaw exists in the registration RPC layer: SECURITY DEFINER functions trust a caller-supplied user ID instead of binding actions to auth.uid().
2. The documents storage bucket is explicitly configured as public in a later migration and is not reverted by later migrations, which undermines document confidentiality if object paths are obtained.

Additional hardening and verification gaps remain around FORCE RLS consistency for newly added tenant tables and storage/isolation regression coverage.

Production readiness verdict: Not ready for strict multi-tenant production until the critical and high findings are remediated and re-tested.

Risk rating: High

## Confirmed Findings

| ID | Severity | Area | Finding |
| --- | --- | --- | --- |
| MT-001 | Critical | Auth/RPC | SECURITY DEFINER registration RPCs trust caller-supplied p_user_id |
| MT-002 | High | Storage | documents bucket is configured public, weakening tenant file isolation |
| MT-003 | Medium | Database/RLS | review_items is tenant-scoped but not forced under RLS in repository migrations |
| MT-004 | Low | Test coverage | storage isolation regression coverage would not catch anonymous access caused by a public bucket |

## Detailed Findings

### MT-001: SECURITY DEFINER registration RPCs trust caller-supplied p_user_id

Severity: Critical

Evidence:

- In supabase/migrations/00009_multi_tenant_registration_fix.sql, public.create_company_with_owner accepts p_user_id and only verifies that the supplied UUID exists in auth.users.
- The same function then writes owner_id, company_users.user_id, user_preferences.user_id, and profiles.id/current_company_id using that supplied p_user_id.
- In the same migration, public.join_company_as_manager also accepts p_user_id, validates only existence, and inserts company_users and profile changes for that supplied user.
- Both functions are SECURITY DEFINER and are granted to authenticated.
- The earlier implementation in supabase/migrations/00003_auth_triggers.sql derived the acting user from auth.uid(), which highlights the regression.

Impact:

- Any authenticated caller who can invoke these RPCs can attempt to act on behalf of another auth.users UUID.
- create_company_with_owner can create a company owned by another user, create an owner membership for that user, update that user's current company, and overwrite profile fields.
- join_company_as_manager can create pending membership rows for another user if the invite code is known and can also alter profile fields for that target user.
- This is an authorization failure inside privileged database code, not just a missing client-side check.

Why this matters for multi-tenancy:

- Tenant identity establishment is the root of all later isolation. If company ownership or membership can be assigned to arbitrary users through a privileged RPC, the tenant boundary can be corrupted at creation time.

Affected sources:

- supabase/migrations/00009_multi_tenant_registration_fix.sql
- lib/services/registration_service.dart

### MT-002: documents bucket is configured public, weakening tenant file isolation

Severity: High

Evidence:

- supabase/migrations/00010_documents_schema_storage_fix.sql explicitly recreates the documents bucket with public = TRUE and comments that it is public so getPublicUrl works.
- The same migration temporarily replaced path-aware storage policies with bucket-only authenticated policies.
- A later migration, supabase/migrations/20260507_document_deletion_consistency.sql, restores path-aware authenticated storage policies using public.user_company_ids(), but it does not revert the bucket to private.
- lib/services/storage_service.dart stores document objects at predictable paths of the form companyId/documentId/fileName.
- The same service persists file_url/path values and can fall back to public object URLs if signed URL generation is unavailable.

Impact:

- Public bucket access bypasses storage.objects SELECT policy checks for anonymous object retrieval.
- If a document path is learned through logs, screenshots, accidental sharing, another bug, or predictable enumeration, the underlying object can be fetched without tenant membership.
- This is especially serious because the stored content includes invoices, receipts, PDFs, and rendered document imagery.

Why this matters for multi-tenancy:

- Row isolation in Postgres is not sufficient if the underlying tenant file objects are anonymously retrievable.
- This creates a second data plane outside normal RLS enforcement.

Affected sources:

- supabase/migrations/00010_documents_schema_storage_fix.sql
- supabase/migrations/20260507_document_deletion_consistency.sql
- lib/services/storage_service.dart
- lib/providers/documents_provider.dart

### MT-003: review_items is tenant-scoped but not forced under RLS in repository migrations

Severity: Medium

Evidence:

- supabase/migrations/20260602_review_center.sql creates public.review_items with company_id and enables RLS.
- That migration adds SELECT, INSERT, and UPDATE tenant policies.
- The migration does not include ALTER TABLE public.review_items FORCE ROW LEVEL SECURITY.
- The repository's own isolation harness in supabase/testing/p4_1_rls_storage_isolation.sql asserts that every public table with company_id should have FORCE RLS.

Impact:

- In normal app-role access, policy enforcement still exists.
- However, the repository's stated security baseline is FORCE RLS for tenant tables, and review_items does not meet that bar in the current migration set.
- This increases exposure to future privileged-code mistakes and creates policy inconsistency in a high-signal operational inbox that aggregates sensitive tenant review state.

Why this matters for multi-tenancy:

- Multi-tenant systems are safest when every tenant table uses the same invariant. Exceptions become future bypass candidates, especially around SECURITY DEFINER code and maintenance scripts.

Affected sources:

- supabase/migrations/20260602_review_center.sql
- supabase/testing/p4_1_rls_storage_isolation.sql

### MT-004: storage isolation regression coverage would not catch anonymous access caused by a public bucket

Severity: Low

Evidence:

- supabase/testing/p4_1_rls_storage_isolation.sql validates authenticated storage.objects isolation and explicitly seeds the documents bucket with public = false inside the test fixture.
- The test checks tenant-aware SQL visibility of storage.objects rows, not anonymous HTTP fetch behavior for public buckets.
- The production migration history includes a later documents bucket public = TRUE change that this harness would not detect.

Impact:

- The current regression harness is useful but can produce a false sense of safety around document storage confidentiality.
- A bucket-publicity regression can exist even while authenticated storage row policies still pass.

Affected sources:

- supabase/testing/p4_1_rls_storage_isolation.sql
- supabase/migrations/00010_documents_schema_storage_fix.sql

## Surface-by-Surface Assessment

### 1. Database table isolation and RLS

Observed strengths:

- Core tenant tables are company-scoped in migrations: providers, products, documents, document_items, orders, order_items, sales, expenses, categories, supplier_aliases, product_prices, product_aliases, price_anomalies, product_price_stats, product_purchase_fingerprints, document_merges, and review_items.
- The main RLS model uses public.user_company_ids() or equivalent auth.uid()-derived helpers rather than trusting client-supplied company IDs.
- FORCE RLS is present on most tenant tables, especially the primary business tables and later intelligence tables.

Observed risks:

- Newer tenant tables must be checked individually; the repo is no longer in a state where FORCE RLS can be assumed everywhere.
- SECURITY DEFINER helper and RPC usage is extensive, which is acceptable only when each function proves identity from auth.uid() or independently proves company membership.

Assessment: Mostly strong, with one critical privileged-RPC regression and one medium consistency gap.

### 2. Flutter query security

Observed strengths:

- companyIdProvider in lib/providers/company_provider.dart is the central tenant context source.
- Major repositories and providers generally include explicit .eq('company_id', companyId) filters even though RLS also exists.
- Realtime subscriptions consistently filter by company_id for document, product, dashboard, and review-center channels.
- Env validation rejects accidental use of a service-role key in Flutter via lib/core/config/env_config.dart.

Observed risks:

- Client-side company filters are defense in depth, not the true boundary; the real risk remains privileged DB and storage surfaces.

Assessment: No confirmed cross-tenant client-query bug found in the audited Flutter surfaces.

### 3. Company context and tenant switching

Observed strengths:

- switch_company in the earlier auth-trigger migration binds to auth.uid() and validates active membership before changing current_company_id.
- get_user_context and get_user_companies are server-derived and avoid client-trusted tenant claims.

Observed risks:

- The registration RPC redesign in 00009 broke the same trust model by moving from auth.uid()-derived identity to p_user_id supplied by the caller.

Assessment: Normal company switching looks sound; tenant bootstrap and invitation onboarding are not.

### 4. Storage and file isolation

Observed strengths:

- Later authenticated storage policies in 20260507_document_deletion_consistency.sql scope document paths with public.user_company_ids().
- Document deletion validates company/path alignment before calling the tenant-scoped delete_document_cascade RPC.

Observed risks:

- Public documents bucket materially weakens confidentiality.
- Long-lived signed URLs are generated and persisted in app flows, increasing blast radius if row data or logs are exposed.
- Product images are publicly readable by design; whether that is acceptable depends on whether product catalog assets are considered tenant-private business data.

Assessment: Authenticated storage row policy is reasonable; bucket confidentiality posture is not.

### 5. Edge Functions and AI pipeline

Observed strengths:

- process-document, recognize-products, and classify-expense all begin with userClient auth validation.
- Those functions fetch a document through RLS first, derive company_id from the database row, and only then instantiate a service-role client.
- Subsequent admin and service-role writes are generally scoped back to the derived company_id.
- Audit logging and rate limiting are present on major AI functions.

Observed risks:

- Because service-role clients are used, any future omission of company_id filters inside those functions becomes high impact.
- The AI pipeline depends on storage confidentiality; public buckets weaken the surrounding trust boundary.

Assessment: The current Edge Function trust pattern is broadly correct.

### 6. Realtime

Observed strengths:

- Realtime channels in Flutter consistently filter on company_id or user_id.
- review_items is added to supabase_realtime explicitly.

Observed risks:

- Realtime safety still depends on the underlying table policy posture. The review_items table should be aligned with the same FORCE RLS standard as other tenant tables.

Assessment: No direct realtime leakage was confirmed from repository code alone.

### 7. Views and analytics surfaces

Observed strengths:

- Tenant-facing analytics views such as v_category_intelligence, v_top_products_by_spend, and v_supplier_intelligence use security_invoker = true.
- dashboard_stats direct access is explicitly revoked and wrapped in dashboard_stats_secure.

Observed risks:

- The codebase has many SECURITY DEFINER functions; every new function must be reviewed as a privileged boundary.

Assessment: View security posture is materially better than the RPC posture.

## Positive Controls Verified

- The Flutter environment layer rejects service-role misuse in client configuration.
- Main tenant business tables are company-scoped and mostly forced under RLS.
- The document deletion RPC is SECURITY INVOKER and re-validates both document ID and company ID.
- AI Edge Functions derive tenant context from RLS-visible rows rather than trusting client-supplied company identifiers.
- A real tenant-isolation SQL regression harness exists in the repo.

## Assumptions and Limits

- This audit is based on repository state, not a live Supabase metadata dump. If production diverges from migrations, live state may differ.
- No live anonymous bucket fetch was executed in this audit; the storage finding is based on migration semantics and app path construction.
- No destructive or corrective actions were taken.

## Recommended Remediation Order

1. Fix the registration RPC authorization flaw by binding privileged actions to auth.uid() server-side and rejecting caller-supplied identity override.
2. Restore private confidentiality for document objects and require signed access only.
3. Bring review_items to the same FORCE RLS baseline as the other tenant tables.
4. Expand the automated isolation suite to cover anonymous and public storage access plus privileged RPC abuse cases.

## Bottom Line

HospiDash is close to a sound multi-tenant architecture, but it currently has one critical tenant-bootstrap authorization flaw and one high-severity document-storage confidentiality flaw. Until those are fixed and regression-tested, strict multi-tenant production deployment is not advisable.
