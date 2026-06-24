# Storage Verification Timeout Analysis

## 1. Current deferred startup flow in `main.dart`

`main()` now mounts Flutter before storage verification:

1. `WidgetsFlutterBinding.ensureInitialized()` runs.
2. Global Flutter/platform error hooks are installed.
3. `EnvConfig.initializeFromEnvironment()` is awaited.
4. `SupabaseService.initialize()` is awaited.
5. `[BOOT] before runApp` is logged in debug mode.
6. `runApp(const ProviderScope(child: HospiDashApp()))` mounts the app.
7. `[BOOT] after runApp` is logged in debug mode.
8. `_startDeferredStartupChecks()` is called.

Before the fix, `_startDeferredStartupChecks()`:

1. Returns unless `EnvConfig.isDevelopment` is true.
2. Schedules work after the first frame with `WidgetsBinding.instance.addPostFrameCallback`.
3. Logs `[BOOT] before deferred verifyStorageConfig` in debug mode.
4. Started `StorageService().verifyStorageConfig().timeout(const Duration(seconds: 8))` with `unawaited`.
5. Logs `[BOOT] after deferred verifyStorageConfig` on success.
6. Logs `[BOOT] Deferred storage verification failed` as a warning with stack trace on any error.

This meant startup no longer depended on storage verification, but the deferred health check still produced a scary warning when it timed out.

After the fix, `_startDeferredStartupChecks()` still runs only in the development environment and still runs after the first frame, but it handles a typed `StorageHealthResult`. The storage health check returns quickly with `StorageHealthStatus.skipped` because startup no longer performs client-side bucket object listing.

## 2. Exact call to `StorageService.verifyStorageConfig()`

The pre-fix call was:

```dart
unawaited(
  StorageService()
      .verifyStorageConfig()
      .then((_) { ... })
      .catchError((Object error, StackTrace stackTrace) { ... }),
);
```

The outer timeout was in `main.dart`. It did not identify which internal verifier step was slow.

The current call is:

```dart
unawaited(
  StorageService()
      .verifyStorageConfig()
      .then((result) { ... })
      .catchError((Object error, StackTrace stackTrace) { ... }),
);
```

The current verifier returns a result instead of relying on a boot-level timeout.

## 3. Every operation inside `verifyStorageConfig()`

Before the fix, `StorageService.verifyStorageConfig()` did this:

1. Returns immediately unless `kDebugMode` is true.
2. Reads `_supabase.auth.currentSession` synchronously.
3. Logs whether an auth session exists.
4. Calls `_resolveAccessToken()`.
5. Builds `storageUrl = '${EnvConfig.supabaseUrl}/storage/v1'`.
6. Performs a direct HTTP POST to:

```text
/storage/v1/object/list/documents
```

with:

```json
{"prefix":"","limit":1}
```

7. Timed that HTTP request with `_storageVerifyTimeout`, then a temporary 3-second per-stage probe during investigation.
8. Logs bucket accessibility on HTTP 200.
9. Logs a warning on non-200 status.
10. Catches `StorageAuthRequiredException` and logs a debug skip.
11. Catches every other exception and logs `[StorageService] Bucket check error` as a warning.
12. Logs `[StorageService] storage_client URL transform bypass active`.

After the fix, `StorageService.verifyStorageConfig()` does this:

1. Returns `StorageHealthStatus.skipped` outside debug mode.
2. Logs `[StorageVerify] stage=start` in debug mode.
3. Reads `_supabase.auth.currentSession` synchronously.
4. Returns `StorageHealthStatus.unauthenticated` when no session exists.
5. Logs `[StorageVerify] stage=check_policy` and `[StorageVerify] stage=complete` without calling the network.
6. Returns `StorageHealthStatus.skipped` with message `Startup bucket listing skipped; uploads validate storage on demand.`

## 4. Which operation times out

The current logs prove the timeout is in the deferred `verifyStorageConfig()` path, after Flutter UI mount:

```text
[BOOT] before deferred verifyStorageConfig
[StorageService] Auth: session exists
TimeoutException after 0:00:08.000000: Future not completed
[BOOT] Deferred storage verification failed
[StorageService] Bucket check error
```

