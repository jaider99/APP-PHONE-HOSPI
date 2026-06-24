# Multi-Tenant Security Test Plan

Date: 2026-06-04
Scope: verification plan only; no tests executed by this document

## Objective

Verify that no authenticated user, unauthenticated caller, Edge Function, storage path, realtime channel, or privileged RPC can access or mutate another company's data.

## Test Principles

- Use at least two tenant fixtures: Company A and Company B.
- Use distinct users for each tenant and at least one user with no membership.
- Treat the database as the source of truth for tenant identity.
- Test both read and write isolation.
- Test anonymous and authenticated storage access separately.
- Test privileged RPCs and Edge Functions as abuse cases, not just happy paths.

## Required Fixtures

- Tenant A owner
- Tenant B owner
- Tenant A manager or member
- Tenant B manager or member
- Unaffiliated authenticated user
- Representative tenant rows for documents, document_items, expenses, categories, providers, products, supplier_aliases, product_prices, price_anomalies, and review_items
- Storage objects for both tenants in documents and products buckets

## Test Suite 1: Metadata and RLS Baseline

Goal: prove every tenant table is protected consistently.

Checks:

1. Enumerate every public table with company_id.
2. Assert RLS is enabled on each.
3. Assert FORCE RLS is enabled on each.
4. Assert at least one policy exists on each.
5. Enumerate all SECURITY DEFINER and SECURITY INVOKER functions.
6. Review each SECURITY DEFINER function for one of these patterns:
   - derives actor from auth.uid()
   - proves p_company_id belongs to public.user_company_ids()
   - is restricted to service_role only

Expected result:

- No tenant table missing RLS
- No tenant table missing FORCE RLS
- No SECURITY DEFINER function trusting caller-supplied user identity

## Test Suite 2: Cross-Tenant Table Access

Goal: prove authenticated app-role access cannot cross company boundaries.

Run as Tenant A user and assert all of the following against Tenant B rows:

1. SELECT returns zero rows from providers
2. SELECT returns zero rows from products
3. SELECT returns zero rows from documents
4. SELECT returns zero rows from document_items
5. SELECT returns zero rows from categories
6. SELECT returns zero rows from expenses
7. SELECT returns zero rows from supplier_aliases
8. SELECT returns zero rows from product_prices
9. SELECT returns zero rows from price_anomalies
10. SELECT returns zero rows from review_items
11. UPDATE affects zero rows
12. DELETE affects zero rows
13. INSERT with company_id = Company B is rejected

Repeat from Tenant B toward Tenant A.

Expected result:

- All cross-tenant reads return nothing
- All cross-tenant writes fail or affect zero rows

## Test Suite 3: Registration RPC Abuse Tests

Goal: prove privileged onboarding RPCs cannot be used to act on another user.

Target functions:

- public.create_company_with_owner
- public.join_company_as_manager

Abuse cases:

1. Authenticate as User A and call create_company_with_owner with p_user_id = User B.
2. Authenticate as User A and call create_company_with_owner with p_user_id = a random existing auth user not equal to auth.uid().
3. Authenticate as User A and call join_company_as_manager with p_user_id = User B.
4. Authenticate as User A and call join_company_as_manager with a valid invite code and p_user_id = another user.
5. After each call, verify that no company_users, profiles, companies, or user_preferences rows were altered for the other user.

Expected result:

- All such calls are rejected.
- No rows are created or mutated for any user other than auth.uid().

## Test Suite 4: Storage Confidentiality

Goal: prove tenant files cannot be fetched without tenant authorization.

### 4A. Authenticated storage row policy tests

1. As Tenant A user, list or select storage.objects rows for Tenant B document paths.
2. Attempt insert, update, or delete against Tenant B document paths.
3. Repeat for the products bucket if product images are intended to be tenant-private.

Expected result:

- Tenant B rows are not visible or mutable by Tenant A.

### 4B. Anonymous and public object fetch tests

1. Attempt HTTP GET of a known Tenant A document object without Authorization.
2. Attempt HTTP GET of a known Tenant B document object without Authorization.
3. Attempt HTTP GET of a guessed document path without Authorization.
4. Attempt HTTP GET of a product image path without Authorization.

