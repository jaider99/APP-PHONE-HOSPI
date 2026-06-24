# App Boot Splash Hang Analysis

## 1. Full startup sequence from `main()`

Current startup flow in `lib/main.dart`:

1. `main()` enters `runZonedGuarded`.
2. `WidgetsFlutterBinding.ensureInitialized()` runs inside the guarded zone.
3. Global error hooks are installed:
   - `FlutterError.onError`
   - `PlatformDispatcher.instance.onError`
4. Debug log prints `[BOOT] Starting app`.
5. Environment state is logged.
6. `EnvConfig.initializeFromEnvironment()` is awaited.
7. Debug log prints `[BOOT] Initializing Supabase`.
8. `SupabaseService.initialize()` is awaited.
9. Debug logs print:
   - `[BOOT] Supabase initialized`
   - `[BOOT] Supabase ready. Session exists: true/false`
10. In development only, `StorageService().verifyStorageConfig()` is awaited.
11. Debug log should print `[BOOT] Running app`.
12. `runApp(const ProviderScope(child: HospiDashApp()))` mounts the Flutter app.
13. `HospiDashApp` watches `appRouterProvider` and returns `MaterialApp.router`.
14. GoRouter handles auth/company redirects.

Observed logs stop after:

```text
[BOOT] Supabase ready. Session exists: true
[StorageService] Auth: session exists
supabase.auth: INFO: Refresh session
```

The expected `[BOOT] Running app` log is not present, so the Flutter UI is not mounted.

## 2. Every awaited Future before `runApp()`

Awaited before `runApp()`:

- `runZonedGuarded(() async { ... })`
- `EnvConfig.initializeFromEnvironment()`
- `SupabaseService.initialize()`
- `StorageService().verifyStorageConfig()` when `EnvConfig.isDevelopment` is true

Inside `StorageService.verifyStorageConfig()`:

- `_resolveAccessToken()` is awaited.
- `_resolveAccessToken()` may await `_supabase.auth.refreshSession()` if the current token expires in 120 seconds or less, or if `expiresAt` is null.
- `http.post(.../storage/v1/object/list/documents)` is awaited.

## 3. Whether `runApp()` is called before or after storage verification

`runApp()` is called after storage verification.

Current order:

```dart
if (EnvConfig.isDevelopment) {
  await StorageService().verifyStorageConfig();
}

debugPrint('[BOOT] Running app');
runApp(...);
```

This means any hang in storage verification leaves the native Flutter splash visible because no Flutter widget tree exists yet.

## 4. What `StorageService.verifyStorageConfig()` does

`verifyStorageConfig()` is a debug/development storage check.

It:

1. Returns immediately outside debug mode.
2. Logs whether the current Supabase auth session exists.
3. Calls `_resolveAccessToken()`.
4. `_resolveAccessToken()`:
   - reads `_supabase.auth.currentSession`
   - throws `StorageAuthRequiredException` when no session exists
   - checks token expiry
   - returns the current token if it has more than 120 seconds left
   - otherwise awaits `_supabase.auth.refreshSession()`
5. Performs an authenticated HTTP POST to:
   - `${EnvConfig.supabaseUrl}/storage/v1/object/list/documents`
6. Logs whether the `documents` bucket is accessible.
7. Logs that the storage client URL transform bypass is active.

## 5. Whether storage verification has timeout

No.

There is no timeout around:

- `_supabase.auth.refreshSession()` inside `_resolveAccessToken()`
- the storage `http.post` inside `verifyStorageConfig()`
- the whole `verifyStorageConfig()` call in `main()`

Therefore a slow/hung auth refresh or storage HTTP call can block `runApp()` indefinitely.

## 6. Whether Supabase auth refresh is awaited

Yes, when the current session is missing `expiresAt` or expires within 120 seconds.

The observed Supabase log:

```text
supabase.auth: INFO: Refresh session
```

matches `_resolveAccessToken()` awaiting `_supabase.auth.refreshSession()` during `verifyStorageConfig()`.

There is no timeout around that refresh in the storage path.

## 7. Whether GoRouter redirects can hang

Yes, but not for the observed native splash hang.

GoRouter redirect awaits these futures for authenticated protected routes:

- `isPendingApprovalProvider.future`
- `companyIdProvider.future`

Those providers perform Supabase queries without explicit timeouts. A network hang there could leave the Flutter app on a routed loading/blank state after `runApp()`.

However, the current observed log sequence stops before `[BOOT] Running app`, so GoRouter has not been mounted yet. It is a secondary hardening target, not the primary root cause of this splash hang.

## 8. Whether company/profile resolution can hang

Yes.

`companyIdProvider` awaits, in order:

1. `profiles.select('current_company_id').eq('id', user.id).maybeSingle()`
2. `company_users.select('company_id')...maybeSingle()` with `is_active = true`
3. another `company_users` query without the active filter
4. `profiles.update({'current_company_id': fallbackId})`
5. last-resort `companies.select('id').limit(1).maybeSingle()`
6. another profile update when the last-resort company is found

None of these calls has an explicit timeout. The provider catches errors and returns `null`, but it cannot catch a future that never completes.

`isPendingApprovalProvider` also performs two Supabase queries without explicit timeouts.

## 9. Whether any provider remains in infinite loading

Possible, after `runApp()`.

Likely candidates:

- `authNotifierProvider`: awaits biometric availability/enabled checks during `build()`. If platform local auth hangs, auth state can remain loading. This would affect router redirects after the Flutter app is mounted.
- `companyIdProvider`: awaits multiple Supabase queries without timeouts.
- `isPendingApprovalProvider`: awaits Supabase queries without timeouts.

