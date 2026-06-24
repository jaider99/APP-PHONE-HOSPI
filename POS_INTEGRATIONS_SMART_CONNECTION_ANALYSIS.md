# POS Integrations Smart Connection Analysis

Date: 2026-06-13

This file is the required Phase 1 analysis artifact before coding the POS redesign. The user also named `POS_SMART_INTEGRATION_STRATEGY_ANALYSIS.md` in the final deliverables. This document uses the exact Phase 1 filename and serves as that strategy analysis.

## Executive finding

HospiDash currently has a useful sales import pipeline, but the POS connection surface is mostly a visual registry. Every named provider in the live catalog is `coming_soon`; the only non-coming-soon entry is `custom`. The `connect-pos` Edge Function creates either a pending custom connection or a request row. It does not start OAuth, validate API credentials, store encrypted provider secrets, or run a provider adapter. The `sync-pos-sales` Edge Function only creates a pending sync job and currently accepts `companyId` from Flutter.

The MVP should not claim any live native POS connection until an adapter exists. The app should become a smart hub that classifies each provider into a truthful action:

- Native candidate: official API exists, but `has_backend_adapter=false` until HospiDash implements it.
- Assisted setup: official access appears gated, partner-managed, or credential-based; collect a safe request and route users to import meanwhile.
- Import reports: immediate value through the existing VLM/report import pipeline.
- Request integration: unsupported or unverifiable providers; save demand signal and offer import fallback.

## Official documentation evidence summary

This research checks official or provider-controlled documentation before making integration claims. It does not mean HospiDash has working adapters today.

| Provider | Official evidence checked | API/auth evidence | Sales data evidence | MVP classification |
| --- | --- | --- | --- | --- |
| Square | https://developer.squareup.com/docs/oauth-api/overview and https://developer.squareup.com/reference/square/orders-api | OAuth 2.0 code flow and PKCE, tokens server-managed | Orders API can search past sales and itemization | `native_oauth` candidate, `setup_required`, no live adapter yet |
| Lightspeed | https://developers.lightspeedhq.com/retail/authentication/authentication-overview/ and https://developers.lightspeedhq.com/retail/endpoints/Sale/ | OAuth 2.0 authorization code, access and refresh tokens | `Sale` endpoint supports completed sales and payments | `native_oauth` candidate, `setup_required`, no live adapter yet |
| Lightspeed Restaurant K-Series | https://api-docs.lsk.lightspeed.app/ | Official REST API portal exists | Restaurant API exists but needs portal-specific implementation | `assisted_credentials` until app credentials and API contract are confirmed |
| Toast | https://doc.toasttab.com/doc/devguide/apiOverview.html and https://doc.toasttab.com/openapi/ | Toast APIs have integration access types and API reference; access is permission-limited | Orders API is listed for menu orders/check/payment info | US-only in current registry; hide outside US, `assisted_credentials`/`request_only` until approved adapter exists |
| Clover | https://docs.clover.com/dev/reference/orders | OAuth2 bearer API reference, merchant orders endpoints | Orders endpoint lists merchant orders with created/status filters | `native_oauth` candidate, `setup_required`, no live adapter yet |
| SumUp | https://developer.sumup.com/api and https://developer.sumup.com/api/transactions | API keys, HTTPS, bearer authentication | Transaction history endpoint with `transactions.history` scope | `native_api_key` candidate only after encrypted credential storage; import-first for MVP |
| Zettle | https://developer.zettle.com/ and https://developer.zettle.com/docs/api/purchase/overview | OAuth 2.0, PKCE, code grant, assertion grant | Purchase API provides read-only purchases; Finance API fetches transactions | `native_oauth` candidate, `setup_required`, no live adapter yet |
| Poster | https://dev.joinposter.com/en/docs/v3/start/index and https://dev.joinposter.com/en/docs/v3/web/transactions/getTransactions | Developer app or personal integration token | Order list and transaction product endpoints expose paid sums and products | `native_api_key` candidate after encrypted credential storage; import-first for MVP |
| Alegra POS | https://developer.alegra.com/reference/autenticaci%C3%B3n and https://developer.alegra.com/reference/facturas-de-venta | Basic auth with email and token | Sales invoices, payments, reports, webhooks | `assisted_credentials`; not one-click because credentials and accounting setup are required |
| Siigo | https://siigoapi.docs.apiary.io/ | OAuth/JWT token from username and access_key, Partner-Id required | Invoices, vouchers, reports, webhooks | `assisted_credentials`; no live adapter yet |
| Glop | https://www.glop.es/api/ | Official page links API docs and says developer registration is required | Integration ecosystem exists, public details are gated | `assisted_credentials` or `import_reports`, no live adapter yet |
| Agora | https://www.agorapos.com/integraciones/ | Official integrations/alliances contact flow, no public self-serve API verified | Reports and partner integrations mentioned | `assisted_credentials` or `import_reports`, no live adapter yet |
| Revo | Official developer URLs were checked but no meaningful public API content was extractable | Not verified in this pass | Not verified in this pass | `request_only` plus import fallback until official docs/access are confirmed |
| CoverManager | https://developers.covermanager.com/ and https://www.covermanager.com/api/ | Official developer/API entry points appear present or gated | Restaurant operations focus, not confirmed as POS sales import source | `assisted_credentials` or `request_only`; import fallback |
| Last.app | https://developers.last.app/ | Official developer portal is login-gated | Not publicly verified without portal access | `assisted_credentials` or `request_only`; import fallback |
| Custom POS | Internal HospiDash path | No external docs needed | Existing VLM/report import pipeline can ingest reports | `custom` and `import_reports`, immediate MVP path |

