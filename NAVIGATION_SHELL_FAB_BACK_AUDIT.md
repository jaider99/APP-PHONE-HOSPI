# Navigation Shell, FAB, and Back Button Audit

Date: 2026-06-23

## Executive Summary

HospiDash has a shell ownership mismatch. `MainScaffold` always renders the split floating bottom navigation for every `ShellRoute` page, while individual screens decide whether to insert the center FAB. `AppBottomNav` always reserves a center gap, so shell pages without their own FAB render as two separated pills with an empty hole. Review Center is the visible example; Products, Providers, Expenses, and shell child flows can hit the same issue.

Minimal safe architecture: keep the shell route structure intact, move central FAB ownership into `MainScaffold`, resolve FAB action sets from route UI metadata, and keep the FAB visible wherever the split bottom nav is visible. Use the existing reusable `AppBackButton` for non-root pages.

## 1. Full GoRouter Route Map

Source: `lib/core/router/app_router.dart`.

### Auth and onboarding routes outside shell

| Route | Widget | Category | Bottom nav | FAB | Back/close expectation |
| --- | --- | --- | --- | --- | --- |
| `/login` | `LoginScreen` | Auth | Hidden | Hidden | No app back button |
| `/sign-in` | `SignInScreen` | Auth | Hidden | Hidden | No app back button |
| `/sign-up` | Redirect to `/register/company-id` | Auth redirect | Hidden | Hidden | N/A |
| `/otp-verify` | `OtpScreen` | Auth flow | Hidden | Hidden | Back to sign-in |
| `/forgot-password` | `ForgotPasswordScreen` | Auth flow | Hidden | Hidden | Back to sign-in |
| `/bootstrap-recovery` | `_BootstrapRecoveryScreen` | Auth recovery | Hidden | Hidden | No shell FAB |
| `/register/company-id` | `CompanyIdScreen` | Setup flow | Hidden | Hidden | Back to sign-in |
| `/register/company-details` | `CompanyDetailsScreen` | Setup flow | Hidden | Hidden | Back to company-id, preserve provider state |
| `/register/user-account` | `UserAccountScreen` | Setup flow | Hidden | Hidden | Back to company-details, preserve provider state |
| `/pending-approval` | `PendingApprovalScreen` | Auth/account state | Hidden | Hidden | No shell FAB |

### Fullscreen routes outside shell

| Route | Widget | Category | Bottom nav | FAB | Back/close expectation |
| --- | --- | --- | --- | --- | --- |
| `/expenses/new` | `ExpenseFormScreen` | Create/edit flow | Hidden | Hidden | Close/back to Expenses |
| `/products/:id` | `ProductDetailScreen` | Detail | Hidden | Hidden | Back to Products |

### Shell routes with `MainScaffold`

| Route | Widget | Category | Bottom nav | Current FAB source | Back/close expectation |
| --- | --- | --- | --- | --- | --- |
| `/dashboard` | `DashboardScreen` | Root tab | Visible | Screen-level `FloatingActionHub.dashboard` | No back button |
| `/review-center` | `ReviewCenterScreen` | Root/main section | Visible | None | No back button by default |
| `/sales` | `SalesScreen` | Root tab | Visible | Screen-level `PremiumFAB` | No back button |
| `/sales/import` | `ImportSalesScreen` | Import/setup flow | Visible | None | Back to Sales |
| `/sales/connect-pos` | `ConnectPosScreen` | Setup flow | Visible | None | Back to Sales |
| `/sales/:id` | `SalesScreen(saleId)` | Detail-ish route | Visible | Screen-level `PremiumFAB` from `SalesScreen` | If actual detail UI appears, back to Sales |
| `/documents` | `DocumentsScreen` | Root tab | Visible | Screen-level `FloatingActionHub.documents` | No back button |
| `/documents/review-queue` | `DocumentMergeReviewScreen` | Review/detail flow | Visible | None | Back to Documents |
| `/documents/:id` | `DocumentsScreen(documentId)` | Modal-like detail trigger | Visible | Screen-level `FloatingActionHub.documents` | Sheet close/dismiss |
| `/orders` | `OrdersScreen` | Root tab | Visible | Screen-level `PremiumFAB` | No back button |
| `/orders/:id` | `OrdersScreen(orderId)` | Detail-ish route | Visible | Screen-level `PremiumFAB` from `OrdersScreen` | If actual detail UI appears, back to Orders |
| `/providers` | `ProvidersScreen` | Root/main section | Visible | None | No back button |
| `/providers/:id` | `SupplierDetailScreen` | Detail | Visible | None | Back to Providers |
| `/expenses` | `ExpenseTrackerScreen` | Root/main section | Visible | None | No back button |
| `/products` | `ProductListScreen` | Root/main section | Visible | None | No back button |

