import 'package:flutter/material.dart';

import 'package:hospi_dash/core/theme/app_elevation.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/shared/ui/app_scaffold.dart';

/// A single action in a [BottomActionSheet]. Icon optional; the leading icon
/// stays mono-ink (no coloured backgrounds, no purple).
class SheetAction {
  const SheetAction({
    required this.label,
    required this.onTap,
    this.icon,
    this.subtitle,
    this.destructive = false,
  });

  final String label;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback onTap;
  final bool destructive;
}

/// Editorial action sheet. Shown via [showAppSheet]. Hairline-separated
/// rows, no per-row card chrome, ink-tinted destructive variant.
class BottomActionSheet extends StatelessWidget {
  const BottomActionSheet({
    super.key,
    this.title,
    required this.actions,
  });

  final String? title;
  final List<SheetAction> actions;

  static Future<void> show(
    BuildContext context, {
    String? title,
    required List<SheetAction> actions,
  }) {
    return showAppSheet(
      context: context,
      builder: (_) => BottomActionSheet(title: title, actions: actions),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: Text(
              title!,
              style: EditorialTypography.titleMedium.copyWith(
                color: EditorialColors.onSurface,
              ),
            ),
          ),
        for (int i = 0; i < actions.length; i++)
          _SheetActionRow(
            action: actions[i],
            dividerBelow: i != actions.length - 1,
          ),
      ],
    );
  }
}

class _SheetActionRow extends StatelessWidget {
  const _SheetActionRow({required this.action, required this.dividerBelow});
  final SheetAction action;
  final bool dividerBelow;

  @override
  Widget build(BuildContext context) {
    final ink = action.destructive
        ? EditorialColors.error
        : EditorialColors.onSurface;

    final row = InkWell(
      onTap: () {
        Navigator.of(context).maybePop();
        action.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          children: [
            if (action.icon != null) ...[
              Icon(action.icon, size: 20, color: ink),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action.label,
                    style: EditorialTypography.bodyLarge.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (action.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle!,
                      style: EditorialTypography.bodySmall.copyWith(
                        color: EditorialColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: EditorialColors.onSurfaceVariant),
          ],
        ),
      ),
    );

    if (!dividerBelow) return row;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: AppElevation.hairlineSide),
      ),
      child: row,
    );
  }
}

/// Inline preview of the expense form to be opened on a full page. Mounted
/// inside the upload flow so users get a glance of the next screen before
/// committing. Strictly does NOT include supplier, date, or total fields —
/// those are derived by the extraction pipeline.
class ExpenseFormPagePreview extends StatelessWidget {
  const ExpenseFormPagePreview({
    super.key,
    this.fields = const <String>[
      'Category',
      'Notes',
      'Cost center',
      'Attachments',
    ],
    required this.onOpen,
  });

  final List<String> fields;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLow,
        border: AppElevation.hairlineBorder,
        borderRadius: BorderRadius.circular(EditorialRadius.standard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'next: expense details'.toLowerCase(),
            style: EditorialTypography.labelSmall.copyWith(
              color: EditorialColors.onSurfaceVariant,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You will complete a short form for this expense.',
            style: EditorialTypography.bodyMedium.copyWith(
              color: EditorialColors.onSurface,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in fields)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: EditorialColors.surface,
                    border: AppElevation.hairlineBorder,
                    borderRadius:
                        BorderRadius.circular(EditorialRadius.xs),
                  ),
                  child: Text(
                    f,
                    style: EditorialTypography.labelSmall.copyWith(
                      color: EditorialColors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: onOpen,
              child: const Text('Open form'),
            ),
          ),
        ],
      ),
    );
  }
}