## 1. Current Connect POS screen flow

Current file: `lib/features/sales/presentation/screens/connect_pos_screen.dart`.

Flow:

1. `ConnectPosScreen` loads a static local market list from `posMarketDefinitions`.
2. `_market` defaults to Spain, because Spain is the first country in the local registry.
3. The UI shows `_IntroCard`, `_CountryGrid`, an "Available providers" heading, then a flat provider card list.
4. Provider cards come from `providersForCountry(_market.code)`.
5. Pressing a provider calls `_handleProvider(provider)`.
6. `_handleProvider` invokes `salesRepositoryProvider.requestPosConnection(countryCode: _market.code, providerKey: provider.key)`.
7. If the function returns `pending_configuration`, the screen pops.
8. Otherwise the UI shows the returned message in a snackbar.
9. Any thrown error is shown using `error.toString()`, so raw or semi-raw Edge Function errors can leak into the UI.
10. A global "Import sales report instead" button navigates to the sales import screen.

User-facing issue:

- The screen looks like a provider integration catalog, but most provider actions only create requests. The useful import path exists, but it is secondary rather than the provider-specific fallback.

## 2. Current provider registry

Current file: `lib/features/sales/data/models/pos_provider_definition.dart`.

Current enums:

- `PosConnectionType`: `oauth`, `apiKey`, `fileImport`, `manual`, `comingSoon`.
- `PosProviderStatus`: `available`, `comingSoon`, `custom`.

Current fields in `PosProviderDefinition`:

- `key`
- `displayName`
- `description`
- `countries`
- `connectionType`
- `status`
- `edgeFunctionSupported`

Problem:

- `edgeFunctionSupported` is set to `true` for all providers. In practice this only means the app can call `connect-pos`, not that a provider adapter exists.
- There is no `connection_mode`, `connection_status`, `has_backend_adapter`, `documentation_url`, or `notes` field.
- The model cannot distinguish "official API exists" from "HospiDash backend adapter is live".

## 3. Current country selector

Current country definitions:

- ES Spain
- US United States
- GB United Kingdom
- FR France
- IT Italy
- DE Germany
- CO Colombia
- MX Mexico
- PT Portugal
- NL Netherlands
- OTHER Other market

Current behavior:

- Spain is selected by default.
- The country selector filters static local provider definitions.
- It does not consult live Supabase provider capabilities.
- It does not hide US-only providers globally; it only filters by selected country.

Required redesign behavior:

- Use country-first filtering, but do not make the list look empty or only "coming soon".
- If a country has no live native providers, show import-based and assisted options first.
- Do not show US-only providers outside the US selection.

## 4. Current Supabase tables: `pos_provider_catalog`

Live columns currently observed:

- `id`
- `provider_key`
- `display_name`
- `countries`
- `connection_type`
- `status`
- `description`
- `created_at`
- `updated_at`

Live rows currently observed:

- All named providers are `status='coming_soon'`.
- `custom` is `status='custom'`.
- There is no row marked `available`.

Missing for the requested architecture:

- `country_codes`
- `connection_mode`
- `connection_status`
- `supports_oauth`
- `supports_api_key`
- `supports_file_import`
- `supports_email_invite`
- `has_backend_adapter`
- `edge_function_name`
- `documentation_url`
- `notes`

Recommended change:

- Extend this table rather than replacing it.
- Keep old `connection_type` and `status` temporarily for compatibility, but drive new UI and Edge Function decisions from explicit capability fields.

## 5. `pos_connections`

Live columns currently observed include:

- `id`
- `company_id`
- `provider`
- `provider_key`
- `provider_name`
- `country_code`
- `status`
- `connection_type`
- `credentials_status`
- `external_account_id`
- `access_token_encrypted`
- `refresh_token_encrypted`
- `token_expires_at`
- `metadata`
- `last_sync_at`
- `sync_status`
- `created_by`
- timestamps

Current constraints:

- `connection_type` is limited to `oauth`, `api_key`, `file_import`, `manual`, `coming_soon`.
- `status` is limited to `pending`, `connected`, `error`, `disconnected`, `coming_soon`.

Problems:

- There is no explicit `connection_mode`.
- There is no `deleted_at`, although soft deletion may become useful for tenant-safe disconnect history.
- Token columns exist, but there is no implemented safe credential capture or provider validation flow in the current app.

Recommended change:

- Add `connection_mode` with values such as `native_oauth`, `native_api_key`, `assisted_credentials`, `import_reports`, `request_only`, `custom`.
- Add `deleted_at` if the app needs soft-delete history.
- For import-based connections, store no provider secrets and set `credentials_status='not_required'` if constraints are expanded, or use a compatible value plus metadata if not.

## 6. `pos_connection_requests`

Live columns currently observed include:

- `id`
- `company_id`
- `provider_key`
- `provider_name`
- `country_code`
- `status`
- `requested_by`
- `metadata`
- timestamps

Current behavior:

- `connect-pos` creates or reuses a request when a provider is `coming_soon`.

Problems:

- The request is not clearly tied to the connection mode chosen by the user.
- There is no dedicated `notes` column, although `metadata` can hold it.
- The UI treats the request as the main action instead of pairing it with immediate import fallback.

Recommended change:

- Store `connection_mode`, `requested_capability`, and optional `notes` in either columns or `metadata`.
- Use this table for demand signals, not for fake pending integrations.

## 7. `pos_sync_jobs`

Live columns currently observed include:

- `id`
- `company_id`
- `pos_connection_id`
- `status`
- `period_start`
- `period_end`
- `records_processed`
- `error_message`
- timestamps

Current behavior:

- `sync-pos-sales` inserts a pending job.
- No provider adapter runs.
- No sales rows are created by this function today.

Problem:

- A sync job currently represents intent, not actual sync capability.
- The function currently accepts `companyId` from Flutter and then checks membership. The hardened design should derive active company server-side.

Recommended change:

- Only create sync jobs for connections where `has_backend_adapter=true` and the connection is native/connected.
- For import-based connections, return a user-safe response directing the user to report import.
- Derive company from JWT membership server-side.

## 8. `sales_imports`

Live columns currently observed include:

- `id`
- `company_id`
- `source_type`
- `source_name`
- `file_path`
- `file_name`
- `file_mime_type`
- `file_size_bytes`
- `status`
- extraction fields
- `metadata`
- timestamps

Current behavior:

- `createSalesReportImport` inserts `source_type='vlm_import'`.
- `source_name` is derived from the MIME type, not from selected POS provider.

Missing:

- No `provider_key` column.
- No provider-aware import prefill.