### Declared constants with no registered route found

| Constant | Path | Current status |
| --- | --- | --- |
| `AppRoutes.settings` | `/settings` | Constant exists, no `GoRoute` currently registered |
| `AppRoutes.profile` | `/settings/profile` | Constant exists, no `GoRoute` currently registered |

## 2. Root Tab Routes

| Bottom-nav item | Route | Notes |
| --- | --- | --- |
| Home | `/dashboard` | Selected by `/dashboard` prefix |
| Sales | `/sales` | Selected by `/sales` prefix |
| Docs | `/documents` | Selected by `/documents` prefix |
| Orders | `/orders` | Selected by `/orders` prefix |

Root/main shell sections that are not bottom-nav items: `/review-center`, `/providers`, `/expenses`, and `/products`. They currently fall back to Home visually because `_indexFromLocation` returns 0 for unknown shell prefixes.

## 3. Detail Routes

| Route | Widget | Decision |
| --- | --- | --- |
| `/products/:id` | `ProductDetailScreen` | Fullscreen outside shell. Back button required. No bottom nav/FAB. |
| `/providers/:id` | `SupplierDetailScreen` | Inside shell. Back button required. If bottom nav remains, shell FAB must remain. |
| `/documents/:id` | `DocumentsScreen(documentId)` + `DocumentDetailSheet` | Modal-like document detail sheet. Use sheet close/dismiss, not a page back button. |
| `/sales/:id` | `SalesScreen(saleId)` | Route exists but screen currently shares root sales UI. Do not invent detail-specific UI. |
| `/orders/:id` | `OrdersScreen(orderId)` | Route exists but screen currently shares root orders UI. Do not invent detail-specific UI. |

## 4. Create/Edit/Import/Setup Routes

| Route | Widget | Decision |
| --- | --- | --- |
| `/expenses/new` | `ExpenseFormScreen` | Fullscreen outside shell. Close/back required. No shell FAB. |
| `/sales/import` | `ImportSalesScreen` | Inside shell import flow. Back required. Shell FAB should still appear because bottom nav remains. |
| `/sales/connect-pos` | `ConnectPosScreen` | Inside shell setup flow. Back required. Shell FAB should still appear because bottom nav remains. |
| `/documents/review-queue` | `DocumentMergeReviewScreen` | Inside shell review flow. Back required. Shell FAB should still appear because bottom nav remains. |
| `/register/*` | Registration screens | Outside shell setup flow. Back required where existing flow supports it. No shell FAB. |

No registered route was found for a dedicated upload-document page, manual sale entry page, POS setup subpage, edit product page, edit sales import page, settings subpage, or review item detail. Do not add FAB actions for routes that do not exist.

## 5. Modal Routes

| Flow | Implementation surface | Notes |
| --- | --- | --- |
| Document detail | `DocumentDetailSheet.show(...)` from `DocumentsScreen` | Modal-like document detail. |
| Document add options | `AddOptionsSheet.show(...)` / `BottomActionSheet.show(...)` | Modal action selection. |
| FAB action hub | `FloatingActionHub` uses `showGeneralDialog` | Has barrier dismiss and overlay close control. |
| Upload/camera/gallery | `CameraUploadService` calls | Existing document extraction/upload pipeline. |
| Sales delete/import/POS sheets | Shared `showAppSheet` / app sheet system | Must remain above floating nav. |

## 6. Pages Currently Showing Bottom Nav

