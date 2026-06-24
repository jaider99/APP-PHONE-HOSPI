# HospiDash Security Runbooks

This folder contains operational security runbooks for HospiDash production support.

Use these documents during incidents, release reviews, and security drills. They are intentionally procedural: follow the checklists, record decisions, and preserve evidence without copying secrets, signed URLs, raw OCR text, AI payloads, or customer financial data into tickets or chat.

## Runbooks

- [Leaked Signed URL Incident](runbooks/leaked_signed_url_incident.md)
- [AI Key Compromise](runbooks/ai_key_compromise.md)
- [Tenant Data Exposure Triage](runbooks/tenant_data_exposure_triage.md)
- [Storage Policy Rollback](runbooks/storage_policy_rollback.md)
- [Release Security Checklist](release_security_checklist.md)

## Rules

- Treat document files, signed URLs, raw OCR, AI payloads, supplier names, prices, and tenant IDs as sensitive.
- Never paste secrets, JWTs, signed URLs, or raw document content into incident notes.
- Prefer redacted identifiers, correlation IDs, timestamps, company IDs, document IDs, and migration names.
- Production rollback decisions require the release owner and backend/Supabase engineer unless there is active customer data exposure.
- Any suspected cross-tenant access is a security incident until disproven.