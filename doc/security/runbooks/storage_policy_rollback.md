# Storage Policy Rollback Plan

## Purpose

Provide a safe rollback path for Supabase Storage policy changes without reopening public or cross-tenant document access.

## Rollback Principle

Never roll back to bucket-only policies or a public `documents` bucket. If a new storage policy breaks previews or uploads, roll forward to the last known private, tenant-scoped policy set.

## Before Changing Storage Policies

1. Confirm the migration name, target environment, and release owner.
2. Export the current `storage.buckets` row for `documents`.
3. Export current `storage.objects` policies and helper functions used by those policies.
4. Confirm the expected path format: `company_id/document_id/file.ext`.
5. Confirm Flutter preview uses signed URLs and stores paths, not durable signed URLs.
6. Prepare smoke tests for Company A own-path access and Company B cross-path denial.

## Safe Baseline

The safe baseline for `documents` is:

- `storage.buckets.public = false`
- SELECT/INSERT/UPDATE policies enforce active membership in the first path segment
- DELETE policy enforces the intended admin/owner rule if configured
- No policy grants access solely on `bucket_id = 'documents'`
- No public URL fallback for document previews

## Rollback Steps

1. Stop new production deploys except storage hotfixes.
2. Identify the failing operation: upload, preview, signed URL, update, delete, or realtime-driven refresh.
3. If customer data exposure is possible, disable the affected feature path before changing policies.
4. Apply a private tenant-scoped rollback migration instead of manually editing policies when possible.
5. Keep `documents` private throughout rollback.
6. Re-run storage smoke tests with two companies.
7. Re-run P4.1 storage isolation checks when database tooling is available.

## Rollback Validation

1. Unauthenticated document object request fails.
2. Company A cannot read, sign, upload, update, or delete Company B paths.
3. Company A can upload and preview its own document path.
4. Product image flows remain unaffected if they use a separate public bucket.
5. Logs contain no signed URLs, query strings, or raw storage response bodies.

## Emergency Deny Option

If active cross-tenant storage access is confirmed and no safe policy fix is ready, temporarily deny document storage access by replacing `documents` bucket policies with authenticated-deny policies, keeping the bucket private, and communicating preview/upload outage risk to support.

## Closure Criteria

- Safe private tenant-scoped policies are active.
- Smoke tests pass.
- Customer-facing impact is documented.
- The failing migration is repaired or superseded.
- Release owner signs off before normal deploys resume.