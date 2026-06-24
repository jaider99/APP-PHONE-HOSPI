# Registration Unauthorized RPC Analysis

Date: 2026-06-15

## 1. Current registration flow

Owner registration currently runs as a three-step Flutter flow:

1. `/register/company-id` collects country, tax ID, and business type.
2. `/register/company-details` collects legal name, trade name, city, currency, and timezone.
3. `/register/user-account` collects full name, email, password, and role.
4. `RegistrationNotifier.completeStep3` calls `RegistrationService.registerAsOwner` for owners or `RegistrationService.registerAsManager` for invited managers.
5. The service calls `SupabaseAuth.signUp` first.
6. The service immediately calls a registration RPC.
7. The screen navigates to `/dashboard` for owner success or `/pending-approval` for manager success.

The failing log is on the owner path after auth signup succeeds:

```text
RegistrationService: auth user created: 433b2cd8-768d-4cfa-ae08-76da8faf2190
RegistrationService: OWNER Step 2 - RPC create_company_with_owner
RegistrationService: RPC DB error - P0001: Unauthorized
RegistrationProvider: Registration failed - RegistrationError.unknown: Unauthorized
```

## 2. Flutter RegistrationService steps

`lib/services/registration_service.dart` currently does this for owners:

1. Validates required registration state.
2. Calls `_supabase.auth.signUp(...)`.
3. Reads `authResponse.user?.id`.
4. Logs the auth user id.
5. Builds sanitized company fields.
6. Calls `_supabase.rpc('create_company_with_owner', params: {...})` immediately.
7. Passes `p_user_id: userId` in the RPC payload.
8. Parses `company_id` and returns `RegistrationResult.ownerSuccess`.
9. Only after the RPC, checks whether `authResponse.session == null` and logs email confirmation pending.

The current comment says the SECURITY DEFINER RPC works regardless of email confirmation/session state. That comment is no longer true under the current audit trigger/security posture.

Manager registration has the same timing pattern:

1. Calls `_supabase.auth.signUp(...)`.
2. Reads `authResponse.user?.id`.
3. Calls `_supabase.rpc('join_company_as_manager', params: {...})` immediately.
4. Passes `p_user_id: userId`.

## 3. Supabase Auth signup behavior

Existing `lib/services/auth_service.dart` already models Supabase signup correctly:

- If `response.user != null` and `response.session == null`, it returns `AuthResult.pendingVerification(email)`.
- If `response.session != null`, it returns `AuthResult.success(session)`.

The registration-specific service bypasses that wrapper and calls `auth.signUp` directly. It does not branch before the RPC when `authResponse.session == null`.

Live database evidence for the failed user:

```text
id: 433b2cd8-768d-4cfa-ae08-76da8faf2190
confirmed: false
email_confirmed: false
has_profile: true
has_company_user: false
```

This is consistent with email confirmation being required: Supabase created `auth.users` and the profile trigger created `profiles`, but no authenticated session existed for the immediate RPC company setup.

The linked database does not expose `auth.config`, so the setting was inferred from the actual failed user state and the app's existing signup wrapper behavior.

## 4. RPC call payload

Owner RPC payload from Flutter:

```dart
{
  'p_user_id': userId,
  'p_company_name': companyName,
  'p_legal_name': sanitizedLegalName,
  'p_tax_id': state.verifiedTaxId!,
  'p_city': _sanitizeInput(state.city!),
  'p_country': state.detectedCountry!,
  'p_currency': state.currency,
  'p_timezone': state.timezone,
  'p_business_type': state.businessType?.name ?? 'restaurant',
  'p_full_name': state.fullName!.trim(),
  'p_email': state.email!.trim(),
}
```

Manager RPC payload from Flutter:

```dart
{
  'p_user_id': userId,
  'p_invite_code': inviteCode.toUpperCase().trim(),
  'p_full_name': fullName.trim(),
  'p_email': email.trim(),
}
```

Both payloads still pass `p_user_id` from Flutter as authority.

## 5. create_company_with_owner function definition

Live definition summary:

- Schema: `public`
- Signature: `create_company_with_owner(p_user_id uuid, p_company_name text, p_legal_name text, p_tax_id text, p_city text default '', p_country text default '', p_currency text default 'EUR', p_timezone text default 'Europe/Madrid', p_business_type text default 'restaurant', p_full_name text default '', p_email text default '')`
- Returns: `jsonb`
- `SECURITY DEFINER`: true
- `search_path`: `public`
- Uses `p_user_id` directly.
- Does not call `auth.uid()`.
- Does not itself contain `RAISE EXCEPTION 'Unauthorized'`.

Live behavior:

1. Validates `auth.users` contains `p_user_id`.
2. Checks duplicate `companies.tax_id`.
3. Inserts `companies` with `owner_id = p_user_id`.
4. Inserts `company_users` with `user_id = p_user_id`, role `owner`, active `true`.
5. Upserts `user_preferences`.
6. Upserts `profiles.current_company_id`.
7. Returns company JSON.

## 6. join_company_as_manager function definition

Live definition summary:

- Schema: `public`
- Signature: `join_company_as_manager(p_user_id uuid, p_invite_code text, p_full_name text default '', p_email text default '')`
- Returns: `jsonb`
- `SECURITY DEFINER`: true
- `search_path`: `public`
- Uses `p_user_id` directly.
- Does not call `auth.uid()`.

Live behavior:

1. Validates `auth.users` contains `p_user_id`.
2. Resolves `companies.invite_code`.
3. Requires company active.
4. Rejects duplicate membership.
5. Inserts inactive manager `company_users` row.
6. Upserts `profiles`.
7. Attempts activity log insert in a best-effort block.
8. Returns pending manager JSON.

## 7. Whether RPC uses auth.uid()

The live `create_company_with_owner` and `join_company_as_manager` functions do not use `auth.uid()`.

However, a trigger fired by the owner RPC does use `auth.uid()` indirectly:

- `company_users` has `AFTER INSERT OR UPDATE` trigger `audit_company_users_sensitive_changes`.
- The trigger executes `public.audit_company_sensitive_changes()`.
- `audit_company_sensitive_changes()` calls `public.record_security_audit_event(...)`.
- `record_security_audit_event(...)` sets `v_actor_id uuid := auth.uid()`.
- If role is not an admin/service role and `v_actor_id IS NULL`, it raises `Unauthorized`.

Relevant live helper logic:

```sql
IF v_role NOT IN ('postgres', 'service_role', 'supabase_admin') THEN
  IF v_actor_id IS NULL OR NOT (p_company_id = ANY(public.user_company_ids())) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
END IF;
```

## 8. Whether RPC still accepts p_user_id

Yes. Both live RPCs still accept `p_user_id`, and Flutter passes `authResponse.user.id`.

This is a security problem after recent hardening work. The client-provided user id should not be the authority for company ownership or manager membership. The correct authority is the authenticated JWT user, `auth.uid()`.

## 9. Whether auth.uid() is null during the RPC call

For the failed owner registration, yes, the evidence points to `auth.uid()` being null in the database call:

- Auth user was created.
- The user is not email confirmed.
- No company membership was created.
- Top-level RPC does not raise `Unauthorized`.
- The audit helper reached by the `company_users` insert does raise `Unauthorized` only when `auth.uid()` is null or the authenticated user is not a company member.
- During owner registration, if the JWT were present and matched the inserted owner row, the `AFTER INSERT` audit check would see the newly inserted active membership and pass.

Therefore, the failing boundary is not the top-level function body; it is the audit trigger/helper running inside the RPC transaction without an authenticated JWT context.

## 10. Whether the session exists after signup

For the failing case, the session does not exist after signup.

The code currently does not log this before the RPC. The requested safe logs should be added before any RPC call:

```dart
AppLogger.debug('[Registration] auth user id: ${user.id}');
AppLogger.debug('[Registration] session exists: ${session != null}');
AppLogger.debug('[Registration] current user exists: ${supabase.auth.currentUser != null}');
AppLogger.debug('[Registration] access token exists: ${supabase.auth.currentSession?.accessToken != null}');
```

Do not log access tokens.

## 11. Whether email confirmation is required

The linked database did not expose `auth.config`, but the failed user is unconfirmed and the auth wrapper in `lib/services/auth_service.dart` already treats `signUp` with `user != null` and `session == null` as pending email verification.

The production behavior is therefore email-confirmation mode for this signup path.

Implication:

- Supabase can create `auth.users`.
- `authResponse.user` can be non-null.
- `authResponse.session` can be null.
- RPC calls made immediately after signup run without `auth.uid()`.
- RPCs that rely on `auth.uid()` directly or indirectly will fail.

## 12. Whether RLS blocks profile/company insert

RLS is not the direct blocker here.

The registration RPCs are `SECURITY DEFINER`, which is intentional for the company/company_users/profile bootstrap chicken-and-egg problem. The live profile trigger also already created a profile for the failed user.

The direct failure is a security/audit helper exception inside a trigger fired by the `company_users` insert. The exception aborts the transaction and rolls back the company and membership writes.

## 13. Exact root cause

The exact root cause is a mismatch between signup timing and the database security model:

