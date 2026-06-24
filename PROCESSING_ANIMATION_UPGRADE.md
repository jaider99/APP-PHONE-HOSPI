# Processing Animation Upgrade

## Scope

This was a UI-only upgrade for the document processing state shown while a document is in `DocumentStatus.processing`.

Analyzed files:

- `lib/features/documents/presentation/widgets/document_card.dart`
- `lib/features/documents/presentation/widgets/document_detail_sheet.dart`
- `lib/features/documents/presentation/widgets/document_edit_sheet.dart`
- `lib/features/documents/presentation/widgets/document_stats_row.dart`

Only the document card processing indicator was changed. The detail sheet loading indicator, edit sheet save spinner, and stats row were intentionally left untouched because they are unrelated to document extraction progress.

## What Changed

- Added `lib/shared/animations/ai_processing_indicator.dart`.
- Replaced the old 12 px `CircularProgressIndicator` inside `_ProcessingCard` with `AiProcessingIndicator`.
- Preserved the existing animated `AI extracting...` label and dot cycle.
- Preserved the existing shimmer thumbnail, card shell, tap behavior, filename rendering, and status-based card switching.

The new indicator uses:

- A 2000 ms rotating `Icons.sync_rounded` glyph.
- A soft 1800 ms opacity breath from 0.8 to 1.0.
- A compact rounded `#F1F1F1` surface with a very soft `0x0A000000` shadow.
- `RepaintBoundary` so repeated animation repaint work stays local to the indicator.

## Why This Is UI-Only

No document lifecycle code was changed.

Unchanged areas:

- Supabase queries
- Supabase realtime subscriptions
- Storage upload flow
- Providers
- Extraction services
- OpenRouter AI calls
- Edge Functions
- PDF rendering
- Document status transitions
- `company_id` or tenant-isolation logic

The animation still appears only because `DocumentCard` switches on `DocumentStatus.processing`. It disappears automatically when the existing provider/realtime flow delivers a completed, flagged, or failed status.

## Regression Checks

Expected behavior after this change:

1. Upload an image receipt: the document appears immediately with the premium AI processing animation.
2. Upload a PDF: the same processing animation appears without blocking the UI.
3. When extraction completes, the processing card is replaced by the completed or flagged card.
4. Multiple processing documents can animate at the same time because each indicator owns and disposes its local controllers.
5. Navigating away and back should not produce animation controller errors because `AiProcessingIndicator.dispose` disposes both controllers.

## Validation

Commands run:

- `dart format lib\shared\animations\ai_processing_indicator.dart lib\features\documents\presentation\widgets\document_card.dart`
- `dart analyze lib\shared\animations\ai_processing_indicator.dart lib\features\documents\presentation\widgets\document_card.dart`
- `flutter analyze`

Results:

- `get_errors` reported no errors in the new animation widget or document card.
- Focused analyzer found no diagnostics in `ai_processing_indicator.dart`.
- Focused analyzer reported only pre-existing info-level style diagnostics in `document_card.dart`.
- Full `flutter analyze` reported `636 issues found`, matching the existing project-wide analyzer debt pattern and not indicating a new error in the processing animation widget.