All routes inside the `ShellRoute` show bottom nav: `/dashboard`, `/review-center`, `/sales`, `/sales/import`, `/sales/connect-pos`, `/sales/:id`, `/documents`, `/documents/review-queue`, `/documents/:id`, `/orders`, `/orders/:id`, `/providers`, `/providers/:id`, `/expenses`, and `/products`.

Auth, registration, pending approval, expense form, and product detail routes are outside the shell and do not show the bottom nav.

## 7. Pages Currently Hiding FAB

Because FAB ownership is screen-level, these shell routes currently show bottom nav but no center FAB: `/review-center`, `/sales/import`, `/sales/connect-pos`, `/documents/review-queue`, `/providers`, `/providers/:id`, `/expenses`, and `/products`.

Routes currently showing a FAB: `/dashboard` via `FloatingActionHub.dashboard`, `/documents` and `/documents/:id` via `FloatingActionHub.documents`, `/sales` and `/sales/:id` via screen-level `PremiumFAB`, and `/orders` and `/orders/:id` via screen-level `PremiumFAB`.

## 8. Pages Missing Back Button

Already handled by the existing `AppBackButton` sweep: `/products/:id`, `/providers/:id`, `/sales/import`, `/sales/connect-pos`, `/expenses/new`, `/documents/review-queue`, `/forgot-password`, `/otp-verify`, and registration steps have back/close controls.

Watch items: `/documents/:id` is a sheet flow, `/sales/:id` and `/orders/:id` are placeholders backed by root screens, and no settings subpage routes currently exist.

## 9. Current Bottom Nav Implementation

`lib/shared/ui/app_bottom_nav.dart` supports exactly four items. It always renders two `_GlassNavSegment` pills separated by `_centerGap = 84` and wraps the whole nav in `_CenterGapHitTestPassThrough`. There is no prop to indicate whether a center FAB is visible and no complete no-FAB layout state.

## 10. Current FAB Implementation

`lib/shared/ui/premium_fab.dart` defines a circular charcoal FAB with 60/64px size, white plus icon, soft shadow, haptic press, hero animation, and 0.96 press scale. It has no route awareness and no open-state plus-to-X rotation.

`lib/shared/fab/floating_action_hub.dart` wraps `PremiumFAB`, opens a `showGeneralDialog`, supports dashboard and documents factories, and uses a separate overlay close FAB.

## 11. Current FAB Action Registry

FAB action files live in `lib/shared/fab/`:

| File | Purpose |
| --- | --- |
| `app_fab_action.dart` | Defines `FabActionType` and `AppFabAction`. |
| `fab_action_registry.dart` | Defines `dashboardFabActions()`. |
| `scanner_fab_actions.dart` | Defines real upload actions using `CameraUploadService`. |
| `floating_action_hub.dart` | Builds dashboard/documents action hubs. |

Current real actions: upload expense submenu, upload file, camera, photo library, manual expense placeholder/callback, and navigation to Expenses, Providers, Products, Orders, and Documents. Sales import and connect POS are real routes but are not yet in the FAB registry.

## 12. Current Back Button Implementation

`lib/shared/widgets/app_back_button.dart` exists and provides circular white Digital Atelier styling, charcoal icon `#151515`, haptic feedback, press scale 0.96, reduced motion support, semantics, and `context.canPop() -> context.pop() -> fallbackRoute` behavior.

## 13. Why FAB Disappears on Some Pages

FAB disappears because the shell owns the bottom nav but screens own the FAB. `MainScaffold` always paints a split nav with a center hole. If the active shell child does not insert its own FAB, the visual hole remains empty.

## 14. FAB Ownership Model

Current FAB behavior is screen-based and partly hardcoded. Dashboard, Documents, Sales, and Orders each define their own FAB behavior. Other shell routes define none. There is no central route metadata and no shell-level action resolver.

## 15. Root Cause

The root cause is split responsibility: `MainScaffold` assumes a center FAB, `AppBottomNav` hardcodes a center gap, but child screens optionally provide the FAB. The shell cannot ask which FAB actions apply because route UI metadata does not exist.

## 16. Minimal Safe Architecture

