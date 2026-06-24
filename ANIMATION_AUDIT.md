# HospiDash Animation Audit

Date: 2026-05-28
Phase: 1 - Audit and roadmap only

## Executive Summary

HospiDash already has some good motion foundations: a central `AppMotion`, fast FAB press feedback, a scanner-first sheet, skeleton loading, and a chart draw animation. The current system still feels less premium because motion is inconsistent by area: some components use the new 90-240ms token system, others use hardcoded 300-600ms transitions, registration uses long staggered fades, documents use shimmer plus spinner plus animated dots at once, and route transitions are mostly absent.

The premium fintech direction should be fast, calm, and invisible. Motion should confirm taps, preserve spatial relationships, explain status changes, prevent harsh data swaps, and improve perceived loading. It should not decorate routine work.

Primary recommendation: create a small shared motion layer, then migrate the shell, scanner flow, dashboard, documents, products, and suppliers onto those primitives. Keep all backend, Supabase, realtime, extraction, and tenant-isolation logic untouched.

## Motion Principles

| Principle | HospiDash rule |
|---|---|
| Should this animate at all? | Only animate feedback, spatial continuity, state indication, jarring changes, transition explanation, or perceived performance. |
| Frequency governs intensity | Daily navigation and scanner actions get 80-180ms feedback. Occasional sheets get 240-280ms. Rare onboarding can use slightly more polish. |
| Fintech motion is restrained | No bounce, elastic, playful wobble, parallax, excessive blur, or decorative loops. |
| Route changes must feel immediate | Bottom nav taps should change route immediately while the icon indicator settles quickly. |
| Data updates should not flicker | Financial numbers and statuses should switch with stable layout and short fade/scale, not rebuild whole cards. |
| Loading should feel operational | Prefer skeletons and stable placeholders over full-screen spinners. |
| Reduced motion is required | Translate/slide motion should collapse to opacity/color changes when reduced motion is enabled. |

## Current Motion Inventory

