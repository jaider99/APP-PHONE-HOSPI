# Upload Screen Redesign Plan

## 1. Current Widget Structure

Primary screen owner:

- `lib/features/expenses/presentation/screens/expense_form_screen.dart`

Current screen structure:

1. `ExpenseFormScreen`
2. `AppScaffold`
3. `AppTopBar` with close action and `Save` text action
4. Scrollable body
5. `_InfoBanner`
6. `_SectionLabel(index: '1', label: 'Upload image')`
7. `_PagePreviewRow`
8. Category dropdown
9. `_SectionLabel(index: '2', label: 'More options', trailing: Switch.adaptive)`
10. `_MoreOptionsSection` when expanded
11. Inline submit error container
12. `_StickyCTA` bottom action

Current upload preview composition:

- `_PagePreviewRow` renders a horizontal `ListView`
- Uses `_SelectedDocumentThumb` when `pages.isEmpty`
- Uses `_PageThumb` for each uploaded page in `formState.pages`
- Always appends `_AddPageButton`

Current motion state:

- No screen entrance choreography
- No animated card press states
- No page focus scaling in carousel
- No CTA attention animation
- Existing interactivity is mostly default `InkWell`, `GestureDetector`, and `Switch.adaptive`

## 2. Existing Upload Flow

Route entry:

- `lib/services/camera_upload_service.dart`
- `_navigateToExpenseForm(...)` pushes `AppRoutes.expenseForm`
- Route extra contains `ExpenseFormArgs(fileBytes, companyId, fileName, mimeType, initialPages)`

Route resolution:

- `lib/core/router/app_router.dart`
- `GoRoute(path: AppRoutes.expenseForm, ...) => ExpenseFormScreen(args: args)`

State source of truth:

- `lib/features/expenses/presentation/providers/expense_form_provider.dart`
- `ExpenseFormNotifier` owns:
  - `pages`
  - category and metadata fields
  - `moreOptionsExpanded`
  - `isSubmitting`
  - `submitError`

Upload actions:

- Add page: `_pickAdditionalPage()` in `ExpenseFormScreen`
- Add page callback: `notifier.addPage(bytes)`
- Delete page callback: `notifier.removePage(index)`
- Submit callback: `notifier.submit()`

Submission pipeline preserved by provider:

- `ExpenseFormNotifier.submit()`
- `documentUploadServiceProvider.submitExpenseFlow(...)`
- storage upload, document creation, page metadata, extraction, and invalidation remain outside the screen

## 3. Existing Callbacks That Must Remain Untouched

Behavior-critical callbacks and owners:

- `CameraUploadService._navigateToExpenseForm(...)`
- `ExpenseFormScreen._pickAdditionalPage(...)`
- `ExpenseFormNotifier.addPage(Uint8List bytes)`
- `ExpenseFormNotifier.removePage(int index)`
- `ExpenseFormNotifier.submit()`
- `DocumentDeleteService.deleteDocument(...)` duplicate discard branch
- document invalidation calls inside `ExpenseFormNotifier.submit()`

These must remain semantically unchanged:

- Route args shape
- Real page list state in `ExpenseFormState.pages`
- Multi-page add/remove behavior
- Submit success/error handling
- Snackbar and duplicate-dialog flow
- Upload CTA wiring

## 4. Components Safe To Redesign

Safe presentation-layer targets:

- Overall layout and spacing in `ExpenseFormScreen`
- Header copy and typography treatment
- `_InfoBanner`
- `_SectionLabel`
- `_PagePreviewRow`
- `_SelectedDocumentThumb`
- `_PageThumb`
- `_AddPageButton`
- `_StickyCTA`
- Form field wrappers and visual styling of dropdown/text fields
- Scroll physics and page carousel visuals
- Entrance and micro-interaction animations
- Small reusable animation/presentation helpers added under `lib/features/expenses/presentation/widgets/` or `lib/shared/animations/`

## 5. Components NOT Safe To Touch

Do not modify:

- `VLM extraction`
- `OpenRouter calls`
- `Supabase Edge Functions`
- `StorageService`
- `ExtractionService`
- `BackgroundExtractionService`
- `document_pages` / page metadata logic
- document creation flow
- PDF/image preprocessing
- multi-page upload logic
- RLS policies
- schema / SQL
- `company_id` logic
- providers / repositories business behavior

Within Flutter, avoid behavioral changes to:

- `ExpenseFormNotifier.submit/addPage/removePage`
- `CameraUploadService`
- route shape in `app_router.dart`

## 6. Animation Implementation Plan

Screen entrance:

- Convert `ExpenseFormScreen` state to own one `AnimationController`
- Create four staggered intervals for:
  1. header
  2. upload card
  3. page carousel
  4. bottom actions
- Motion: `FadeTransition` + `SlideTransition`
- Offset: `Offset(0, 0.08)` equivalent to about 20 px on mobile
- Curve: `Curves.easeOutCubic`
- Reduced motion: switch to fade-only with near-zero translation

Carousel motion:

- Keep same `pages` source and callbacks
- Replace plain horizontal `ListView` feel with a `PageController`-driven or scroll-notifier-driven horizontal carousel
- Add focused-card scale interpolation `1.0` center, `0.96` off-axis
- Use platform-appropriate `BouncingScrollPhysics` on iOS-like feel while preserving drag behavior
- Do not change page add/remove semantics

Interactive previews:

- Each page card becomes a pressable stateful widget
- Add `AnimatedScale` press-down to `0.95`
- Add subtle tonal shift via `AnimatedContainer`
- Keep image bytes stable and avoid rebuilding image providers every animation frame

Delete button:

- Preserve `onDelete`
- Add small scale press feedback
- Animate fill/surface from soft terracotta to deeper terracotta
- Keep touch target at least 44x44

Add Page card:

- Preserve `onTap`
- Add quiet pulse on plus icon using a slow repeating animation
- Add background tonal transition on press/hover state
- Keep interaction subtle and disable pulse when reduced motion is enabled

Upload CTA:

- Preserve `onPressed`
- Restyle as charcoal pill (`#151515`) with premium depth
- Add one-shot subtle pulse or restrained shine when CTA is near viewport focus
- Do not create continuous distracting shimmer
- Respect reduced motion and fall back to static emphasis

Accessibility:

- Use `MediaQuery.disableAnimations`
- Disable pulse, scale, and carousel depth when reduced motion is on
- Keep semantic labels for delete, preview, add page, and upload actions

## 7. Files That Will Change

Expected primary change file:

- `lib/features/expenses/presentation/screens/expense_form_screen.dart`

Possible supporting files if needed for clean reuse:

- `lib/shared/animations/` new helper(s)
- or a new presentation-only helper under `lib/features/expenses/presentation/widgets/`

Files inspected but not planned for behavioral changes:

- `lib/features/expenses/presentation/providers/expense_form_provider.dart`
- `lib/services/camera_upload_service.dart`
- `lib/core/router/app_router.dart`

## 8. Risk Analysis

Primary risk:

- Accidentally changing page add/remove/submit behavior while refactoring the layout.

Mitigations:

- Keep `ExpenseFormNotifier` untouched.
- Preserve exact callback wiring from the screen to the notifier.
- Limit edits to the presentation layer.
- Validate with focused analysis on the touched UI files.

Secondary risks:

- Over-animating and harming premium tone.
- Breaking reduced-motion expectations.
- Rebuilding heavy image widgets during animations.
- Causing bottom CTA overlap with safe area or nav gestures.

Mitigations:

- Use transform/opacity animations only.
- Read `MediaQuery.disableAnimations` and degrade gracefully.
- Isolate animated chrome around stable `Image.memory` content.
- Preserve safe-area padding already present in `_StickyCTA`.

## 9. Implementation Boundary Confirmation

The redesign will preserve the upload pipeline exactly as-is.

Confirmed preserved layers:

- document selection
- camera/gallery/file picker entry
- real multi-page state
- upload callback chain
- Supabase storage flow
- document creation
- background extraction
- Edge Function processing
- OpenRouter extraction
- tenant scoping

Only the presentation layer will be modified.