1. Add typed route UI metadata under `lib/core/navigation/`.
2. Resolve shell route UI by `GoRouterState.matchedLocation`.
3. Move central FAB rendering into `MainScaffold`.
4. Keep the central FAB visible whenever bottom nav is visible.
5. Use global quick actions when no contextual actions exist.
6. Extend the FAB registry only with real routes/features.
7. Remove screen-owned FABs from root shell pages to prevent duplicates.
8. Add `AppBottomNav` adaptive no-FAB support as a future-safe fallback, but keep FAB visible for current shell routes.

## 17. Files to Modify

Likely files:

- `lib/core/navigation/route_ui_config.dart`
- `lib/shared/widgets/main_scaffold.dart`
- `lib/shared/ui/app_bottom_nav.dart`
- `lib/shared/ui/premium_fab.dart`
- `lib/shared/fab/app_fab_action.dart`
- `lib/shared/fab/fab_action_registry.dart`
- `lib/shared/fab/floating_action_hub.dart`
- `lib/features/dashboard/presentation/screens/dashboard_screen.dart`
- `lib/features/documents/presentation/screens/documents_screen.dart`
- `lib/features/sales/presentation/screens/sales_screen.dart`
- `lib/features/orders/presentation/screens/orders_screen.dart`

## 18. Files to Leave Untouched

Do not touch Supabase migrations, Edge Functions, `process-document`, `process-sales-import`, OpenRouter/VLM logic, storage policies, RLS policies, product matching backend, sales import backend, document extraction backend, or tenant isolation/data security logic.

## 19. Validation Checklist

Navigation shell: Dashboard, Sales, Documents, Products, Review Center, Providers, and Expenses have complete bottom nav plus central FAB; no shell route shows split nav pills with an empty center hole; auth/register/fullscreen routes do not show shell FAB; bottom nav selected state remains correct for Home/Sales/Docs/Orders.

FAB: Documents actions use real upload flows; Sales actions use real import/connect POS routes; global fallback uses real existing routes only; FAB opens/closes without stale context; FAB does not appear on auth screens; upload/import/POS flows still work.

Back buttons: Product detail, Supplier detail, Import sales, Connect POS, Expense form, and Document review queue back/close controls work with fallback routes; root tabs do not get unnecessary back buttons.

Safety: Android system back still works; no route loops; delete modals remain above nav; Review Center still fetches data; no backend/security files changed; no RenderFlex overflow on small phones.

## Route Classification Decisions

| Route | Category | Bottom nav | FAB | Back decision |
| --- | --- | --- | --- | --- |
| `/dashboard` | A root tab | Visible | Shell global/contextual | No back |
| `/sales` | A root tab | Visible | Shell sales actions | No back |
| `/documents` | A root tab | Visible | Shell document upload actions | No back |
| `/orders` | A root tab | Visible | Shell global/orders actions | No back |
| `/review-center` | A root/main section | Visible | Shell review/global fallback | No back by default |
| `/products` | A root/main section | Visible | Shell product/global fallback | No back by default |
| `/providers` | A root/main section | Visible | Shell supplier/global fallback | No back by default |
| `/expenses` | A root/main section | Visible | Shell expense/global fallback | No back by default |
| `/products/:id` | B detail | Hidden | Hidden | Back to Products |
| `/providers/:id` | B detail | Visible | Shell global/contextual | Back to Providers |
| `/documents/:id` | D modal-like detail | Visible | Shell document/global | Sheet dismiss |
| `/sales/:id` | B placeholder detail | Visible | Shell sales/global | No dedicated detail UI currently |
| `/orders/:id` | B placeholder detail | Visible | Shell orders/global | No dedicated detail UI currently |
| `/sales/import` | C import flow | Visible | Shell sales/global | Back to Sales |
| `/sales/connect-pos` | C setup flow | Visible | Shell sales/global | Back to Sales |
| `/documents/review-queue` | C review flow | Visible | Shell documents/global | Back to Documents |
| `/expenses/new` | C create/edit flow | Hidden | Hidden | Close/back to Expenses |
| `/register/*` | C setup flow | Hidden | Hidden | Provider-aware back |
| Auth routes | Auth/system | Hidden | Hidden | No shell back |
