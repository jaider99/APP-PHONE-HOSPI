# Document Screen UI Redesign Analysis

## 1. Current Widget Tree

Primary screen:
- `lib/features/documents/presentation/screens/documents_screen.dart`
- `DocumentsScreen extends ConsumerStatefulWidget`

Current tree inside `AppScaffold`:
1. `AppTopBar(eyebrow: 'inbox', title: 'Documents')`
2. `FloatingActionHub.documents(...)`
3. `CustomScrollView`
4. optional review queue banner using `documentMergeReviewCountProvider`
5. `DocumentStatsRow`
6. `FilterChipRow`
7. optional upload progress `LinearProgressIndicator`
8. `documentsProvider.when(...)`
   - `SliverList` of `DocumentCard`
   - `DocumentCardShimmer` loading state
   - `AppEmptyState` empty state
   - `ErrorState` retry state

Document open path:
- `DocumentCard(onTap: () => _openDocument(doc))`
- `_openDocument()` precaches preview if possible
- opens `DocumentDetailSheet.show(context, doc.id)`

Current card implementation:
- `lib/features/documents/presentation/widgets/document_card.dart`
- three status-specific presentations:
  - `_ProcessingCard`
  - `_CompletedCard`
  - `_FlaggedCard`
- shared shell: `_CardShell`

Current filters:
- `lib/features/documents/presentation/widgets/filter_chip_row.dart`
- uses `documentFilterProvider`
- current options:
  - All
  - Invoices
  - Delivery notes
  - Expenses
  - Flagged

## 2. Current Data Flow

UI-only redesign must preserve this data path:
- `documentsProvider` in `lib/providers/documents_provider.dart`
- provider already depends on:
  - `documentsRealtimeListProvider`
  - `documentFilterProvider`
  - active `companyIdProvider`
- realtime list is already tenant-filtered by `company_id`
- fallback fetch is also tenant-filtered by `company_id`
- document detail navigation already works through `DocumentDetailSheet`
- upload progress comes from `uploadProgressProvider`
- review queue hint comes from `documentMergeReviewCountProvider`

Important: current filtering is provider-driven and tenant-safe. Redesign must not bypass it.

## 3. Current Actions Preserved

These must remain untouched:
- Tap document card -> open existing `DocumentDetailSheet`
- Upload via existing `FloatingActionHub.documents`
- Photo capture via `CameraUploadService.handleCameraCapture`
- Upload from gallery/file via `CameraUploadService`
- Manual entry placeholder snackbar
- Review queue banner action -> `AppRoutes.documentReviewQueue`
- Realtime updates from `documentsRealtimeListProvider`
- Upload progress bar from `uploadProgressProvider`
- Existing delete/edit/detail actions inside detail sheet

## 4. Files To Modify

Safest UI-only targets:
- `lib/features/documents/presentation/screens/documents_screen.dart`
- `lib/features/documents/presentation/widgets/document_card.dart`
- `lib/features/documents/presentation/widgets/filter_chip_row.dart`

Possible new UI-only file(s):
- `lib/features/documents/presentation/widgets/document_search_bar.dart`
- or keep search UI local in `documents_screen.dart`

Possible provider addition only if required for UI search state:
- `lib/providers/documents_provider.dart`
  - only for a lightweight search query `StateProvider` or derived filtered provider
  - no backend/query contract changes

## 5. Files NOT Touched

Do not touch:
- `lib/features/documents/presentation/widgets/document_detail_sheet.dart`
- `lib/features/documents/presentation/widgets/document_edit_sheet.dart`
- `lib/features/documents/data/services/*`
- upload / delete / duplicate / extraction services
- Supabase migrations
- Supabase functions
- OpenRouter / VLM logic
- RLS / company isolation logic
- `FloatingActionHub` / FAB behavior
- document processing states and backend transitions

## 6. Current UI Problems Confirmed

From current implementation:
- `DocumentCard` still uses old `AppColors` and small radii (`14`) rather than the newer Digital Atelier editorial tokens
- `_CardShell` uses `Border.all(...)`, which conflicts with the new no-hard-borders direction
- amount/date/status alignment is driven by narrow row layouts that can compress content on smaller widths
- supplier / title / subtitle text rely on a simple row that can crowd the trailing amount
- filter row is compact and limited; visually closer to old category chips than premium pills
- there is no search UI on the screen
- loading state is functional but visually basic

## 7. Safest Search Strategy

User requested search across:
- supplier name
- document number
- filename
- document type

Given the current architecture and the restriction against backend/query changes, the safest implementation is:
- add a local debounced search query state in UI
- apply the search as a derived in-memory filter on the already tenant-scoped `documentsProvider` result

Why this is safe:
- `documentsProvider` is already company-scoped and realtime-backed
- no Supabase query changes required
- no risk to extraction/upload/detail logic
- no cross-tenant leakage because the input set is already tenant-filtered

This does mean local filtering, but only on the already tenant-isolated active-company dataset, which is safe and consistent with the current screen architecture.

## 8. UI Implementation Plan

1. Redesign `DocumentsScreen` header area:
   - keep `AppTopBar`
   - add a large premium search pill below it
   - preserve review queue banner but visually soften it to match the screen

2. Add debounced search UI:
   - `TextEditingController`
   - `Timer`-based 300ms debounce in screen state
   - derived visible list from `documentsProvider` result
   - search matches supplier/title/document number/file name/document type labels

3. Redesign filter chips:
   - horizontal premium pills
   - black selected state, white/light gray unselected
   - add requested labels where they map safely to existing filters
   - keep provider-driven filter behavior

4. Redesign `DocumentCard`:
   - move to Digital Atelier tokens (`EditorialColors`, `EditorialTypography`, large radii, soft shadows)
   - remove hard borders
   - use stable responsive row structure:
     - icon block
     - expanded info column
     - fixed trailing amount column
   - ensure supplier/title/document number/date/status do not overflow
   - use `Expanded`, `Flexible`, `TextOverflow.ellipsis`, `maxLines: 1`

5. Preserve status-specific presentation:
   - processing -> premium AI extracting state using existing logic/icon/animation
   - completed -> premium clean card with amount always visible
   - flagged/failed -> premium warning card with soft container and no hard border

6. Improve loading/empty states:
   - keep shimmer approach, but restyle to premium cards
   - replace current empty message styling only, not behavior

7. Add subtle entrance motion:
   - fade + slight slide using existing Flutter primitives
   - keep durations 200-300ms

## 9. Validation Checklist

- Existing documents still render from `documentsProvider`
- Card tap still opens `DocumentDetailSheet`
- FAB and upload flows remain unchanged
- Realtime updates still refresh list UI
- Upload progress still displays
- Search matches supplier/document number/file name/document type
- Filter chips still drive existing `documentFilterProvider`
- No `RenderFlex overflow` at 360px width
- No backend/service/provider contract changes beyond optional UI search state
- No mock data introduced
- No Supabase query / RLS / company_id behavior changed
