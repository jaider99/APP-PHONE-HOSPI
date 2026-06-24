# Back Navigation Audit

## 1. Current GoRouter Route Map

### Auth and onboarding routes

| Route | Screen | Notes |
| --- | --- | --- |
| `/login` | `LoginScreen` | Alternate auth entry |
| `/sign-in` | `SignInScreen` | Primary auth entry |
| `/sign-up` | Redirects to `/register/company-id` | No standalone screen |
| `/otp-verify` | `OtpScreen` | Verification flow |
| `/forgot-password` | `ForgotPasswordScreen` | Password recovery |
| `/register/company-id` | `CompanyIdScreen` | Registration step 1 |
| `/register/company-details` | `CompanyDetailsScreen` | Registration step 2, guarded by step 1 |
| `/register/user-account` | `UserAccountScreen` | Registration step 3, guarded by step 2 |
| `/pending-approval` | `PendingApprovalScreen` | Waiting state after manager registration |

### Root-level non-shell routes

| Route | Screen | Notes |
| --- | --- | --- |
| `/expenses/new` | `ExpenseFormScreen` | Fullscreen form outside shell |
| `/products/:id` | `ProductDetailScreen` | Fullscreen detail outside shell |

### ShellRoute routes using `MainScaffold`

| Route | Screen | Notes |
| --- | --- | --- |
| `/dashboard` | `DashboardScreen` | No-transition shell child |
| `/review-center` | `ReviewCenterScreen` | Shell child, not bottom-nav item |
| `/sales` | `SalesScreen` | No-transition shell child |
| `/sales/import` | `ImportSalesScreen` | Nested under sales |
| `/sales/connect-pos` | `ConnectPosScreen` | Nested under sales |
| `/sales/:id` | `SalesScreen(saleId)` | Route exists, but current screen does not branch into a dedicated detail header |
| `/documents` | `DocumentsScreen` | No-transition shell child |
| `/documents/review-queue` | `DocumentMergeReviewScreen` | Nested document review flow |
| `/documents/:id` | `DocumentsScreen(documentId)` | Opens `DocumentDetailSheet` after first frame |
| `/orders` | `OrdersScreen` | No-transition shell child |
| `/orders/:id` | `OrdersScreen(orderId)` | Route exists, but current screen does not branch into a dedicated detail header |
| `/providers` | `ProvidersScreen` | Shell child, not bottom-nav item |
| `/providers/:id` | `SupplierDetailScreen` | Detail screen |
| `/expenses` | `ExpenseTrackerScreen` | Shell child, not bottom-nav item |
| `/products` | `ProductListScreen` | Shell child, not bottom-nav item |

## 2. All Root Tab Screens

These are the true bottom-navigation roots controlled by `MainScaffold` and `AppBottomNav`:

- `/dashboard`
- `/sales`
- `/documents`
- `/orders`

Additional shell-level top destinations that behave like root sections, even though they are not bottom-nav items:

- `/products`
- `/providers`
- `/expenses`
- `/review-center`

## 3. All Detail Screens

### Dedicated detail screens

- `/products/:id` → `ProductDetailScreen`
- `/providers/:id` → `SupplierDetailScreen`

### Route-level details that currently materialize as reused root screens or sheets

- `/documents/:id` → `DocumentsScreen(documentId)` immediately opens `DocumentDetailSheet`
- `/sales/:id` → `SalesScreen(saleId)` but the current UI does not render a dedicated sale-detail header state
- `/orders/:id` → `OrdersScreen(orderId)` but the current UI does not render a dedicated order-detail header state

### Review/detail-like nested flows

- `/documents/review-queue` → `DocumentMergeReviewScreen`

## 4. All Modal and Fullscreen Flows

### Bottom sheets and modal flows

- `DocumentDetailSheet.show(...)` from `DocumentsScreen`
- `AddOptionsSheet.show(...)` from `DocumentsScreen`
- Shared `showAppSheet(...)` flows in sales (import management, POS actions, confirmations)
- Document action sheets and confirmation sheets under documents widgets

### Fullscreen routed flows

