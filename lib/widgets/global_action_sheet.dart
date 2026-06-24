import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GLOBAL ACTION SHEET
//
// Trade Republic–inspired draggable bottom sheet.
// Swipe down to dismiss. Used from Dashboard, Documents, Products, etc.
// ─────────────────────────────────────────────────────────────────────────────

/// Defines one action item in the [GlobalActionSheet].
class ActionSheetItem {
  const ActionSheetItem({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

/// Shows a Trade Republic–style draggable bottom sheet.
///
/// Usage:
/// ```dart
/// GlobalActionSheet.show(context, items: [...]);
/// ```
class GlobalActionSheet {
  GlobalActionSheet._();

  static void show(
    BuildContext context, {
    required List<ActionSheetItem> items,
    String? title,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.2,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => _ActionSheetContent(
          scrollController: scrollController,
          items: items,
          title: title,
        ),
      ),
    );
  }
}

// ─── Content widget ───────────────────────────────────────────────────────────

class _ActionSheetContent extends StatelessWidget {
  const _ActionSheetContent({
    required this.scrollController,
    required this.items,
    this.title,
  });

  final ScrollController scrollController;
  final List<ActionSheetItem> items;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: EditorialColors.onSurface.withOpacity(0.08),
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        children: [
          // ── Handle ──────────────────────────────────────────────────────
          Center(
            child: Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: EditorialColors.outlineVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // ── Optional title ───────────────────────────────────────────────
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Text(
                title!,
                style: EditorialTypography.labelSmall.copyWith(
                  color: EditorialColors.onSurfaceVariant,
                  letterSpacing: 1.5,
                  fontSize: 11,
                ),
              ),
            ),

          // ── Action items ─────────────────────────────────────────────────
          ...items.map((item) => _ActionTile(item: item)),

          // ── Bottom safe area ─────────────────────────────────────────────
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Action tile ──────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.item});

  final ActionSheetItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: EditorialColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                item.icon,
                color: EditorialColors.onSurface,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              item.label,
              style: EditorialTypography.bodyLarge.copyWith(
                color: EditorialColors.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: EditorialColors.onSurfaceVariant.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }
}
