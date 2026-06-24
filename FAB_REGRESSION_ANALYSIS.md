# FAB Regression Analysis

Date: 2026-06-01

## 1. Root Cause

The regression was introduced by the premium floating navigation refactor.

The existing FAB action system was not removed or rewritten. `DashboardScreen` still provided `FloatingActionHub.dashboard(ref: ref)`, `DocumentsScreen` still provided `FloatingActionHub.documents(ref: ref, onManual: _handleManual)`, and `FloatingActionHub` still created a `PremiumFAB` with a real `onPressed` callback.

The break was in the UI layer above it: the new glass navigation became a shell-level overlay rendered after the child screen. The FAB remained inside the nested screen `AppScaffold`, while the new `AppBottomNav` occupied the same bottom-center shell region. Visually the center gap made the FAB appear correct, but the shell navigation layer still participated in hit testing across the center area, so taps could stop at the navigation overlay instead of reaching the `PremiumFAB` underneath.

## 2. Broken Event Chain

Expected chain:

```text
User taps PremiumFAB
  -> PremiumFAB.onTap / onPressed
  -> FloatingActionHub._openActions(context)
  -> showGeneralDialog(... _FabActionSheet ...)
  -> AppFabAction selection
  -> action.onTap(screenContext)
  -> GoRouter navigation or CameraUploadService
```

Observed after the navigation refactor:

```text
User taps visible center plus
  -> AppBottomNav shell overlay participates in hit testing over the center gap
  -> PremiumFAB gesture does not reliably receive the tap
  -> FloatingActionHub._openActions is not called
  -> AppFabAction list is never shown
  -> GoRouter / CameraUploadService callbacks are never reached
```

The chain stopped before `PremiumFAB.onPressed()`.

## 3. File Causing Regression

Primary regression surface:

- `lib/shared/ui/app_bottom_nav.dart`

Contributing layout surface:

- `lib/shared/widgets/main_scaffold.dart`

Unaffected action/callback surfaces verified during tracing:

- `lib/shared/ui/premium_fab.dart`
- `lib/shared/fab/floating_action_hub.dart`
- `lib/shared/fab/fab_action_registry.dart`
- `lib/shared/fab/scanner_fab_actions.dart`
- `lib/features/dashboard/presentation/screens/dashboard_screen.dart`
- `lib/features/documents/presentation/screens/documents_screen.dart`

## 4. Why It Happened

The redesign changed the bottom navigation from a normal scaffold bottom bar into a floating shell overlay:

```text
MainScaffold
  -> Stack
     -> child screen Scaffold
        -> screen-owned FloatingActionHub / PremiumFAB
     -> AppBottomNav overlay
```

That made the visual layer order different from the old behavior. The center plus still rendered because the nav had a visual gap, but visual transparency is not the same thing as pointer transparency. Flutter hit testing is based on render objects, not only visible pixels.

The refactor therefore mixed the visual shell layer and the child-screen FAB layer without explicitly preserving pointer pass-through in the center FAB zone.

## 5. Fix Applied

Applied the smallest possible wiring fix in `AppBottomNav`:

- Added a private `_CenterGapHitTestPassThrough` render proxy.
- Wrapped the `AppBottomNav` root with it.
- The proxy returns `false` for hit tests inside the center FAB gap.
- Outside the center gap, hit testing is unchanged, so Home/Sales/Docs/Orders nav icons still receive taps.

This reconnects the existing architecture without changing it:

```text
Center gap tap
  -> AppBottomNav explicitly passes hit test through
  -> underlying PremiumFAB receives tap
  -> existing FloatingActionHub opens
  -> existing AppFabAction callbacks run
```

No FAB system rewrite was performed. No action registry changes were made. No scanner callback changes were made. No Supabase, OpenRouter, extraction, realtime, storage, auth, or tenant-isolation code was touched.

## 6. Files Modified

- `lib/shared/ui/app_bottom_nav.dart`
  - Added center-gap hit-test pass-through for the floating nav overlay.

- `FAB_REGRESSION_ANALYSIS.md`
  - Added this investigation and repair report.

## 7. Validation Checklist

Automated validation:

- [x] Focused analyzer passed with no issues for:
  - `lib/shared/ui/app_bottom_nav.dart`
  - `lib/shared/widgets/main_scaffold.dart`
  - `lib/shared/ui/premium_fab.dart`
  - `lib/shared/fab/floating_action_hub.dart`
  - `lib/shared/fab/fab_action_registry.dart`
  - `lib/shared/fab/scanner_fab_actions.dart`
- [x] Full `flutter analyze` was run. It reports existing project-wide analyzer debt (`639 issues found`, mostly pre-existing info-level lints plus unrelated warnings such as registration/service warnings). No issues were reported by the focused analyzer for the FAB regression files.

Manual validation required on device/emulator:

- [ ] TEST 1: Dashboard -> tap `+` -> animated action menu appears.
- [ ] TEST 2: Dashboard -> tap `Upload expense` -> nested scanner menu opens.
- [ ] TEST 3: Nested scanner menu -> tap `Upload file` -> file picker opens.
- [ ] TEST 4: Nested scanner menu -> tap `Camera` -> `CameraUploadService.handleCameraCapture` starts.
- [ ] TEST 5: Documents -> tap `+` -> direct scanner actions appear.
- [ ] TEST 6: Navigate Home, Sales, Documents, Orders -> FAB remains centered and route taps still work.

## 8. Event Chain After Fix

Dashboard:

```text
PremiumFAB.onPressed
  -> FloatingActionHub.dashboard
  -> dashboardFabActions
  -> Upload expense switches menu level to scanner actions
  -> scannerFabActions
  -> CameraUploadService / GoRouter callbacks
```

Documents:

```text
PremiumFAB.onPressed
  -> FloatingActionHub.documents
  -> scannerFabActions directly
  -> CameraUploadService / manual callback
```
