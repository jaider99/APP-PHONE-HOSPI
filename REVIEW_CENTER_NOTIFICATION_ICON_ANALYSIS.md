# Review Center Notification Icon Analysis

## Current Review Center Route

- Existing route constant: `AppRoutes.reviewCenter = '/review-center'`
- Existing route registration: `lib/core/router/app_router.dart`
- Existing screen: `ReviewCenterScreen`
- No new route or screen is needed.

## Current Review Center Providers

- `reviewCenterRealtimeProvider` subscribes to `public.review_items` filtered by active `company_id`.
- `reviewItemsProvider` loads open review items for the active company.
- `reviewItemCountsProvider` loads open Review Center counts for the active company.
- `syncReviewItemsProvider` refreshes derived review items through the existing backend RPC.

## Existing Open Review Count Source

The dashboard already exposes real review counts through:

- `dashboardGridMetricsProvider`
- `DashboardGridRepository._fetchReviewRows(companyId)`
- `DashboardGridMetrics.reviewOpenCount`
- `DashboardGridMetrics.reviewCriticalCount`

This source is tenant-safe because it filters by:

- `company_id = active company id`
- `status = 'open'`

It also watches `reviewCenterRealtimeProvider`, so dashboard review counts refresh when `review_items` changes.

For the dashboard bell, the safest implementation is to reuse `dashboardGridMetricsProvider.valueOrNull?.reviewOpenCount` instead of creating a duplicate query provider.

## Current Dashboard Review Banner Location

The large Review Center dashboard entry is currently inside:

- `lib/features/dashboard/presentation/widgets/dashboard_intelligence_grid.dart`
- `_DashboardReviewTile`
- Rendered below the 2x2 dashboard grid as an extra fifth tile.

This is the dashboard clutter to remove.

## Dashboard Header / App Shell Findings

- `DashboardScreen` currently starts directly with `ExpenseLineChart` after the earlier greeting/header block was removed.
- There is no dedicated `dashboard_header.dart` in the current implementation.
- Shared shell components exist (`MainScaffold`, `AppScaffold`, bottom nav/FAB), but the bell belongs only to dashboard access for now.

## Safest Widget Placement

Add a lightweight top `SliverToBoxAdapter` in `DashboardScreen` before `ExpenseLineChart`:

- `SafeArea(bottom: false)`
- horizontal padding using existing `AppSpacing.screenPadding`
- `Row(mainAxisAlignment: MainAxisAlignment.end)`
- `ReviewNotificationButton`

This preserves a clean top-right dashboard header area for future features without reintroducing the old greeting/company header.

## Reusable Widget Location

Create:

- `lib/features/review_center/presentation/widgets/review_notification_button.dart`

Reason:

- The widget is Review Center-specific.
- It can be reused by dashboard or future app shell/header surfaces.
- It should not live in generic shared widgets until another feature needs it.

## Files To Modify

- `lib/features/dashboard/presentation/screens/dashboard_screen.dart`
  - Add the top-right notification button.
  - Pass real open count from `dashboardGridMetricsProvider`.
  - Navigate with `context.go(AppRoutes.reviewCenter)`.
  - Remove `onReviewTap` from the dashboard grid call.

- `lib/features/dashboard/presentation/widgets/dashboard_intelligence_grid.dart`
  - Remove `_DashboardReviewTile` and the fifth review tile.
  - Remove `onReviewTap` from constructor/API.
  - Keep the existing 2x2 grid only.

- `lib/features/review_center/presentation/widgets/review_notification_button.dart`
  - Add `ReviewNotificationButton`.
  - Add custom `PremiumBellIcon` / `_PremiumBellPainter`.
  - Add subtle badge for count > 0.

## Files To Leave Untouched

- Supabase migrations
- Supabase Edge Functions
- OpenRouter/process-document/extraction logic
- Product/supplier/price anomaly logic
- RLS/storage/auth
- Review Center screen and route
- Review Center repository business actions
- Bottom navigation and FAB

## Implementation Plan

1. Create `ReviewNotificationButton` with a custom `CustomPainter` bell icon.
2. Use a 44x44 tap target, 24-26px icon, transparent/subtle surface, scale-to-0.96 press state, and light haptic feedback.
3. Badge rules:
   - no badge for zero/open count unavailable
   - show `1` through `9`
   - show `9+` for counts above 9
   - use `#151515` badge with white text and subtle background-colored separation.
4. Add the button to the dashboard top-right area.
5. Remove the large Review Center tile from `DashboardIntelligenceGrid`.
6. Reuse `dashboardGridMetricsProvider` as the dashboard count source.
7. Keep tap navigation to `AppRoutes.reviewCenter`.

## Validation Checklist

- Dashboard loads with a top-right minimalist bell.
- No large Review Center / Needs Review tile remains in the dashboard grid.
- Count 0 or loading/error shows bell without badge.
- Count 1-9 shows a compact badge with that number.
- Count > 9 shows `9+`.
- Tapping the bell opens the existing Review Center route.
- Review Center screen remains unchanged and real-data backed.
- `review_items` count remains tenant-filtered by active `company_id`.
- Realtime updates still flow through `dashboardGridMetricsProvider` watching `reviewCenterRealtimeProvider`.
- Dashboard does not crash if review count is unavailable.
- Focused Flutter diagnostics pass for touched files.