For the observed logs, these providers are not yet the stopping point because `runApp()` has not been called.

## 10. Exact line/stage where boot stops

Boot stops after `main.dart` logs Supabase readiness and enters the development-only storage verification block:

```dart
if (EnvConfig.isDevelopment) {
  await StorageService().verifyStorageConfig();
}
```

The last observed app log is produced at the beginning of `StorageService.verifyStorageConfig()`:

```text
[StorageService] Auth: session exists
```

The next observed SDK log is:

```text
supabase.auth: INFO: Refresh session
```

That points to `_resolveAccessToken()` awaiting `_supabase.auth.refreshSession()` before `runApp()`.

The cheapest discriminating check is already present in code: if `[BOOT] Running app` does not appear, `runApp()` was not reached. Current logs confirm it does not appear.

## 11. Root cause

Primary root cause:

`main()` blocks first UI mount on a non-critical development storage verification call. That call performs remote auth/storage work without timeouts. With an existing near-expired or stale session, `verifyStorageConfig()` enters `_resolveAccessToken()`, awaits Supabase `refreshSession()`, and can hang before `runApp()`. Because the Flutter widget tree has not mounted, the user only sees the native Flutter splash/loading screen.

Secondary risk:

After `runApp()`, GoRouter redirects and company resolution also await network-backed providers without explicit timeouts. Those are not the observed native splash blocker, but they can still produce app-level indefinite loading if Supabase is slow or unavailable.

## 12. Minimal safe fix

Minimal safe fix:

1. Do not await `StorageService.verifyStorageConfig()` before `runApp()`.
2. Mount the Flutter app immediately after environment and Supabase initialization.
3. Defer storage verification after the first frame.
4. Add a timeout to the deferred storage verification.
5. Catch and log storage verification failures without blocking startup.
6. Add timeouts to storage auth refresh and storage HTTP calls used by storage operations.
7. Add route-guard timeouts around `isPendingApprovalProvider.future` and `companyIdProvider.future`, returning a controlled setup route or login route rather than hanging indefinitely.
8. Preserve auth guards, `company_id` resolution, RLS, upload behavior, extraction, sales/POS, products, and OpenRouter logic.

The first implementation should stay narrow: `main.dart`, `StorageService`, and possibly router/company provider timeout wrappers if validation shows post-`runApp()` loading can still hang.

## 13. Files to modify

Expected minimal files:

- `lib/main.dart`
  - Move storage verification after `runApp()`.
  - Add boot-stage logs around deferred verification.
  - Keep global error hooks.
- `lib/services/storage_service.dart`
  - Add timeout protection to auth refresh and storage HTTP calls.
  - Keep upload/storage behavior intact.
- `lib/core/router/app_router.dart`
  - Add bounded waits around redirect-time `isPendingApprovalProvider` and `companyIdProvider` reads if needed.
- `lib/providers/company_provider.dart`
  - Add bounded Supabase query helpers if router-level timeout is not sufficient.
- `PROJECT_CONTEXT.md`
  - Document the resolved issue after validation.

## 14. Files to leave untouched

Do not touch:

- `supabase/functions/process-document`
- `supabase/functions/process-sales-import`
- OpenRouter/VLM logic
- document extraction
- PDF rendering
- product matching
- sales/POS logic
- database migrations
- RLS policies
- storage bucket policies
- bottom navigation
- FAB/UI redesign files

## 15. Validation checklist

Focused code validation:

- Run analyzer on modified boot/storage/router/provider files.
- Confirm no new diagnostics in `APP_BOOT_SPLASH_HANG_ANALYSIS.md`.

Boot validation:

- Existing session: logs should show `[BOOT] Running app` and the app should reach dashboard/company setup/login instead of native splash.
- Existing near-expired/stale session: auth refresh failure should not block first UI mount.
- Fresh install/no session: app should reach login/register.
- Existing session/no company: app should route to company setup.
- Slow/no network: app should leave native splash and reach a controlled Flutter UI state.
- Storage verification failure: app should still render; warning is logged and upload paths surface specific storage errors later.
- Hot restart: no indefinite native splash.
- Document upload smoke: storage upload still works after deferred verification.
- Sales/import/POS/product flows remain untouched and unaffected.

## 16. Post-fix validation result

Implemented fix summary:

- `main.dart` now calls `runApp()` before development storage verification.
- Storage verification starts after the first frame and is timeout-bounded.
- Storage auth refresh and HTTP calls are timeout-bounded.
- Auth biometric probes, company queries, and GoRouter route-guard futures are timeout-bounded.
- Route-guard failure now reaches `/bootstrap-recovery` instead of indefinite loading.

Focused analyzer validation passes with no issues for:

```text
flutter analyze lib/main.dart lib/services/storage_service.dart lib/core/router/app_router.dart lib/providers/company_provider.dart lib/providers/auth_provider.dart
```

Runtime emulator validation using:

```text
flutter run --dart-define-from-file=env/dev.json -d emulator-5554
```

confirmed the app leaves the native splash path and mounts Flutter before the same storage/session problem completes. The relevant boot logs were:

```text
[BOOT] Supabase ready. Session exists: true
[BOOT] before runApp
[BOOT] after runApp
GoRouter: INFO: setting initial location /sign-in
[BOOT] before deferred verifyStorageConfig
[BOOT] Deferred storage verification failed
```

The deferred storage verification still timed out after 8 seconds in the emulator, which is the expected controlled failure mode: the timeout no longer prevents Flutter UI mount.