Expected result:

- documents bucket objects must not be retrievable anonymously
- if products bucket is intentionally public, document and approve that exception explicitly

### 4C. Signed URL boundary tests

1. Generate a signed URL as Tenant A for a Tenant A document path.
2. Confirm it works only until expiration.
3. Confirm Tenant A cannot generate a signed URL for Tenant B paths.
4. Verify signed URLs are not logged into audit payloads, debug logs, or user-visible notes.

Expected result:

- Signed access is tenant-scoped and time-limited.

## Test Suite 5: Edge Function Authorization

Goal: prove service-role escalation inside Edge Functions never crosses company boundaries.

Target functions:

- process-document
- recognize-products
- classify-expense
- classify-document-type

Abuse cases:

1. Tenant A calls process-document for a Tenant B document ID.
2. Tenant A calls recognize-products for a Tenant B document ID.
3. Tenant A calls classify-expense for a Tenant B document ID.
4. Unauthenticated caller invokes each function.
5. Authenticated but unaffiliated user invokes each function with a valid document ID from another tenant.

Expected result:

- Functions return 401 or 403.
- No Company B rows are inserted, updated, or deleted.
- No Company B audit events are written on behalf of Tenant A except denied security logs where appropriate.

## Test Suite 6: Realtime Isolation

Goal: prove tenant-specific subscriptions receive only tenant-specific events.

Checks:

1. Tenant A subscribes to documents changes filtered by company_id = Company A.
2. Mutate Company B documents and confirm Tenant A receives no event.
3. Repeat for document_items, products, product_prices, categories, review_items, and company_users pending-approval flows.
4. Confirm user_id-scoped pending approval subscriptions do not leak other users' company_users updates.

Expected result:

- No cross-tenant realtime payloads are delivered.

## Test Suite 7: Analytics and View Isolation

Goal: prove tenant-facing views never expose another tenant's aggregates.

Target views:

- dashboard_stats_secure
- v_category_intelligence
- v_top_products_by_spend
- v_supplier_intelligence

Checks:

1. As Tenant A, query each view and verify only Company A rows are returned.
2. Attempt direct read from raw dashboard_stats as authenticated.
3. Compare aggregate totals against known seeded fixture values.

Expected result:

- Only tenant rows are visible.
- Raw dashboard_stats is not readable by app roles.

## Test Suite 8: Audit Logging and Sensitive Operations

Goal: prove audit controls do not leak secrets and still preserve tenant scope.

Checks:

1. Execute a permitted sensitive action and confirm activity_logs entry is tenant-scoped.
2. Execute a denied sensitive action and confirm outcome = denied.
3. Verify metadata redaction removes signed URLs, tokens, JWTs, raw OCR text, AI responses, and file paths where intended.
4. Confirm one tenant cannot read another tenant's activity logs.

Expected result:

- Audit logs are readable only within the tenant.
- Sensitive payloads are redacted.

## Test Suite 9: Regression Harness Improvements

Add these cases to automated SQL or CI coverage:

1. Registration RPC impersonation tests using mismatched p_user_id versus auth.uid().
2. Anonymous fetch test for documents bucket objects.
3. FORCE RLS assertion for every newly added tenant table, including review_items.
4. Product bucket public or private decision test based on the intended security model.
5. Edge Function denial tests for cross-tenant document IDs.

## Suggested Execution Order

1. Metadata and RLS baseline
2. Cross-tenant table access
3. Registration RPC abuse tests
4. Anonymous and authenticated storage tests
5. Edge Function authorization tests
6. Realtime isolation tests
7. Analytics and view isolation tests
8. Audit logging verification

## Exit Criteria

HospiDash should be considered multi-tenant ready only when all of the following are true:

1. No critical or high findings remain open.
2. Every tenant table has RLS enabled, FORCE RLS enabled, and at least one tenant policy.
3. Registration and membership RPCs are bound to auth.uid() server-side.
4. Document objects are not anonymously retrievable.
5. Edge Functions reject cross-tenant document IDs with no side effects.
6. Realtime and analytics surfaces show zero cross-tenant leakage.
7. The expanded regression suite passes in CI on every schema-affecting change.
