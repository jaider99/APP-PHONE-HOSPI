# Release Security Checklist

Use this checklist before production deploys. A release owner must sign off before a non-security production release.

## Release Metadata

- Release version:
- Date:
- Release owner:
- Security reviewer:
- Target environment:
- Related migrations:
- Related Edge Functions:

## Gate A: Critical Security

- [ ] `process-document` requires JWT and derives tenant context through RLS.
- [ ] No Flutter code contains `OPENROUTER_API_KEY`.
- [ ] No Flutter code directly calls `openrouter.ai/api`.
- [ ] No Flutter code contains `SUPABASE_SERVICE_ROLE_KEY`.
- [ ] `documents` bucket is private.
- [ ] Document storage policies are tenant path-scoped.
- [ ] Cross-tenant document processing test passes or has a documented blocker.

## Gate B: High-Risk Closure

- [ ] Document signed URL TTL is 300 seconds or less.
- [ ] Signed URLs are generated on demand and are not persisted in document rows.
- [ ] Document public URL fallback is removed.
- [ ] Sensitive logs are redacted.
- [ ] Tenant tables are queried with explicit company filters where applicable.
- [ ] Raw `dashboard_stats` access is revoked from app roles.

## Gate C: Preventive Controls

- [ ] P4.1 RLS/storage isolation harness has been run in a database environment or blocker is documented.
- [ ] P4.2 CI gates pass or every red gate is explicitly release-blocking.
- [ ] Edge Functions pass `deno check`.
- [ ] Flutter analyzer status is reviewed.
- [ ] Dependency freshness and vulnerability scan results are reviewed.
- [ ] Incident runbooks are available under `doc/security/`.

## Migration Checks

- [ ] Every new tenant table has `company_id`.
- [ ] Every tenant table has RLS enabled and forced.
- [ ] Every tenant table has at least one tenant-scoped policy.
- [ ] Every exposed tenant RPC rejects wrong `p_company_id`.
- [ ] Rollback plan exists for storage/auth/RLS migrations.

## Logging Checks

- [ ] Logs do not contain JWTs, API keys, signed URLs, URL query strings, raw OCR text, raw AI responses, or document contents.
- [ ] Logs use correlation IDs and sanitized operation metadata.
- [ ] Error responses do not expose upstream AI response bodies or secrets.

## Sign-Off

- [ ] Release owner approves.
- [ ] Security reviewer approves.
- [ ] Support is aware of user-visible security changes.
- [ ] Rollback owner is assigned.

## Notes

Record exceptions here. Exceptions must include owner, risk, expiration date, and follow-up issue.