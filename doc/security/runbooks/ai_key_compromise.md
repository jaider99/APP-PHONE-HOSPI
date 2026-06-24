# AI Key Compromise Runbook

## Purpose

Respond when an OpenRouter key or any third-party AI credential may have been exposed through Flutter builds, logs, CI variables, local files, tickets, screenshots, or repository history.

## Severity

Treat as Critical when a key may have shipped in a Flutter build or appeared in a shared channel. Treat as High when exposure is limited to a restricted internal system but cannot be fully disproven.

## Immediate Triage

1. Record the report source, environment, build version, timestamp, and suspected key name.
2. Do not paste the secret into the incident record.
3. Identify where the key appeared: Flutter dart-define, Edge Function secret, CI variable, local script, logs, or documentation.
4. Check whether `lib/` contains `OPENROUTER_API_KEY` or direct `openrouter.ai/api` usage.
5. Check whether the P4.2 forbidden-pattern gate is failing on AI secret patterns.

## Containment

1. Rotate the OpenRouter key immediately if it may have shipped to any Flutter build or external artifact.
2. Remove the exposed key from CI variables, local launch configs, build scripts, and shared notes.
3. Recreate only the server-side Supabase Edge Function secret with the new key.
4. Disable or rate-limit affected AI workflows if abuse is suspected.
5. Block non-security production releases until Flutter no longer contains AI secrets or direct AI HTTP calls.

## Investigation

1. Identify all builds that could include the key.
2. Review OpenRouter usage logs for abnormal request volume, unknown referers, unusual models, or unexpected geographies.
3. Check whether raw OCR text, document content, supplier data, prices, or customer identifiers were sent outside the approved Edge Function path.
4. Review recent commits touching `duplicate_merge_service.dart`, extraction services, Edge Functions, and environment config.
5. Verify whether the compromised key had access beyond the intended OpenRouter project/account.

## Eradication

1. Remove direct Flutter AI calls.
2. Keep OpenRouter access only inside Supabase Edge Functions.
3. Edge Functions must validate JWT, fetch tenant data through RLS, enforce same-company inputs, and minimize AI payloads.
4. Ensure P4.2 grep gates pass for `OPENROUTER_API_KEY` and `openrouter.ai/api` under `lib/`.

## Recovery Validation

1. Old key is disabled and no longer accepted by OpenRouter.
2. Edge Functions can call OpenRouter with the new server-side secret.
3. Flutter builds contain no OpenRouter key, OpenRouter URL, or direct AI HTTP path.
4. Duplicate merge and extraction flows still work through heuristic or server-side paths.
5. OpenRouter usage returns to expected volume.

## Communication

Notify the release owner, backend/Supabase engineer, Flutter engineer, security reviewer, and product owner. Customer notification depends on confirmed data sent to unauthorized systems, legal review, and contractual obligations.

## Closure Criteria

- Key rotation is complete.
- Direct Flutter AI usage is removed or release-blocked.
- Affected builds and environments are listed.
- Abuse review is complete.
- P4.2 forbidden-pattern gate passes for AI patterns.