Recommended change:

- Add nullable `provider_key` to `sales_imports` or store provider details in `metadata` for MVP.
- When launched from Connect POS, prefill source context such as `source_type='pos_report_import'`, `source_name='Glop sales report'`, and metadata `{ provider_key, country_code, connection_mode }`.

## 9. `sales`

Live columns currently observed include:

- `id`
- `company_id`
- `sale_date`
- revenue fields
- `transaction_count`
- `source_type`
- `source_id`
- `sales_import_id`
- `metadata`
- timestamps

Current behavior:

- Sales dashboards read `sales` rows populated by completed imports.
- The prior date parsing fix made imported sales feed dashboards correctly.

Recommended change:

- Do not change the core sales aggregation path for this POS hub MVP.
- If provider context is needed, propagate it through `sales.metadata` from `sales_imports.metadata` only after verifying `process-sales-import` behavior.

## 10. Current Edge Functions: `connect-pos`

Current file: `supabase/functions/connect-pos/index.ts`.

Current request body:

- `country_code`
- `provider`

Current behavior:

- Authenticates the user.
- Resolves active company server-side.
- Fetches provider from `pos_provider_catalog` using old fields.
- If provider status is `custom`, creates a `pos_connections` row with `status='pending'` and `credentials_status='pending'`.
- If provider status is `coming_soon`, creates/reuses a `pos_connection_requests` row.
- Otherwise returns `501 not_implemented`.

Problems:

- No OAuth start flow.
- No API credential validation.
- No encrypted credential write path.
- No import-based connected path.
- No structured action result for the Flutter UI.

Recommended change:

- Accept `provider_key`, `country_code`, and optional `connection_mode`.
- Fetch new catalog capabilities.
- Return structured safe responses such as `connected_import_mode`, `request_saved`, `setup_required`, `native_not_ready`, `unsupported_country`.
- Never return raw provider errors to Flutter.
- Never trust `company_id` from Flutter.

## 11. `sync-pos-sales`

Current file: `supabase/functions/sync-pos-sales/index.ts`.

Current request body:

- `companyId`
- `connectionId`

Current behavior:

- Uses a user client to check membership.
- Inserts a pending `pos_sync_jobs` row.
- Does not run provider sync logic.

Problems:

- It accepts `companyId` from Flutter.
- It can create a sync job even when no adapter exists.

Recommended change:

- Derive active company server-side from JWT and membership.
- Verify the connection belongs to that company.
- Verify the provider catalog row has `has_backend_adapter=true`.
- Return a user-safe message for import-based or request-only providers.

## 12. `disconnect-pos`

Current file: `supabase/functions/disconnect-pos/index.ts`.

Current state from prior remediation:

- Authenticates the user.
- Derives company server-side.
- Requires owner/admin.
- Clears token columns.
- Returns controlled errors.

Recommended change for this task:

- Leave core security behavior intact.
- Only update if new `connection_mode` or `deleted_at` fields require compatibility.

## 13. `process-sales-import`

Current file: `supabase/functions/process-sales-import/index.ts`.

Current state from prior remediation:

- Deployed and working after the day-first date parsing fix.
- Converts completed sales imports into `sales` and `sales_items` rows.

Recommended change for this task:

- Do not alter extraction logic unless provider metadata must be propagated.
- Keep document extraction separate and untouched.
- Revalidate after any optional import metadata addition.

## 14. Which providers are currently marked available / coming soon / custom

Current live catalog classification:

| Status | Providers |
| --- | --- |
| `available` | None |
| `coming_soon` | Agora, Alegra POS, Clover, CoverManager, Glop, Last.app, Lightspeed, Poster, Revo, Siigo, Square, SumUp, Toast, Zettle |
| `custom` | Custom POS |

Current local registry mirrors the same practical state:

- `custom` is the only custom provider.
- Every named real provider is `comingSoon`.

## 15. Why users cannot actually connect

Users cannot actually connect because the current stack lacks the controlling implementation pieces:

- No provider has `status='available'` in the live catalog.
- `connect-pos` only handles `custom` and `coming_soon`.
- OAuth providers do not have authorization URL generation, callback handling, token exchange, refresh handling, or adapter code.
- API-key providers do not have secure credential capture, encryption, validation, or adapter code.
- Assisted providers do not have a guided setup workflow.
- `sync-pos-sales` does not call any provider API.
- The UI calls `connect-pos` for all providers because `edgeFunctionSupported=true`, but that flag does not mean an adapter exists.

## 16. Which providers have backend support implemented

Actual backend support implemented today:

| Provider class | Implemented behavior | Is it a real sales sync connection? |
| --- | --- | --- |
| Custom POS | Creates a pending `pos_connections` row | No |
| Coming-soon providers | Creates/reuses a `pos_connection_requests` row | No |
| Sales report import | Uploads and processes reports into `sales` | Yes, but it is import-based, not provider API sync |

No named provider currently has a working backend adapter for native sales sync.

## 17. Which providers are only visual placeholders

These providers are visual/request placeholders in the current Connect POS flow because they have no HospiDash adapter:

- Agora
- Alegra POS
- Clover
- CoverManager
- Glop
- Last.app
- Lightspeed
- Poster
- Revo
- Siigo
- Square
- SumUp
- Toast
- Zettle

Custom POS is also not yet useful because it creates a pending configuration record instead of immediately connecting the user to the import workflow.

## 18. Which providers should be native, assisted, import-based, or request-only

Recommended MVP classification, based on official documentation and current backend reality:

| Provider | Current countries | Recommended `connection_mode` | Recommended `connection_status` | `has_backend_adapter` now | CTA |
| --- | --- | --- | --- | --- | --- |
| Custom POS | All | `custom` + `import_reports` | `import_only` | false | Set up report import |
| Square | ES, US, GB, FR | `native_oauth` | `setup_required` | false | Import reports while native sync is prepared |
| Lightspeed | ES, US, GB, FR, IT, DE, PT, NL | `native_oauth` or `assisted_credentials` for K-Series | `setup_required` | false | Import reports / request guided setup |
| Toast | US only | `assisted_credentials` or `request_only` | `unavailable` outside US | false | Hide outside US; request/import in US |
| Clover | US, GB | `native_oauth` | `setup_required` | false | Import reports / request native sync |
| SumUp | GB, FR, IT, DE, PT, NL | `native_api_key` | `setup_required` | false | Import reports until encrypted credentials exist |
| Zettle | GB, FR, IT, DE, NL | `native_oauth` | `setup_required` | false | Import reports / request native sync |
| Glop | ES | `assisted_credentials` | `setup_required` | false | Import reports / request assisted setup |
| Agora | ES | `assisted_credentials` | `setup_required` | false | Import reports / request assisted setup |
| Revo | ES | `request_only` until official docs verified | `requested` | false | Import reports / request integration |
| CoverManager | ES | `assisted_credentials` or `request_only` | `setup_required` | false | Import reports / request integration |
| Last.app | ES | `assisted_credentials` or `request_only` | `setup_required` | false | Import reports / request integration |
| Poster | CO, MX, PT | `native_api_key` | `setup_required` | false | Import reports until encrypted credentials exist |
| Alegra POS | CO, MX | `assisted_credentials` | `setup_required` | false | Import reports / request assisted setup |
| Siigo | CO | `assisted_credentials` | `setup_required` | false | Import reports / request assisted setup |

Important rule:

- A provider may be a native candidate only if official documentation verifies API support.
- It may be marked live only when `has_backend_adapter=true` and the Edge Function implementation exists.

## 19. Best MVP implementation

The best MVP is a smart, honest connection hub that makes the existing sales import pipeline the default value path when native sync is not actually implemented.

Backend MVP:

1. Extend `pos_provider_catalog` with capability fields:
   - `connection_mode`
   - `connection_status`
   - `supports_oauth`
   - `supports_api_key`
   - `supports_file_import`
   - `supports_email_invite`
   - `has_backend_adapter`
   - `edge_function_name`
   - `documentation_url`
   - `notes`