| Area | Current behavior | Problem | Better behavior | Why |
|---|---|---|---|---|
| Global tokens | `lib/core/theme/app_motion.dart` defines `micro` 90ms, `fast` 120ms, `standard` 180ms, `emphasised` 240ms, `skeletonPulse` 1200ms, enter/exit/press curves. | Good base, but naming differs from requested system and adoption is partial. `exit = easeInCubic` can feel sluggish if overused. | Extend tokens to `instant`, `normal`, `sheet`, `slow`, keep aliases for current names, add reduced-motion helpers. | Centralizes taste and prevents hardcoded drift. |
| Router shell | Shell tabs use `NoTransitionPage`. Detail/fullscreen routes use default GoRouter builders. | Tab switch is immediate but lacks indicator continuity. Detail transitions may feel inconsistent by platform. | Keep tab route change immediate. Add nav indicator motion only. Consider a 180ms shared-axis style transition for fullscreen detail routes later. | Navigation should feel fast, not theatrical. |
| Floating navigation | `AppBottomNav` uses `AnimatedContainer` 180ms easeOutCubic for active icon pill. Icons only after latest change. | Active indicator changes per item rather than moving as one object. No icon opacity/scale differentiation. | Use one moving pill/indicator with `AnimatedAlign` or `TweenAnimationBuilder`, icon scale max 1.04, opacity 0.55 -> 1.0. | A moving indicator gives spatial continuity without slowing route changes. |
| FAB | `PremiumFAB` uses press scale 0.97 for 120ms easeOutCubic and Hero arc tween. | Good feedback. Hero may be unnecessary if not paired with a stable destination. No haptic policy. | Keep press. Add optional light haptic for primary scanner action only. Avoid decorative Hero unless a matching element exists. | Immediate tactile confirmation is correct for high-value action. |
| Scanner action sheet | Uses default `showModalBottomSheet`, dim barrier 0.32, `AnimatedPadding` 240ms, press scale on rows. | Sheet relies on platform default transition and has no row entrance rhythm. Primary/secondary row press code is duplicated. | Use `showAppSheet` or custom route with 260ms easeOutCubic slide, 160ms barrier fade, tiny row fade-slide stagger capped at 120ms. Use `AppPressable`. | Preserves bottom-up spatial transition and makes the scanner flow feel confident. |
| Generic bottom sheets | `showAppSheet` wraps `showModalBottomSheet`; keyboard inset padding animates 120ms. | Good wrapper, but sheet transition is still default and rows lack press feedback. | Centralize sheet route timing and row press feedback. | Sheets are frequent enough to need consistency. |
| Dashboard refresh | Uses `RefreshIndicator`. | Native and expected, but default indicator styling can feel generic. | Keep native behavior; ensure accent color and no extra animation around refresh completion. | Pull-to-refresh is a common mobile gesture; do not overdesign it. |
| Dashboard chart | `ExpenseLineChart` uses `AnimationController` 600ms easeOutCubic to draw line. Skeleton shimmer repeats 1500ms via `flutter_animate`. | 600ms can feel slightly slow for a finance dashboard if repeated often. Shimmer dependency differs from shared skeleton primitive. | Draw line only on first load or period change, 360-450ms. Use shared skeleton pulse or a subtle shimmer token. | Chart motion can explain data loading, but should not slow routine use. |
| Dashboard chart header | `AnimatedSwitcher` 150ms fade for amount/date changes while touching chart. | Good duration, but financial values are swapped rather than numerically transitioned. | Use `AnimatedValue` for meaningful KPI changes; keep touch scrubbing instant/fade-only. | Scrubbing should feel responsive; KPI changes can be polished. |
| Period selector | `TweenAnimationBuilder` press scale 120ms and active pill `AnimatedContainer` 180ms. | Good start. Active pill changes in place, not a sliding indicator. | Use a single sliding active pill, 180-220ms easeOutCubic, while text color transitions. | Fintech tabs feel better when the selection travels. |
| KPI cards | Static after recent visual polish. | No skeleton-to-content transition; sudden data availability can feel abrupt. | Wrap cards in `FadeSlideIn` after first load; animate meaningful value changes only. | Prevents harsh loading swaps without animating every rebuild. |
| Intelligence/category rows | Linear progress bars and card shimmer. | Progress can appear abruptly; no standardized list entrance. | Progress bars use 220ms easeOutCubic on first reveal; rows stagger 25-30ms capped at 150ms. | Analytical content should settle quickly and quietly. |
| Documents loading | `DocumentCardShimmer` uses package shimmer; screen shows 6 shimmer cards. | Shimmer is louder than the app's quiet fintech direction and differs from `SkeletonBlock`. | Use shared skeleton row/cards with 1200ms pulse or very subtle shimmer. | Loading should communicate structure, not attract attention. |
| Document processing card | Per-card `AnimationController` repeats 1200ms for animated dots, plus shimmer thumbnail, plus spinner. | Too many simultaneous loops; looks busy and operationally cheap. Per-card controllers can scale poorly in long lists. | Replace with `AnimatedStatusSwitcher`; one stable badge: Queued, Extracting, Completed, Failed. Keep one subtle progress affordance only. | Status motion should clarify pipeline state without noise. |
| Document list updates | SliverList appears all at once; new realtime documents likely pop into place. | New uploads/status updates can feel abrupt. | Optimistic/new inserted cards fade-slide from top 180-220ms; status text/badge switches 160-200ms. Avoid reanimating old rows. | Realtime operations need confidence and spatial continuity. |
| Document detail sheet | `showModalBottomSheet`; images fade in 100ms; multiple spinners for loading/action states. | Sheet transition is generic; multiple spinners reduce perceived quality. | Use unified sheet route; thumbnail fade 160-220ms from skeleton; action buttons use stable-width `AnimatedSwitcher`. | Details should feel like a native inspection panel. |
| Upload progress | Linear progress indicator appears/disappears instantly. | Upload state can jump into view and shift layout. | Fade/slide in 160ms, stable height reserved while upload active, done state collapses 120ms. | Scanner/upload flow should feel reliable. |
| Expense tracker progress bars | `AnimatedContainer` width 600ms easeOut. | 600ms is long for common analytics rows. | 220-300ms easeOutCubic on first reveal; no repeated animation on rebuild. | Keeps analytics calm and fast. |
| Expense form upload/extraction states | Uses snackbars, circular progress indicators, and long 3s snackbar duration. | Feedback exists, but button/state transitions are not centralized. | Stable button with `AnimatedSwitcher`: idle, saving, queued, done, failed. Keep width stable. | Users need confidence after submitting documents. |
| Products list | Skeleton grid for loading. Search debounce 400ms. | Loading is acceptable; list entry not standardized. | First load fade-slide grid items 25ms capped. Do not animate filtered search results heavily. | Product browsing should stay fast. |
| Product detail | Loading spinners and skeleton chart. Price history/anomaly content appears statically. | High-value intelligence can feel flat or abrupt. | Chart line draw 360-450ms first render, anomaly badge `AnimatedStatusSwitcher`, section fade-slide. | Product intelligence should feel analytical, not CRUD. |
| Suppliers list/detail | Skeletons and static spend sections. | Supplier analytics lacks transition polish. | List first-load fade-slide; spend values `AnimatedValue`; chart first-render line draw. | Supplier intelligence should feel like finance analytics. |
| Sales screen | Custom shimmer skeleton 1500ms, insight refresh rotates 500ms, `AnimatedSwitcher` 300ms, legend chips 200ms. | Some pieces are good, but 500ms refresh and 300ms insight switch are a bit slow. Skeleton uses a different implementation. | Standardize skeleton; refresh rotation 240-300ms or progress state; insight switch 180-220ms fade/scale. | Sales should match the main finance motion language. |
| Registration/onboarding | `flutter_animate` fade-ins 300-400ms with delays up to 600ms; elastic password success animation. | Fine for rare onboarding, but long and playful compared with serious SaaS. Elastic is off-brand. | Keep rare-flow stagger but cap total delay around 240ms; remove elastic, use scale 0.98->1 + fade. | Registration can be polished but should still feel serious. |
| Auth screens | Login button uses spinner; custom checkbox animates 150ms. | Mostly acceptable. Spinner-only buttons could feel generic. | Stable button `AnimatedSwitcher` for loading; checkbox 120-150ms stays. | Auth should feel responsive and trustworthy. |
| Skeleton system | `SkeletonBlock`, sales `SkeletonLoader`, shimmer package, and flutter_animate shimmer all coexist. | Inconsistent loading texture and multiple controllers. | One shared skeleton primitive with reduced-motion behavior; use it across dashboard/documents/sales/products/suppliers. | Loading is a major perceived-performance system. |
| Reduced motion | No centralized reduced-motion strategy found. | Accessibility gap; translate/shimmer/loops may remain active. | Add `MotionConfig`/`ReducedMotion` helpers using `MediaQuery.disableAnimations` and/or platform accessibility flags. | Required for native-feeling mobile quality. |

