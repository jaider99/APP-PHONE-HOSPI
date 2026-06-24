# POS Connection Architecture Analysis

## 1. Current Connect POS screen flow

The routed screen is `ConnectPosScreen` at `/sales/connect-pos`. It currently renders a single provider dropdown and one `Create connection` button. There is no country or market selection step.

Current options are:

- `custom` - Custom POS
- `square` - Square
- `lightspeed` - Lightspeed
- `toast` - Toast

This is US-biased and incomplete for a multi-country hospitality SaaS. Spain, Portugal, Colombia, Mexico, France, Italy, Germany, Netherlands, and other markets are not represented.

## 2. Current Flutter files involved

- `lib/features/sales/presentation/screens/connect_pos_screen.dart`
  - Owns the current Connect POS UI.
  - Uses a raw `DropdownButtonFormField` for provider choice.
  - Calls `SalesRepository.requestPosConnection(...)` on submit.
  - Shows raw `$error` in a snackbar, so `FunctionException(status: 404...)` can surface to the user.
- `lib/features/sales/data/repositories/sales_repository.dart`
  - `requestPosConnection({required String companyId, required String provider})` invokes Supabase Edge Function `connect-pos`.
  - Current payload is `{ 'companyId': companyId, 'provider': provider }`.
- `lib/features/sales/presentation/providers/sales_providers.dart`
  - Provides `salesRepositoryProvider` and `posConnectionsProvider`.
  - Realtime listens to `pos_sync_jobs`, but not `pos_connections` directly.
- `lib/features/sales/data/models/pos_connection.dart`
  - Current model expects `provider`, `status`, `external_account_id`, `last_sync_at`, `sync_status`.
- `lib/core/router/app_router.dart`
  - Defines `/sales/connect-pos` and routes it to `ConnectPosScreen`.
- `lib/features/sales/presentation/screens/sales_screen.dart`
  - Links to Connect POS and displays POS status via `posConnectionsProvider`.

## 3. Current POS provider list

The current provider list is hardcoded in the Flutter screen:

- Custom POS
- Square
- Lightspeed
- Toast

There is no provider metadata, no country support metadata, no connection type, no availability status, and no distinction between implemented and coming-soon integrations.

## 4. Current Supabase tables related to POS

The current Sales migration defines:

- `public.pos_connections`
  - Columns: `id`, `company_id`, `provider`, `status`, encrypted token fields, `external_account_id`, `last_sync_at`, `sync_status`, `metadata`, timestamps.
  - Tokens are intentionally not exposed to Flutter.
  - No direct `SELECT` policy exists.
- `public.pos_sync_jobs`
  - Columns: `id`, `company_id`, `pos_connection_id`, `status`, period fields, error/completion fields.
- `public.pos_connection_status`
  - View exposing token-free POS connection status for authenticated company members.
- There is currently no `public.pos_provider_catalog` table.

Current migration gaps for the requested product behavior:

- `pos_connections` has `provider`, but not `provider_key`, `provider_name`, `country_code`, `connection_type`, `credentials_status`, or `created_by`.
- `pos_connections.status` allows `connected`, `disconnected`, `error`, `pending`, but not `coming_soon` or `revoked`.
- No tenant-scoped request/waitlist table exists for coming-soon providers.
- No global provider catalog exists for country-first filtering.

## 5. Current Edge Functions expected by Flutter

Current Flutter Sales code invokes:

- `process-sales-import`
  - From `SalesRepository._invokeSalesImport(...)`.
  - Body: `{ 'salesImportId': salesImportId }`.
- `connect-pos`
  - From `SalesRepository.requestPosConnection(...)`.
  - Body: `{ 'companyId': companyId, 'provider': provider }`.

Search found no Flutter call to:

- `create-pos-connection`
- `start-pos-oauth`
- `sync-pos-sales`
- `disconnect-pos`

`sync-pos-sales` and `disconnect-pos` exist locally as Edge Function folders, but the current Connect POS screen does not call them.

## 6. Actual Edge Functions available/deployed

Local `supabase/functions/` folders currently include:

- `connect-pos`
- `disconnect-pos`
- `sync-pos-sales`
- `process-sales-import`
- `process-document`
- `recognize-products`
- `classify-expense`
- `classify-document-type`

Deployment status could not be confirmed from this environment. Running `supabase functions list` failed because the `supabase` CLI command is not available in the terminal.

Conclusion: `connect-pos` exists locally, but the user-facing 404 means the active Supabase project most likely does not have `connect-pos` deployed, or Flutter is pointed at a project/environment where that function is absent. This is not a Flutter route issue.

## 7. Exact source of the 404

The source call is:

- File: `lib/features/sales/data/repositories/sales_repository.dart`
- Method: `SalesRepository.requestPosConnection(...)`
- Edge Function name: `connect-pos`
- Current payload: `{ 'companyId': companyId, 'provider': provider }`
- Expected response today: `{ ok: true, connection: ... }`
- Current error handling:
  - The repository does not catch `FunctionException`.
  - `ConnectPosScreen._submit()` catches `Object error` and shows `SnackBar(content: Text('$error'))`.
  - That is why `FunctionException(status: 404, details: { code: NOT_FOUND, message: Requested function was not found })` can be shown raw.

The missing function is `connect-pos` in the active deployed Supabase project. It is not `create-pos-connection`, `start-pos-oauth`, or `sync-pos-sales` based on current Flutter code.