2. Extend `pos_connections` with `connection_mode` and optionally `deleted_at`.
3. Optionally add `provider_key` to `sales_imports`, or store provider details in `metadata` for a smaller migration.
4. Update `connect-pos` to return mode-aware safe responses.
5. For `custom` and `import_reports`, create a real import-based connection with no credentials or tokens.
6. For `request_only`, save `pos_connection_requests` and return an import fallback action.
7. For native candidates without adapters, do not create fake connected records. Return `setup_required` or `native_not_ready` with import fallback.
8. Harden `sync-pos-sales` so it derives the company server-side and refuses providers without live adapters.

Flutter MVP:

1. Replace status-only provider cards with smart groups:
   - Connect automatically
   - Guided setup
   - Import reports
   - Request integration
2. For countries with no live native adapter, make import/report actions visually primary.
3. Make Custom POS an import-based connection path, not a pending credentials path.
4. Pass provider context to the import screen.
5. Show safe messages from structured function responses, not `error.toString()`.
6. Hide US-only providers unless the selected country is US.

Credential policy for MVP:

- Do not accept raw POS credentials in Flutter.
- Do not store credentials in plaintext.
- Do not build `validate-pos-credentials` for real credentials until encryption and provider-specific validation are implemented.
- For API-key providers, use request/import-only or assisted setup until server-side encryption is ready.

## 20. Files to modify

Likely implementation files:

- `supabase/migrations/<new>_pos_smart_connection_modes.sql`
- `supabase/functions/connect-pos/index.ts`
- `supabase/functions/sync-pos-sales/index.ts`
- Optional: `supabase/functions/save-pos-connection-request/index.ts`
- Optional later: `supabase/functions/validate-pos-credentials/index.ts`
- `lib/features/sales/data/models/pos_provider_definition.dart`
- `lib/features/sales/data/models/pos_connection_result.dart`
- `lib/features/sales/data/repositories/sales_repository.dart`
- `lib/features/sales/presentation/screens/connect_pos_screen.dart`
- `lib/features/sales/presentation/screens/import_sales_screen.dart`
- `lib/core/router/app_router.dart` if import prefill needs route parameters
- `lib/features/sales/presentation/providers/sales_providers.dart` if provider catalog is fetched live
- `PROJECT_CONTEXT.md` after implementation

## 21. Files to leave untouched

Leave these untouched unless a direct, verified dependency appears:

- Document extraction Edge Functions and prompts
- `process-document`
- Product matching
- Documents screen
- Products screen
- Dashboard UI unrelated to sales refresh
- Auth flows
- Storage policies unless a confirmed sales import issue requires it
- Unrelated RLS policies
- Existing sales import parsing logic, except optional provider metadata propagation

## 22. Validation checklist

Analysis validation:

- Confirm this file exists before implementation.
- Confirm all 22 requested sections are present.
- Confirm every native/assisted claim references official or provider-controlled documentation.
- Confirm no provider is called live unless a backend adapter exists.

Schema validation:

- Apply migration to linked Supabase project without weakening RLS.
- Confirm `pos_provider_catalog` has new capability fields.
- Confirm `pos_connections` remains tenant-scoped.
- Confirm request rows remain tenant-scoped.
- Confirm sales import rows remain tenant-scoped.

Edge Function validation:

- `connect-pos` rejects unauthenticated calls.
- `connect-pos` derives company server-side.
- `connect-pos` rejects unsupported country/provider combinations.
- `connect-pos` returns import-based connection for Custom POS without credentials.
- `connect-pos` saves request-only demand signals without creating fake connected native rows.
- `sync-pos-sales` rejects client-supplied tenant scope and derives company server-side.
- `sync-pos-sales` refuses native sync when `has_backend_adapter=false`.
- No raw provider or Supabase error is exposed to Flutter.

Flutter validation:

- Spain does not show only "Coming soon" actions.
- US-only Toast is hidden outside the US selection.
- Custom POS leads to import-based setup.
- Provider import CTA opens import screen with provider context.
- Request integration saves a request and still offers import fallback.
- Existing Sales import still processes reports and updates Sales/dashboard.
- Existing document extraction still works and was not changed.