## Screen-by-Screen Motion Map

| Screen / flow | Current motion patterns | Missing or weak motion | Recommended direction |
|---|---|---|---|
| Splash / bootstrap | Not fully audited in visible surface; app starts through router/auth providers. | No documented bootstrap transition policy. | Keep bootstrap minimal: stable splash, no decorative logo animation unless native splash already handles it. |
| Auth sign-in | Button loading uses spinner; checkbox has 150ms animation. | Loading button can jump; no shared pressable. | Stable-width button state switch, 120ms press feedback, no page flourish. |
| Registration flow | Multiple `flutter_animate` fades and slides, long stagger delays, progress bar animation, password strength animations including elastic. | Too slow/playful for serious multitenant SaaS. | Keep rare onboarding polish but reduce durations/delays, remove elastic, use standardized fade-slide. |
| Main shell | No tab page transitions, floating nav animates active icon background. | Indicator lacks spatial movement. | Immediate route switch + 180-220ms moving indicator/icon scale. |
| Dashboard / Home | RefreshIndicator, chart draw, chart skeleton, period selector press, dynamic header fades. | No skeleton-to-content section transition; period selector lacks moving indicator; chart draw may repeat too long. | First-load section fade-slide, chart draw 360-450ms on first/period change, period pill slides. |
| Documents | Shimmer cards, processing shimmer/spinner/dots, upload progress bar, bottom sheets. | Too many loading loops; status changes are not stable animated state switches. | Shared skeleton, status switcher, thumbnail fade, optimistic insert animation, unified sheet route. |
| Scanner / upload | FAB press, scanner sheet default slide, row press scale, upload calls existing services. | Sheet rows do not enter with polish; upload state not a cohesive motion flow. | 260ms sheet, row stagger max 120ms, stable upload button states, optimistic document insert. |
| Expenses | Progress bars animate width 600ms; loading skeletons. | Width animation too long; no shared tokens. | 220-300ms first-reveal bars via tokens; no repeated rebuild animation. |
| Products | Skeleton grid, detail loading spinners/skeletons. | Product analytics lacks chart/status transitions. | Product chart draw once, anomaly badge switcher, section fade-slide. |
| Suppliers | Skeletons and static charts/sections. | Analytical changes feel abrupt. | Spend values animate when meaningful; first-load sections fade-slide; chart first draw. |
| Orders / Sales / Stock | Sales has custom skeletons, insight switcher, refresh rotation, legend chip animation. Orders/stock details need a pass in implementation. | Multiple skeleton implementations; some durations slow. | Shared skeletons, tokenized chip/switcher durations, no decorative loops. |

