import 'package:flutter/material.dart';

import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// Semantic tone for badges and chips.
enum BadgeTone { neutral, accent, success, warning, error, info }

class _ToneInk {
  const _ToneInk(this.ink, this.surface);
  final Color ink;
  final Color surface;
}

_ToneInk _inkFor(BadgeTone tone) {
  switch (tone) {
    case BadgeTone.neutral:
      return _ToneInk(
        EditorialColors.onSurfaceVariant,
        EditorialColors.surfaceContainer,
      );
    case BadgeTone.accent:
      return _ToneInk(EditorialColors.accent, EditorialColors.accentContainer);
    case BadgeTone.success:
      return _ToneInk(EditorialColors.success, EditorialColors.successContainer);
    case BadgeTone.warning:
      return _ToneInk(
        const Color(0xFF6B5320),
        EditorialColors.warningLight,
      );
    case BadgeTone.error:
      return _ToneInk(EditorialColors.error, EditorialColors.errorContainer);
    case BadgeTone.info:
      return _ToneInk(
        const Color(0xFF2F4566),
        EditorialColors.infoLight,
      );
  }
}

/// Compact status badge. Flat, single hairline border, optional leading dot.
/// No drop shadow, no pill stretch.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.tone = BadgeTone.neutral,
    this.dot = false,
  });

  final String label;
  final BadgeTone tone;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final t = _inkFor(tone);
    return Container(
      padding: EdgeInsets.fromLTRB(dot ? 8 : 10, 4, 10, 4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(EditorialRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: t.ink,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: EditorialTypography.labelSmall.copyWith(
              color: t.ink,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Document lifecycle status. Maps the existing extraction pipeline states
/// onto editorial tones. Single neutral dot for "processing" — no purple.
enum DocumentLifecycle {
  uploading,
  processing,
  needsReview,
  ready,
  failed,
  archived,
}

class DocumentStatusPill extends StatelessWidget {
  const DocumentStatusPill({super.key, required this.status});

  final DocumentLifecycle status;

  ({String label, BadgeTone tone, bool dot}) _spec() {
    switch (status) {
      case DocumentLifecycle.uploading:
        return (label: 'Uploading', tone: BadgeTone.neutral, dot: true);
      case DocumentLifecycle.processing:
        return (label: 'Processing', tone: BadgeTone.neutral, dot: true);
      case DocumentLifecycle.needsReview:
        return (label: 'Needs review', tone: BadgeTone.warning, dot: false);
      case DocumentLifecycle.ready:
        return (label: 'Ready', tone: BadgeTone.success, dot: false);
      case DocumentLifecycle.failed:
        return (label: 'Failed', tone: BadgeTone.error, dot: false);
      case DocumentLifecycle.archived:
        return (label: 'Archived', tone: BadgeTone.neutral, dot: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _spec();
    return StatusBadge(label: s.label, tone: s.tone, dot: s.dot);
  }
}

/// Compact category chip. Tappable, hairline border, no fill until selected.
class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final ink = selected
        ? EditorialColors.onPrimary
        : EditorialColors.onSurface;
    final fill = selected
        ? EditorialColors.primary
        : EditorialColors.surface;
    final border = selected
        ? EditorialColors.primary
        : EditorialColors.outlineVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(EditorialRadius.full),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(EditorialRadius.full),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                IconTheme(
                  data: IconThemeData(size: 14, color: ink),
                  child: leading!,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: EditorialTypography.labelMedium.copyWith(
                  color: ink,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