- `/products/:id`
- `/expenses/new`
- `/sales/import`
- `/sales/connect-pos`
- `/documents/review-queue`
- registration steps under `/register/*`
- `/forgot-password`
- `/otp-verify`

## 5. All Create, Edit, Import, and Setup Screens

| Route or flow | Screen | Category |
| --- | --- | --- |
| `/sales/import` | `ImportSalesScreen` | Import flow |
| `/sales/connect-pos` | `ConnectPosScreen` | POS setup flow |
| `/expenses/new` | `ExpenseFormScreen` | Create or edit expense |
| `/register/company-id` | `CompanyIdScreen` | Setup step 1 |
| `/register/company-details` | `CompanyDetailsScreen` | Setup step 2 |
| `/register/user-account` | `UserAccountScreen` | Setup step 3 |
| Sales edit sheet | `_SaleEditSheet` in `sales_screen.dart` | Bottom-sheet edit flow |
| Document merge review | `DocumentMergeReviewScreen` | Review and resolve flow |

## 6. Which Screens Currently Have a Back Button

| Screen | Current implementation |
| --- | --- |
| `ImportSalesScreen` | `AppTopBar.leading` with `IconButton(Icons.arrow_back_rounded)` and `context.pop()` |
| `ConnectPosScreen` | `AppTopBar.leading` with `IconButton(Icons.arrow_back_rounded)` and `context.pop()` |
| `ExpenseFormScreen` | `AppTopBar.leading` with a close-style `IconButton` |
| `ProductDetailScreen` | Local `_BackToProductsButton` with `context.canPop()` fallback to `/products` |
| `SupplierDetailScreen` | Local `_BackButton` in the sliver app bar |
| `ForgotPasswordScreen` | Custom circular `GestureDetector` back control |
| `OtpScreen` | Custom circular `GestureDetector` back control |
| `CompanyIdScreen` | Custom rounded back control near the top of the form |
| `CompanyDetailsScreen` | Custom `CircleAvatar` back control in header |
| `UserAccountScreen` | Custom `CircleAvatar` back control in header |

## 7. Which Screens Are Missing a Back Button

### Missing and should be fixed

- `DocumentMergeReviewScreen` at `/documents/review-queue`

### Routes that look like details in the router but do not currently render a distinct detail page

- `SalesScreen(saleId)` at `/sales/:id`
- `OrdersScreen(orderId)` at `/orders/:id`

These should not receive a blind back-button patch until they actually render dedicated detail-state UI. Right now they still behave like the root screens.

## 8. Which Screens Should NOT Have a Back Button

### Root tabs

- `DashboardScreen`
- `SalesScreen` root state
- `DocumentsScreen` root state
- `OrdersScreen` root state

### Shell-level section roots with persistent shell navigation

- `ProductListScreen`
- `ProvidersScreen`
- `ExpenseTrackerScreen`
- `ReviewCenterScreen`

### Auth states that are true entry points or passive wait states

- `LoginScreen`
- `SignInScreen`
- `PendingApprovalScreen`

### Modal and bottom-sheet flows

These should continue to use close or dismiss patterns instead of back buttons:

- `DocumentDetailSheet`
- `AddOptionsSheet`
- shared sales sheets and confirmations
- document confirmations and pickers

## 9. Current Navigation Shell and Bottom Navigation Behavior

- `MainScaffold` wraps shell children with a floating glass bottom nav.
- `AppBottomNav` exposes exactly four items: Home, Sales, Docs, Orders.
- `MainScaffold._indexFromLocation()` only marks those four routes as active; all other shell routes fall back to index `0` visually.
- Shell children outside the bottom-nav item set (`/products`, `/providers`, `/expenses`, `/review-center`) still show the floating nav and remain escapable through shell navigation.
- Because of that shell behavior, those section roots should not receive redundant back buttons by default.
- Fullscreen routes outside the shell (`/products/:id`, `/expenses/new`) need self-contained back or close affordances.

## 10. Recommended Reusable Back Button Component

Create `AppBackButton` in `lib/shared/widgets/app_back_button.dart`.