## Before / After / Why

| Before | After | Why |
|---|---|---|
| Scattered hardcoded durations from 150ms to 600ms | Central `AppMotion` tokens: 80, 120, 180, 260, 320ms with aliases for old names | Prevents drift and makes the app feel like one product. |
| Active nav icon gets its own local `AnimatedContainer` | One moving active indicator plus icon scale 1.0 -> 1.04 and opacity changes | Gives spatial continuity while keeping route changes immediate. |
| FAB has custom press code | `AppPressable` with scale 0.97/0.98, 100-140ms, optional haptic for primary scanner action | Applies the same tactile response to all premium tappable elements. |
| Scanner sheet uses default bottom sheet transition only | 260ms bottom-up sheet route, 160ms barrier fade, tiny row stagger capped at 120ms | Preserves spatial consistency and makes the primary flow feel native. |
| Processing document card runs shimmer, spinner, and animated dots together | Stable status badge using `AnimatedStatusSwitcher`, one subtle loading affordance | Reduces noise and makes extraction status clearer. |
| Document list updates pop in from realtime | New/optimistic card fade-slides from top 180-220ms; existing rows do not reanimate | Confirms upload/realtime insertion without making the list restless. |
| Chart line draws for 600ms | Draw line only on first load/period change in 360-450ms | Keeps analytical polish without delaying routine dashboard use. |
| KPI amount swaps abruptly or via plain fade | `AnimatedValue` for meaningful financial changes; no animation during touch scrubbing | Financial changes feel premium but do not fight real-time interaction. |
| Period selector changes active chip in place | Sliding selection pill 180-220ms easeOutCubic | Feels closer to modern banking tab controls. |
| Expense progress bars animate 600ms | 220-300ms first-reveal progress animation | Faster and calmer for operational analytics. |
| Sales skeleton uses 1500ms custom pulse, dashboard uses another skeleton, documents use shimmer package | One shared skeleton primitive with pulse duration token and reduced-motion fallback | Loading states become cohesive and easier to tune. |
| Registration uses long delayed fades and elastic success animation | Shorter stagger capped around 240ms; scale/fade instead of elastic | Rare flow remains polished but matches serious fintech tone. |
| Spinner-only buttons | Stable-width `AnimatedSwitcher` button content: idle/saving/queued/done/failed | Improves perceived performance and prevents layout jump. |
| No centralized reduced-motion behavior | `MotionConfig` and helper APIs that collapse movement to opacity/color transitions | Accessibility and product quality. |

## Proposed Motion Design System

### Tokens

Target file: `lib/core/theme/app_motion.dart`

```dart
abstract class AppMotion {
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 180);
  static const Duration sheet = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 320);
  static const Duration skeletonPulse = Duration(milliseconds: 1200);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeInOut = Curves.easeInOutCubic;
  static const Curve sheetCurve = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutExpo;

  static const double pressScale = 0.98;
  static const double primaryPressScale = 0.97;
  static const double enterTranslateY = 8;

  // Backward-compatible aliases while migrating.
  static const Duration micro = instant;
  static const Duration standard = normal;
  static const Duration emphasised = sheet;
  static const Curve enter = easeOut;
  static const Curve press = easeOut;
}
```

Rules:

| Token | Use |
|---|---|
| `instant` 80ms | Micro feedback, very frequent state changes. |
| `fast` 120ms | Press/release, small fades, exits. |
| `normal` 180ms | Standard content enter, active chips, status switches. |
| `sheet` 260ms | Bottom sheets and meaningful spatial transitions. |
| `slow` 320ms | Rare page/detail transition only. |
| `skeletonPulse` 1200ms | Quiet loading pulse. |

### Shared motion components

Target folder: `lib/shared/motion/`