## 8. Current route/navigation flow

- `SalesScreen` routes to `AppRoutes.salesConnectPos` (`/sales/connect-pos`).
- `AppRoutes.salesConnectPos` is defined in `app_router.dart`.
- `/sales/connect-pos` is a nested route under `/sales` and renders `ConnectPosScreen`.
- The screen returns with `context.pop()` after a successful request.
- `SalesScreen` also provides `/sales/import` as a fallback for importing sales reports.

## 9. Current tenant/company context usage

Flutter gets the active tenant via `companyIdProvider`, which resolves:

1. `profiles.current_company_id`
2. `company_users.company_id`
3. `companies.id` as a last resort

Current `connect-pos` Edge Function accepts `companyId` from Flutter and then checks membership via `company_users`. This is safer than trusting it blindly, but the requested architecture should avoid relying on client-supplied `company_id` at all. The function should derive the active company server-side from `profiles.current_company_id` and validate the user belongs to it.

## 10. Recommended country-first POS architecture

Recommended MVP architecture:

1. Keep a static Flutter registry for immediate UI filtering and offline clarity.
2. Add `pos_provider_catalog` in Supabase as the server source of truth and seed it with the same MVP catalog.
3. `connect-pos` validates provider/country against `pos_provider_catalog` server-side.
4. Only create tenant-scoped `pos_connections` records when appropriate:
   - `custom` creates `pending_configuration` / pending custom connection.
   - `available` integrations can create pending connection or return `redirect_required` if OAuth exists.
   - `coming_soon` creates a request/waitlist record or returns structured `coming_soon` without pretending the connection succeeded.
5. Flutter cards show availability and do not call backend for providers that have no supported action unless the action is explicitly `Request access`.

Provider definition shape:

- `key`
- `displayName`
- `countries`
- `connectionType`: `oauth`, `api_key`, `file_import`, `manual`, `coming_soon`
- `status`: `available`, `coming_soon`, `custom`
- `description`
- `requiredCredentials`
- `edgeFunctionSupported`

## 11. MVP scope

In scope now:

- Country selector in Connect POS.
- Country-filtered provider cards.
- Provider availability badges and user-friendly CTAs.
- Static Flutter registry as UI source of truth.
- Supabase `pos_provider_catalog` as backend validation source.
- `connect-pos` function contract changed to `{ country_code, provider }`.
- Server derives `company_id`; Flutter does not send it.
- Custom POS creates a tenant-scoped pending connection.
- Coming-soon providers return structured response and optionally record metadata/request state.
- Friendly Flutter handling for missing function 404.
- Sales import fallback remains visible.

Out of scope now:

- Real OAuth to Square, Lightspeed, Toast, Revo, etc.
- POS token storage/exchange flows.
- Syncing live POS sales data.
- Modifying document extraction or OpenRouter VLM code.

## 12. Files to modify

- `supabase/migrations/20260613_sales_module_foundation.sql`
  - Add `pos_provider_catalog`.
  - Add missing POS connection columns and statuses.
  - Update `pos_connection_status` view.
  - Add RLS/read policy for catalog.
- `supabase/functions/connect-pos/index.ts`
  - Change request body to `country_code` and `provider`.
  - Derive `company_id` server-side.
  - Validate provider/country from catalog.
  - Return structured statuses.
- `lib/features/sales/data/models/pos_provider_definition.dart`
  - Add static provider/country registry model for UI.
- `lib/features/sales/data/models/pos_connection.dart`
  - Add country, provider display, connection type, credentials status as nullable/backward-compatible fields.
- `lib/features/sales/data/repositories/sales_repository.dart`
  - Update `requestPosConnection` contract.
  - Add structured response model/handling.
  - Catch function 404 at repository or UI boundary.
- `lib/features/sales/presentation/screens/connect_pos_screen.dart`
  - Replace raw dropdown with country-first flow and provider cards.

## 13. Files to leave untouched

- `supabase/functions/process-document/index.ts`
- `supabase/functions/process-sales-import/index.ts`
- Document extraction code
- OpenRouter VLM extraction code
- Products
- Providers/suppliers
- Dashboard
- Auth UI
- Storage service
- Bottom navigation
- FAB behavior

## 14. Deployment checklist

- `connect-pos` exists locally: yes.
- `connect-pos` deployed: not confirmed; Supabase CLI unavailable in this terminal.
- Flutter calls exact deployed name: should remain `connect-pos`.
- Flutter request body should be updated to `{ country_code, provider }`.
- Function must require auth.
- Function must return structured errors/responses.
- After Supabase CLI is available, run:
  - `supabase functions deploy connect-pos`
  - `supabase functions list`
  - authenticated function test against the linked project.

## 15. Validation checklist

- Open Connect POS: country selector appears.
- Select Spain: Spain-relevant providers appear.
- Select United States: US-relevant providers appear.
- Select coming-soon provider: no raw 404; request/access message shown.
- Select Custom POS: tenant-scoped pending configuration record created.
- Function missing scenario: user sees `POS connection service is not deployed yet. Please try again later.`
- `connect-pos` validates provider and country server-side.
- `connect-pos` derives `company_id` server-side and validates membership.
- Company A cannot see Company B POS connections.
- Sales page still loads.
- Sales import route still works.
- Document extraction remains untouched.