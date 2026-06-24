# Tenant Data Exposure Triage Checklist

## Purpose

Triage suspected cross-tenant access in Supabase Postgres, Storage, Realtime, Edge Functions, or Flutter client queries.

## Severity

Treat as Critical until proven otherwise. Any confirmed Company A access to Company B data is a tenant isolation incident.

## Intake

1. Record reporter, timestamp, environment, affected user ID, company ID, route/screen/function, and correlation ID.
2. Capture redacted screenshots or logs. Do not copy raw document content, OCR text, signed URLs, or secrets.
3. Identify the data class: document metadata, document binary, expenses, products, suppliers, sales, dashboard stats, anomalies, realtime payload, or audit logs.
4. Identify whether the issue is read, insert, update, delete, storage object access, realtime broadcast, or RPC execution.

## Containment

1. Disable the affected feature path if active exposure is ongoing.
2. Revoke direct access to unsafe views or tables if exposure is through grants.
3. Apply emergency RLS/storage policy tightening if the vulnerable path is confirmed.
4. Pause non-security deployments until impact is bounded.

## Database Checks

1. Verify target tables have `company_id`.
2. Verify RLS is enabled and forced.
3. Verify policies use `company_id = ANY(public.user_company_ids())` or another approved tenant-membership check.
4. Verify views use `security_invoker = true` or secure tenant-filtered wrappers.
5. Verify RPCs reject wrong `p_company_id` for authenticated callers.
6. Run the P4.1 RLS/storage isolation harness in a disposable or staging database when available.

## Storage Checks

1. Verify `documents` bucket is private.
2. Verify object paths follow `company_id/document_id/file.ext`.
3. Verify storage policies enforce the first path segment against active company membership.
4. Verify DELETE/UPDATE policies require the intended owner/admin role if applicable.
5. Verify no document path is accessible through public URL fallback.

## Edge Function Checks

1. Verify the function requires `Authorization`.
2. Verify the function validates `auth.getUser()`.
3. Verify tenant context is derived from RLS-visible database rows, not from client-provided company ID.
4. Verify service-role clients are used only after tenant authorization.
5. Verify logs are redacted.

## Flutter Checks

1. Verify client queries include explicit `.eq('company_id', companyId)` where applicable.
2. Verify no stale company context is reused after account/company switch.
3. Verify no public document URL or long-lived signed URL is persisted.
4. Verify realtime subscriptions include tenant filters.

## Impact Assessment

1. List affected companies, users, tables, objects, and time window.
2. Determine whether data was only visible, or also modified/deleted.
3. Determine whether external systems received tenant data.
4. Preserve minimal evidence required for root-cause analysis.

## Recovery Validation

1. Reproduce the original report with the same actor and confirm access is denied.
2. Confirm expected same-tenant access still works.
3. Re-run relevant RLS/storage/RPC tests.
4. Confirm P4.2 security gates still pass or have documented blockers.

## Closure Criteria

- Root cause is identified.
- Affected tenant scope is bounded.
- Fix is deployed or release-blocked.
- Cross-tenant regression test exists or is added.
- Customer/legal notification decision is documented.