| File | Purpose | Implementation notes |
|---|---|---|
| `motion_config.dart` | Central access to reduced-motion decisions and token helpers. | Expose `MotionConfig.of(context)` or static helpers using `MediaQuery`. |
| `reduced_motion.dart` | Small helpers for duration/offset collapse. | `duration(context, normal)`, `offset(context, dy)`, `shouldReduce(context)`. |
| `app_pressable.dart` | Consistent press feedback for tappable UI. | `GestureDetector` or `Listener` + `AnimatedScale`; 0.97/0.98; no bounce; optional haptic. |
| `fade_slide_in.dart` | Page section entrance. | `FadeTransition` + `SlideTransition`, 8px Y, 180-240ms, reduced-motion falls back to fade only. |
| `staggered_list.dart` | Bounded list entrance. | 25-40ms per item, cap total delay at 180ms. Do not animate old realtime rows. |
| `animated_value.dart` | Financial value transitions. | Animate only meaningful changes; tabular figures; disable for frequent realtime scrubbing. |
| `animated_status_switcher.dart` | Status badges and button states. | `AnimatedSwitcher`, fade + scale 0.98 -> 1.0, 160-200ms, stable layout. |

## Files to Create or Change

| Phase | Files |
|---|---|
| Phase 2 - Motion system | `lib/core/theme/app_motion.dart`, `lib/shared/motion/motion_config.dart`, `lib/shared/motion/reduced_motion.dart`, `lib/shared/motion/app_pressable.dart`, `lib/shared/motion/fade_slide_in.dart`, `lib/shared/motion/staggered_list.dart`, `lib/shared/motion/animated_value.dart`, `lib/shared/motion/animated_status_switcher.dart`, barrel export file if project pattern supports it. |
| Phase 3 - Core shell | `lib/shared/ui/app_bottom_nav.dart`, `lib/shared/ui/premium_fab.dart`, `lib/shared/ui/scanner_action_sheet.dart`, `lib/shared/ui/app_scaffold.dart`, `lib/shared/ui/bottom_action_sheet.dart`, `lib/core/router/app_router.dart` if route transition cleanup is accepted. |
| Phase 4 - Dashboard | `lib/features/dashboard/presentation/screens/dashboard_screen.dart`, `lib/widgets/expenses/expense_line_chart.dart`, `lib/widgets/expenses/chart_period_selector.dart`, `lib/widgets/expenses/chart_dynamic_header.dart`, `lib/widgets/expenses/chart_kpi_cards.dart`, `lib/features/dashboard/presentation/widgets/intelligence_section.dart`. |
| Phase 5 - Scanner flow | `lib/shared/ui/scanner_action_sheet.dart`, `lib/features/documents/presentation/screens/documents_screen.dart`, `lib/features/expenses/presentation/screens/expense_form_screen.dart`, existing camera/upload service call sites only for UI state hooks if needed. |
| Phase 6 - Documents/products/suppliers | `lib/features/documents/presentation/widgets/document_card.dart`, `lib/features/documents/presentation/widgets/document_detail_sheet.dart`, `lib/features/products/presentation/screens/product_list_screen.dart`, `lib/features/products/presentation/screens/product_detail_screen.dart`, `lib/features/providers/presentation/screens/providers_screen.dart`, `lib/features/providers/presentation/screens/supplier_detail_screen.dart`, sales widgets using custom skeletons. |
| Phase 7 - QA | No business logic files. Test with analyzer, emulator/device, reduced-motion setting, debug/profile performance. |

## Implementation Phases

### Phase 1 - Audit and map

Status: this document.

Deliverables:

| Deliverable | Status |
|---|---|
| Animation inventory | Complete |
| Screen-by-screen map | Complete |
| Before/After/Why recommendations | Complete |
| Risk areas | Complete |
| No runtime code changed | Complete |

### Phase 2 - Motion design system

Implement shared tokens and wrappers. Keep compatibility aliases in `AppMotion` so existing code does not break. Add reduced-motion helpers before migrating screens.

### Phase 3 - Core shell polish

Implement moving nav indicator, migrate FAB/sheet rows to `AppPressable`, unify bottom sheet timing, keep tab switching immediate.

### Phase 4 - Dashboard polish

Add section fade-slide only after first load, refine chart draw duration, slide period selector indicator, add meaningful `AnimatedValue` for financial totals.