1. Supabase Auth signup succeeds but returns no session because the email is not confirmed.
2. `RegistrationService.registerAsOwner` immediately calls `create_company_with_owner` anyway.
3. The live RPC still trusts client `p_user_id` and is executable by anon/PUBLIC, so the RPC body starts even without an authenticated JWT.
4. The RPC inserts `company_users`.
5. The `audit_company_users_sensitive_changes` trigger fires.
6. The trigger calls `record_security_audit_event`.
7. `record_security_audit_event` evaluates `auth.uid()` and finds it null.
8. It raises `P0001: Unauthorized`.
9. The registration transaction rolls back, leaving an auth user and profile but no company/company_users/current_company_id.
10. Flutter maps the raw database message to `RegistrationError.unknown: Unauthorized`, leaving the user stuck.

There is a second security defect in the same path: `create_company_with_owner` and `join_company_as_manager` still accept and use `p_user_id` from Flutter as authority. The safest fix must remove that trust and use `auth.uid()` inside the RPCs.

## 14. Minimal safe fix

The minimal safe fix has three parts:

1. Flutter session gate:
   - After `auth.signUp`, log session/currentUser/currentSession presence safely.
   - If `authResponse.session == null`, do not call the registration RPC.
   - Return a pending-verification registration result and route the user to OTP/email verification.
   - Show copy that company setup will finish after verification/sign-in, not raw `Unauthorized`.

2. Secure RPCs:
   - Replace the registration RPC definitions so they derive `v_user_id := auth.uid()`.
   - Reject unauthenticated calls with `Unauthorized` and no side effects.
   - Stop using client `p_user_id` as authority.
   - Revoke EXECUTE from `PUBLIC` and `anon`.
   - Grant EXECUTE only to `authenticated` (and service/admin as needed by platform operations, not Flutter).
   - Keep `SECURITY DEFINER` and fixed `search_path`.
   - Upsert `profiles` so missing profile rows do not block registration.

3. Recovery for authenticated users with no company:
   - If the user returns after verification and the registration state still exists, call the same owner/manager completion path with the now-authenticated session.
   - If an authenticated user reaches a protected route with no company and no pending manager membership, route to the company setup flow instead of leaving the dashboard in a null-company state.

## 15. Files/migrations to modify

Expected files:

- `REGISTRATION_UNAUTHORIZED_RPC_ANALYSIS.md`
- `lib/services/registration_service.dart`
- `lib/models/registration_models.dart`
- `lib/providers/registration_provider.dart`
- `lib/screens/registration/user_account_screen.dart`
- `lib/screens/auth/otp_screen.dart` if needed to complete setup after verification in the current session
- `lib/core/router/app_router.dart` for authenticated-without-company recovery guard
- A new Supabase migration under `supabase/migrations/` for secure registration RPC replacement and grants
- `PROJECT_CONTEXT.md` for the project record

## 16. Files to leave untouched

Do not touch:

- Document extraction
- `process-document`
- `process-sales-import`
- OpenRouter/VLM prompts
- Products/product matching
- Sales/POS integrations
- Storage policies unrelated to registration
- Dashboard UI layout/design
- Unrelated RLS policies

## 17. Validation checklist

Database validation:

1. Inspect live definitions for `create_company_with_owner`, `join_company_as_manager`, `handle_new_user`.
2. Confirm unauthenticated RPC calls are denied and have no side effects.
3. Confirm authenticated owner RPC creates exactly one company row.
4. Confirm owner RPC creates one active `company_users` owner row for `auth.uid()`.
5. Confirm owner RPC sets `profiles.current_company_id`.
6. Confirm owner RPC upserts profile when missing.
7. Confirm attempts to pass a different `p_user_id` are impossible or ignored because the signature no longer accepts it.
8. Confirm manager RPC uses `auth.uid()` and creates an inactive manager membership for the invite code.
9. Confirm `PUBLIC` and `anon` do not have EXECUTE on registration RPCs.
10. Confirm audit trigger still records sensitive membership changes for authenticated registrations.

Flutter validation:

1. `auth.signUp` with `session != null` proceeds to owner RPC and dashboard.
2. `auth.signUp` with `session == null` does not call owner RPC and routes to OTP/email verification.
3. No raw `P0001 Unauthorized` is shown to the user.
4. After OTP verification, pending owner setup completes when in-memory registration state is still available.
5. Existing auth user with no company is routed to company setup instead of a broken dashboard.
6. Manager invite flow still creates a pending manager membership after session is active.
7. Existing login remains unaffected.
8. Focused Flutter analyzer passes for touched registration/auth/router files.
9. Live linked SQL validation passes after applying the migration.
