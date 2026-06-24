# App Performance Freeze Analysis

## 1. Exact freeze scenarios tested

Tested directly in this session:

1. Android emulator debug boot with existing session and development env.
   - Command: `flutter run --dart-define-from-file=env/dev.json -d emulator-5554`
   - Result: app reaches Flutter UI and GoRouter `/sign-in`; no storage startup timeout after the previous storage-health fix.
2. Android emulator Review Center static/code path inspection.
   - Inspected `ReviewCenterScreen`, providers, repository, realtime stream, and sync RPC usage.
   - Found automatic sync on screen entry, unbounded item/count fetches, and undebounced realtime-triggered provider refetches.
3. Live Supabase `review_items` volume and duplicate checks.
   - Active company: `e70aabbf-679d-4270-aaf6-bb8a8c25babe`.
   - Current live open review items: `28`.
   - Current duplicate-key rows for `(company_id, review_type, source_table, source_id, status)`: `0`.
   - Current total/distinct source count: `28 / 28`.
4. Live table-size estimate check.
   - `document_items`: about `128` rows.
   - `documents`: about `120` rows.
   - `product_prices`: about `68` rows.
   - `products`: about `64` rows.
   - `review_items`: about `28` rows.
5. Android emulator profile launch after the Review Center performance patch.
  - Command: `flutter run --profile --dart-define-from-file=env/dev.json -d emulator-5554`
  - Result: app built, installed, launched, and exposed DevTools successfully.
  - Remaining signal: emulator still logged a startup skipped-frame burst (`Skipped 275 frames`), so emulator/profile startup pressure is real but not specifically tied to Review Center list rendering.

Not reproduced yet:

- A manual long-scroll freeze with hundreds of Review Center rows; current database does not contain that volume.
- A physical-device freeze; no physical Android device is currently connected.
- An iOS simulator freeze; no iOS target is available in this Windows workspace.

## 2. Whether the freeze happens on emulator only or real device too

Current evidence only covers the Android emulator and local code/database inspection.

Available Flutter devices:

- `sdk gphone16k x86 64` Android emulator, `emulator-5554`, Android 17 API 37, `android-x64`.
- Windows desktop.
- Chrome web.
- Edge web.

No physical Android device and no iOS simulator are available from `flutter devices` in this environment, so real-device behavior remains unverified.

## 3. Device/emulator specs

Detected emulator target:

```text
sdk gphone16k x86 64 (mobile) - emulator-5554 - android-x64 - Android 17 API 37
```

Host OS:

```text
Windows 10.0.26200.8655
```

The emulator logs show repeated Android `Skipped ... frames` / `Davey!` messages during startup, which confirms the emulator/debug environment can jank under load. That does not by itself prove the freeze is emulator-only.

## 4. Flutter build mode tested: debug

Debug mode was tested repeatedly through:

```text
flutter run --dart-define-from-file=env/dev.json -d emulator-5554
```

Observed:

- App boots to Flutter UI.
- GoRouter initializes.
- Android reports skipped frames during startup.
- The previous storage verification timeout is gone after `ISSUE-041`.

Debug mode remains the most sensitive to rebuild storms, heavy logging, and emulator CPU pressure.

## 5. Flutter build mode tested: profile

Profile mode completed before and after the Review Center patch:

```text
flutter run --profile --dart-define-from-file=env/dev.json -d emulator-5554
```

Observed:

- Pre-fix profile launch built and installed successfully, then Android logged `Skipped 315 frames` during startup.
- Post-fix profile launch built and installed successfully, then Android logged `Skipped 275 frames` during startup.
- This confirms startup jank is not debug-only in the emulator. It does not prove Review Center is freezing at current live volume, because current live Review Center data remains small.

## 6. Flutter build mode tested: release

Release mode has not yet been completed in this pass.

Expected command:

```text
flutter run --release --dart-define-from-file=env/dev.json -d emulator-5554
```

Release mode should be used after the targeted Review Center changes to confirm there is no production-mode freeze.

## 7. CPU/frame performance findings

Confirmed findings:

- Android emulator debug startup logs contain skipped-frame messages.
- Review Center cards use `SliverList.separated`, not `SingleChildScrollView + Column`, so it does not eagerly build every item.
- Each Review Center card uses a large static `BoxShadow` (`blurRadius: 30`). This is not the primary root cause with 28 items, but it is a rendering cost multiplier if hundreds of cards are visible/rapidly rebuilt.
- The most suspicious CPU/frame pattern is not list construction alone; it is repeated network/provider/rebuild waves caused by sync + realtime + invalidation.

## 8. Memory findings

Current live data size is small enough that memory pressure from `review_items` alone is not proven:

- `28` review items.
- `120` documents.
- `128` document items.

Memory risk remains for future scale because Review Center currently fetches all matching open rows and counts by loading every open review item row into Dart. If review_items grows to hundreds/thousands, memory and parsing pressure will increase.

## 9. Riverpod rebuild findings

Review Center providers:

- `reviewItemsProvider` watches `reviewCenterRealtimeProvider`, `companyIdProvider.future`, and `selectedReviewFilterProvider`.
- `reviewItemCountsProvider` watches `reviewCenterRealtimeProvider` and `companyIdProvider.future`.
- `syncReviewItemsProvider` watches `companyIdProvider.future`, calls `sync_review_items_for_company`, then invalidates `reviewItemsProvider` and `reviewItemCountsProvider`.
- `ReviewCenterScreen.initState` invalidates and reads `syncReviewItemsProvider` after the first frame.

This creates a burst pattern:

1. Open Review Center.
2. Screen auto-runs sync.
3. Sync RPC upserts/updates review rows.
4. Realtime emits one or more events.
5. `reviewItemsProvider` refetches.
6. `reviewItemCountsProvider` refetches.
7. `syncReviewItemsProvider` also explicitly invalidates both providers.

This is not an infinite loop by itself, but it is a request/rebuild storm under heavy update volume.

## 10. Supabase query/realtime findings

Pre-fix Review Center repository:

- `fetchOpenItems()` queries by `company_id` and `status = open`, optionally filters by type, orders by `created_at desc`, then sorts again in Dart by severity and date.
- `fetchOpenItems()` had no limit/pagination.
- `fetchCounts()` queries `review_type, severity` for every open row and counts in Dart.
- `syncCompanyReviewItems()` calls `sync_review_items_for_company`.

Pre-fix realtime:

- `reviewCenterRealtimeProvider` subscribes to all `review_items` changes for the company.
- The realtime callback emitted immediately for every payload; no debounce/coalescing existed.
- Dashboard grid metrics also watch `reviewCenterRealtimeProvider`, so review item changes can invalidate dashboard metrics when that provider is active.

Post-fix app-side changes:

- `fetchOpenItems()` now has a default bounded first-page limit of `120` rows and logs safe timing/row counts.
- `fetchCounts()` still counts all open rows for truthful summary numbers, but logs safe timing/row counts so future scale issues are visible.
- `syncCompanyReviewItems()` logs safe timing and changed-row count.
- `reviewCenterRealtimeProvider` now coalesces realtime bursts with a `600ms` debounce before invalidating dependent providers.
- `ReviewCenterScreen` no longer watches the sync provider in `build`; auto-sync is started after the first frame only when the last auto-sync is stale.
- Manual pull-to-refresh still forces sync.

Schema support:

- Live `review_items` has `review_items_unique_source` on `(company_id, review_type, source_table, source_id)`.
- Live indexes include:
  - `(company_id, status, created_at desc)`
  - `(company_id, review_type, status)`
  - `(company_id, severity, status)`
  - `(company_id, source_table, source_id)`

The database has the right duplicate-prevention/index foundation. The app-side realtime/fetch behavior is the current concern.

## 11. Review Center data volume findings

Live active company volume:

```text
open review_items: 28
total review_items: 28
distinct source_id: 28
```

By type:

```text
product_match_review: 23 open
pos_connection_issue: 2 open
price_anomaly: 2 open
failed_sales_import: 1 open
```

The screenshot showing repeated “Line item needs product match” cards is consistent with multiple distinct product-match source rows, not necessarily duplicates.

## 12. Duplicate review item findings

Duplicate query result:

```text
0 duplicate groups
```

Live constraint:

```text
UNIQUE (company_id, review_type, source_table, source_id)
```

Conclusion: duplicate review item generation is not the current live root cause.

## 13. Navigation/auth redirect findings

GoRouter boot was already hardened in `ISSUE-040`:

- Auth/company route guards are timeout-bounded.
- Route guard failures go to `/bootstrap-recovery`.

No current evidence shows an auth redirect loop. The app boots to `/sign-in` in emulator runs.

Review Center navigation risk is from `initState` auto-sync on every screen entry, not GoRouter redirects.

## 14. Main isolate blocking findings

Confirmed main-isolate risks:

- Review Center currently parses and sorts all fetched open items on the UI isolate.
- Review Center counts scan all open rows on the UI isolate.
- Sales import file picking reads file bytes in Flutter (`File(...).readAsBytes()`), but this is not tied to the Review Center freeze evidence.
- Image compression and document preprocessing already use `compute()` in storage/background extraction paths.

The strongest confirmed main-isolate risk for the reported screenshot area is repeated provider fetch/parse/sort cycles, not a single expensive synchronous algorithm.