### Phase 5 - Scanner flow polish

Refine FAB -> sheet -> camera/upload -> form -> queued document flow. Add stable upload button states and optimistic document card insertion. Do not touch extraction internals.

### Phase 6 - Documents/products/suppliers polish

Replace noisy document processing loops with status switchers, fade thumbnails from skeleton, add chart/anomaly transitions to product and supplier analytics, unify sales skeletons.

### Phase 7 - Reduced motion and performance QA

Verify reduced motion, list performance, no jank in documents, no repeated chart animation on rebuild, no backend/realtime regressions.

## Animations to Remove or Reduce

| Area | Remove/reduce | Replacement |
|---|---|---|
| Password strength success | `Curves.elasticOut` scale | 160-180ms fade/scale with easeOutCubic. |
| Long registration stagger | Delays up to 600ms | Cap total entrance delay around 240ms. |
| Processing document card | Spinner + shimmer + animated dots combination | One status badge switcher plus one subtle progress affordance. |
| 600ms analytics progress bars | Long width animation | 220-300ms first-reveal only. |
| Multiple skeleton styles | Package shimmer/custom pulse/flutter_animate shimmer all mixed | One shared skeleton primitive. |
| Refresh rotation 500ms | Slow full rotation | 240-300ms or stable progress state. |

## Performance Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| One `AnimationController` per document processing card | Long realtime lists can create many ticking controllers. | Use shared/implicit status switcher or one low-cost visual state per card. |
| Shimmer across many cards | Animated gradients can be more expensive than opacity pulse. | Prefer `SkeletonBlock` pulse for long lists. |
| Animating width in many rows | Width/layout animation triggers layout work. | Use sparingly on first reveal; consider `FractionallySizedBox`/clip/transform where possible. |
| Reanimating on every provider rebuild | Realtime data can make UI restless and costly. | Track first load and meaningful changes; do not animate unchanged rows. |
| Blur/glass effects | Expensive on mobile GPUs. | Avoid as a motion primitive; use opacity/transform. |
| Route transitions fighting nav indicator | User perceives double animation. | Keep tab page transitions instant; animate only nav indicator. |

## Reduced Motion Strategy

| Motion type | Normal behavior | Reduced-motion behavior |
|---|---|---|
| Press feedback | Scale 0.97/0.98 for 100-140ms | Keep very subtle scale or instant opacity/color feedback. |
| Section entrance | Fade + translateY 8px | Fade only, same or shorter duration. |
| Bottom sheet | Slide up 260ms + barrier fade | Short barrier fade; reduce/disable slide distance. |
| Staggered lists | 25-40ms item delay capped | No stagger; items appear together with fade or instantly. |
| Chart draw | 360-450ms line draw | Show final line immediately or short fade. |
| Skeleton pulse | 1200ms pulse | Static skeleton block. |
| Status switcher | Fade + scale 0.98 -> 1.0 | Fade only. |

Flutter detection should prefer `MediaQuery.maybeOf(context)?.disableAnimations == true`, with a fallback helper that can later include platform accessibility signals.

## QA Checklist

| Check | Expected result |
|---|---|
| `flutter analyze --no-pub` | No new analyzer errors. |
| Dashboard first load | Skeletons appear, content settles once, chart does not redraw on every rebuild. |
| Bottom nav tap | Route changes immediately; indicator settles in 180-220ms. |
| FAB tap | Press feedback is instant; sheet rises smoothly; scanner action remains direct. |
| Upload flow | Button/list states are stable; extraction pipeline still works. |
| Documents realtime update | New document appears confidently; existing list does not reanimate. |
| Status change | Queued/extracting/completed/failed transitions do not jump layout. |
| Product/supplier detail | Charts animate on first render only; skeletons are consistent. |
| Reduced motion enabled | Large movement and shimmer are reduced; core state feedback remains clear. |
| Profile mode performance | No obvious dropped frames on Android emulator or physical device. |

## Non-Negotiables

| Constraint | Rule |
|---|---|
| Backend | Do not rewrite backend logic. |
| Supabase | Do not change Supabase providers, RLS, tenant filtering, or realtime semantics for motion work. |
| Extraction | Do not alter document extraction, product matching, supplier matching, category detection, anomaly detection, or OpenRouter prompts for this work. |
| Motion | No bounce/elastic for fintech UI. No random animation. No long decorative delays. No layout jank. |