Recommended API:

```dart
AppBackButton(
  fallbackRoute: AppRoutes.documents,
  tooltip: 'Back',
  semanticLabel: 'Go back',
  useCloseIcon: false,
)
```

Recommended behavior:

- If `context.canPop()` is true, call `context.pop()`.
- Otherwise, if `fallbackRoute` is provided, call `context.go(fallbackRoute)`.
- Apply `HapticFeedback.selectionClick()` on tap.
- Disable press-scale animation when `MediaQuery.disableAnimations` is true.

Recommended styling aligned to Digital Atelier:

- 48 to 52 px visual size
- Circular shape
- White or `surfaceContainerLowest` background
- Icon color `#151515`
- Ambient shadow `0px 20px 40px rgba(26, 28, 28, 0.06)`
- No hard border
- Optional 15% `outlineVariant` ghost border only if needed for contrast

## 11. Files To Modify

### Audit artifact

- `BACK_NAVIGATION_AUDIT.md`

### Shared reusable component

- `lib/shared/widgets/app_back_button.dart`

### Shared export surface if needed

- `lib/shared/widgets/...` barrel file or the nearest shared export file actually used by the codebase

### Screen files to normalize or patch

- `lib/features/documents/presentation/screens/document_merge_review_screen.dart`
- `lib/features/sales/presentation/screens/import_sales_screen.dart`
- `lib/features/sales/presentation/screens/connect_pos_screen.dart`
- `lib/features/expenses/presentation/screens/expense_form_screen.dart`
- `lib/features/products/presentation/screens/product_detail_screen.dart`
- `lib/features/providers/presentation/screens/supplier_detail_screen.dart`
- `lib/screens/auth/forgot_password_screen.dart`
- `lib/screens/auth/otp_screen.dart`
- `lib/screens/registration/company_id_screen.dart`
- `lib/screens/registration/company_details_screen.dart`
- `lib/screens/registration/user_account_screen.dart`

### Optional follow-up only if safe and necessary

- `lib/shared/ui/app_scaffold.dart` if a shared top-bar leading slot helper is useful without broad refactor

## 12. Files To Leave Untouched

### Navigation boundaries to preserve

- `lib/shared/widgets/main_scaffold.dart`
- `lib/shared/ui/app_bottom_nav.dart`

### Business logic and backend-adjacent files to avoid

- Supabase migrations
- Supabase Edge Functions
- document extraction pipeline
- sales import pipeline
- OpenRouter logic
- storage and RLS logic
- product matching logic

### Route behavior to avoid changing unless a dedicated follow-up is requested

- `lib/core/router/app_router.dart` shell structure
- existing auth redirects and route guards

## 13. Validation Checklist

- [ ] Root dashboard still has no back button.
- [ ] Root sales still has no back button.
- [ ] Root documents still has no back button.
- [ ] Root orders still has no back button.
- [ ] Product detail back button still works and falls back to `/products` safely.
- [ ] Supplier detail back button still works.
- [ ] Import sales screen uses the shared premium back button.
- [ ] Connect POS screen uses the shared premium back button.
- [ ] Expense form keeps a safe dismiss affordance.
- [ ] Document merge review screen gains a visible back button.
- [ ] Registration step screens still allow safe backward movement without breaking guards.
- [ ] Forgot password and OTP keep visible backward navigation.
- [ ] `context.canPop()` false fallback works where configured.
- [ ] Android system back still works.
- [ ] Shell bottom nav still works exactly as before.
- [ ] FAB behavior stays unchanged.
- [ ] No GoRouter route loops are introduced.
- [ ] No providers, Supabase auth, or business logic files are touched.
- [ ] All updated back controls follow the Digital Atelier styling and safe-area placement.

## Recommended Implementation Scope

1. Build one shared `AppBackButton`.
2. Replace ad hoc back controls in screens that already need one.
3. Add the shared back control to `DocumentMergeReviewScreen`.
4. Leave root shell screens untouched.
5. Leave `/sales/:id` and `/orders/:id` alone in this pass because they are not yet separate detail UIs.