The pre-fix code had two async operations inside the verifier:

- `_resolveAccessToken()`, which may call Supabase `auth.refreshSession()`.
- `http.post('/storage/v1/object/list/documents')`, which has `_storageVerifyTimeout`.

Temporary Phase 2 instrumentation added stage logs and 3-second per-step timeouts. The emulator run proved the exact slow step:

```text
[StorageVerify] stage=resolve_token
[StorageVerify] stage=check_bucket
[BOOT] after deferred verifyStorageConfig status=timedOut stage=check_bucket
```

Token resolution completed quickly. The timeout was the client-side `POST /storage/v1/object/list/documents` bucket/object-list probe.

## 5. Whether it calls auth token refresh

Before the fix, yes, indirectly.

`verifyStorageConfig()` calls `_resolveAccessToken()`. `_resolveAccessToken()`:

1. Reads `_supabase.auth.currentSession`.
2. Throws `StorageAuthRequiredException` if no session exists.
3. Checks `session.expiresAt`.
4. Returns the current access token if it has more than 120 seconds remaining.
5. Otherwise awaits `_supabase.auth.refreshSession().timeout(_authRefreshTimeout)`.

For a stale or near-expired session, the debug storage health check could force a session refresh. That was not appropriate for a startup diagnostic.

After the fix, `verifyStorageConfig()` does not call `_resolveAccessToken()` and does not force `refreshSession()` at startup. Upload/sign/delete paths still use `_resolveAccessToken()` because those are real storage operations.

## 6. Whether it lists buckets

No.

The current code does not call `supabase.storage.listBuckets()`.

## 7. Whether it gets bucket metadata

No.

The current code does not call `supabase.storage.getBucket('documents')` or an equivalent bucket metadata endpoint.

## 8. Whether it creates a signed URL

No.

`verifyStorageConfig()` does not call `getSignedUrl()` or `/storage/v1/object/sign/...`.

## 9. Whether it uploads a test object

No.

`verifyStorageConfig()` does not upload a test object.

## 10. Whether it downloads a test object

No.

`verifyStorageConfig()` does not download an object.

## 11. Whether it calls a Supabase Storage admin endpoint

No direct admin bucket endpoint is used.

Before the fix, it called the Storage object listing endpoint from the Flutter client:

```text
POST /storage/v1/object/list/documents
```

This was not bucket administration, but it was still a remote storage policy probe. It depended on authenticated storage object listing permissions and network health.

After the fix, startup verification does not call any Supabase Storage endpoint.

## 12. Whether the mobile anon/authenticated client is allowed to perform that operation

It depends on Storage policies for `storage.objects`.

For a private multi-tenant bucket, a client-side object listing at `prefix: ''` is not a good startup probe:

- It may be denied by policy because root bucket listing is broader than tenant-scoped access.
- It may require `SELECT` on `storage.objects`, even though upload can still be allowed for a tenant path.
- It does not prove that a specific tenant path upload will work.
- It can force token refresh and network work unrelated to the user action.
- It is not required for normal app navigation.

Flutter should upload to the known tenant path and map real upload errors. Bucket existence and broad policy checks belong in deployment validation or a privileged CI/admin diagnostic, not every app launch.

## 13. Whether this check is required at startup

No.

It is a diagnostic convenience only. The app can render login, register, dashboard, company setup, review center, and other screens without proving storage bucket list access at startup.

Storage correctness should be validated when the user performs a storage operation, especially `uploadDocument()` and `uploadSalesImport()`.

## 14. Whether the check is dev-only or production-visible

There are two guards:

- `_startDeferredStartupChecks()` returns unless `EnvConfig.isDevelopment` is true.
- `verifyStorageConfig()` returns unless `kDebugMode` is true.

So the current check should only run in development/debug builds with development env config. It is still noisy during local/mobile testing and can look like an app error even though startup is no longer blocked.

## 15. Exact root cause

The root cause of the new timeout noise is not the native splash blocker. That was already fixed.

The confirmed root cause is that a non-critical debug startup diagnostic performed authenticated remote storage work:

1. It may force Supabase auth token refresh through `_resolveAccessToken()`.
2. It performs a client-side root object-list probe against a private multi-tenant storage bucket.
3. It is wrapped in an outer boot-level timeout and logs timeout/error conditions as warnings with stack traces.

This makes expected development conditions, such as stale sessions, emulator DNS/network slowness, denied object-list policy, or slow Storage API responses, appear as startup failures even though uploads should be validated on demand.

Phase 2 instrumentation confirmed the hanging sub-step was `check_bucket`, the client-side object-list POST to `/storage/v1/object/list/documents`. Token resolution completed before the timeout.

## 16. Minimal safe fix

The implemented production-safe fix is:

1. Keep app startup independent from storage verification.
2. Keep startup verification debug/development-only.
3. Convert `verifyStorageConfig()` from `Future<void>` with warning side effects into a typed soft health result.
4. Do not force session refresh for the health check.
5. Do not perform broad/root client-side bucket listing as a startup health check.
6. The remaining health check is lightweight and non-privileged:
   - read current session only,
   - skip when unauthenticated,
  - reports that upload paths will validate storage on demand,
  - returns `skipped` or `unauthenticated` instead of throwing for normal startup cases.
7. Change deferred startup logging so a timeout or skipped health check is debug/info only, not a scary warning with full stack trace.
8. Preserve upload-time validation and clear upload errors in `uploadDocument()` and `uploadSalesImport()`.

## 17. Files to modify

Expected minimal files:

- `lib/main.dart`
  - Keep deferred checks debug/dev-only.
  - Handle typed health results softly.
  - Remove warning-stack logging for expected health check timeout/skip.
- `lib/services/storage_service.dart`
  - Add `StorageHealthResult` and `StorageHealthStatus`.
  - Add per-stage diagnostic logs.
  - Avoid forced token refresh in verification.
  - Remove or avoid broad client-side object-list startup probe.
  - Keep real upload behavior and errors intact.
- `PROJECT_CONTEXT.md`
  - Document the resolved issue after validation.

## 18. Files to leave untouched

Do not touch:

- `supabase/functions/process-document`
- `supabase/functions/process-sales-import`
- OpenRouter/VLM logic
- document extraction prompts
- PDF rendering
- sales/POS logic
- product matching
- RLS policies
- storage policies
- database migrations
- UI redesign files
- bottom navigation
- FAB

## 19. Validation checklist

Focused validation:

- `flutter analyze lib/main.dart lib/services/storage_service.dart`
- VS Code diagnostics clean for `STORAGE_VERIFICATION_TIMEOUT_ANALYSIS.md`.

Startup validation:

- Existing session: app reaches Flutter UI; no `[BOOT] Deferred storage verification failed` warning.
- No session: login/register appears; storage health check skips without warning.
- Offline/slow network: app reaches controlled Flutter UI; no startup storage stack trace.
- Debug mode: health check logs clear stage/result at debug/info severity only.
- Release mode: no unnecessary startup bucket verification call.

Storage operation validation:

- Document upload still requires authenticated session.
- Document upload still uses `documents` bucket.
- Document upload still uses `company_id/document_id/file.ext` path.
- Permission denied maps to a clear auth/access message.
- Network failures map to a clear connection message.
- Missing/misconfigured bucket maps to a clear support message.
- Sales import remains unaffected.
- Extraction/VLM flows remain untouched.

## 20. Post-fix validation result

Focused analyzer validation passes with no issues for:

```text
flutter analyze lib/main.dart lib/services/storage_service.dart
```

Runtime emulator validation using:

```text
flutter run --dart-define-from-file=env/dev.json -d emulator-5554
```

confirmed startup no longer performs the client-side bucket object-list probe. Relevant logs:

```text
[BOOT] before runApp
[BOOT] after runApp
[BOOT] before deferred verifyStorageConfig
[StorageVerify] stage=start
[StorageService] Auth: session exists
[StorageVerify] stage=check_policy
[StorageVerify] stage=complete
[StorageService] Startup bucket listing skipped; uploads validate storage on demand.
[BOOT] after deferred verifyStorageConfig status=skipped stage=complete
```

There was no `check_bucket` stage, no `TimeoutException`, no `[BOOT] Deferred storage verification failed`, and no `[StorageService] Bucket check error`.