## 15. Root cause

The exact freeze was not reproduced with the current small dataset, but the current evidence identifies the most likely root cause for freezes under heavy Review Center use:

Pre-fix, Review Center could create a sync/realtime/provider refetch storm.

The controlling code path is:

- `ReviewCenterScreen.initState` auto-runs `syncReviewItemsProvider` on every screen entry.
- `syncReviewItemsProvider` calls `sync_review_items_for_company` and then invalidates items/count providers.
- The SQL sync function uses `ON CONFLICT DO UPDATE ... updated_at = now()` in its generation blocks, so even unchanged review signals can produce row updates and realtime events.
- `reviewCenterRealtimeProvider` emits immediately for every review item realtime event.
- `reviewItemsProvider` and `reviewItemCountsProvider` both watch that stream and refetch.
- `fetchOpenItems()` and `fetchCounts()` are unbounded and do Dart-side scan/sort work.

With 28 rows this was tolerable. With repeated navigation, syncs, realtime bursts, or hundreds of review items, it could overload debug/emulator and make the app feel frozen.

The implemented fix removes the strongest app-side trigger for that storm by rate-limiting auto-sync, debouncing realtime, and bounding the initial item list. The remaining skipped-frame profile signal is startup/emulator pressure and should be profiled separately if it persists after navigation.

## 16. Minimal safe fix

Implemented only changes supported by the evidence:

1. Add safe performance logs around Review Center fetch/count/sync and realtime lifecycle.
2. Debounce Review Center realtime emissions so bursts become one provider invalidation wave.
3. Rate-limit automatic Review Center sync on screen entry so navigation does not trigger full sync repeatedly.
4. Keep manual pull-to-refresh sync available.
5. Add an initial page limit for `fetchOpenItems()` so Review Center does not render/fetch unlimited rows by default.
6. Preserve `company_id`, RLS, realtime, Review Center functionality, product matching, sales import, extraction, navigation, FAB, and bottom nav.

Do not add database indexes or duplicate cleanup now because live duplicates are absent and the needed indexes/unique constraint already exist.

## 17. Files modified

Modified files:

- `lib/features/review_center/data/repositories/review_center_repository.dart`
  - Add timing logs.
  - Add default fetch limit.
- `lib/features/review_center/presentation/providers/review_center_providers.dart`
  - Add realtime debounce.
  - Add safe lifecycle/perf logs.
  - Add auto-sync rate limiting.
- `lib/features/review_center/presentation/screens/review_center_screen.dart`
  - Use rate-limited auto-sync instead of unconditional sync on every entry.
- `APP_PERFORMANCE_FREEZE_ANALYSIS.md`
  - Record profiling and validation results.
- `PROJECT_CONTEXT.md`
  - Record the issue after validation.

## 18. Files to leave untouched

Do not touch:

- OpenRouter/VLM prompts or extraction model logic.
- `supabase/functions/process-document`.
- `supabase/functions/process-sales-import`.
- Product matching logic.
- Sales/POS integrations.
- RLS policies.
- Storage policies.
- Bottom navigation.
- FAB.
- Broad auth/session handling.

## 19. Validation checklist

Code validation:

- Passed: `flutter analyze lib/features/review_center/data/repositories/review_center_repository.dart lib/features/review_center/presentation/providers/review_center_providers.dart lib/features/review_center/presentation/screens/review_center_screen.dart`
- Passed: VS Code diagnostics clean for `APP_PERFORMANCE_FREEZE_ANALYSIS.md` after the post-fix update.

Data validation:

- Duplicate query still returns zero duplicate groups.
- Review Center still shows the same real open items.
- Resolved/ignored items are not shown in the open list.

Runtime validation:

- Android emulator debug: startup still reaches controlled UI.
- Android emulator profile: patched app builds, installs, launches, and exposes DevTools; startup still logs skipped frames on the emulator.
- Physical Android: pending because no device is connected.
- iOS simulator: unavailable on this Windows workspace.
- Hot restart: app should recover to Flutter UI and not immediately start repeated Review Center sync unless the screen is opened and sync is stale.

Review Center behavior validation:

- Open Review Center once: at most one auto-sync if stale.
- Navigate out/in quickly: no repeated sync on every entry within the cooldown window.
- Realtime burst: provider refetch is debounced.
- Pull to refresh: sync still runs explicitly.
- Resolve/ignore item: list/counts update.
- Many items: first page remains bounded and list uses slivers.

Non-regression validation:

- Dashboard still reads Review Center count.
- VLM extraction unaffected.
- Sales import unaffected.
- Product matching unaffected.
- Tenant-scoped queries preserved.
