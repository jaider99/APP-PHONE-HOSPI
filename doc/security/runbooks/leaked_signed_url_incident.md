# Leaked Signed URL Incident Runbook

## Purpose

Respond to suspected leakage of document signed URLs, public document URLs, or logs containing document preview links.

## Severity

Treat as High by default. Escalate to Critical if the URL grants access to documents across tenants, was published externally, or the `documents` bucket is public.

## Immediate Triage

1. Record the report source, timestamp, environment, and reporter.
2. Capture only redacted evidence. Do not paste full URLs or tokens into the incident record.
3. Identify the affected bucket, object path prefix, company ID, document ID, and URL TTL if available.
4. Check whether the URL is still valid from an unauthenticated browser session.
5. Check whether the object belongs to the `documents` bucket and whether the path follows `company_id/document_id/file.ext`.
6. Search logs for the redacted URL fingerprint, document ID, and request correlation ID.

## Containment

1. If the `documents` bucket is public, apply the private-bucket storage lockdown migration before normal releases continue.
2. Remove or redact leaked URLs from support tickets, chat, logs, and screenshots where possible.
3. Revoke or shorten long-lived preview URL behavior by deploying the short-lived signed URL flow.
4. If a specific object is exposed, rotate the object path by re-uploading under a new document path and updating `documents.file_path` after authorization review.
5. Temporarily disable document sharing/preview features if fresh leaks continue.

## Investigation

1. Determine whether the URL was created by Flutter upload, document preview, a support action, or an Edge Function.
2. Confirm whether `documents.file_url` contains a persisted signed URL.
3. Confirm whether app logs contain signed URLs, URL query strings, storage response bodies, or raw document paths.
4. Review recent changes touching storage policies, `StorageService`, document preview providers, or Edge Function signed URL generation.
5. Verify whether any other companies' document paths were exposed.

## Eradication

1. Remove durable signed URL persistence for private document files.
2. Use signed URLs only on demand with a 60-300 second TTL.
3. Ensure logs redact signed URLs, query strings, JWTs, document paths, and storage response bodies.
4. Ensure the P4.2 forbidden-pattern gate blocks long signed URL TTLs and document `getPublicUrl()` use.

## Recovery Validation

1. An unauthenticated request to the old URL fails.
2. An authenticated Company A user cannot access a Company B document path.
3. An authenticated Company A user can preview its own document through a short-lived URL.
4. New upload records store `file_path`, not durable signed URLs.
5. Logs from a preview flow contain no signed URL or token.

## Communication

Notify the release owner, backend/Supabase engineer, security reviewer, and customer support lead. Customer notification depends on confirmed access, affected records, regulatory obligations, and legal review.

## Closure Criteria

- Exposure window is documented.
- Affected companies/documents are identified or bounded.
- Storage and logging fixes are deployed or tracked as release blockers.
- P4.2 gates pass for signed URL and public URL patterns.
- Post-incident action items have owners and dates.