import 'package:flutter/material.dart';

import 'package:hospi_dash/core/theme/app_elevation.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/shared/ui/badges.dart';
import 'package:hospi_dash/shared/ui/metric_text.dart';

/// Editorial list row. Leading slot (avatar / icon / nothing), primary +
/// secondary text, optional trailing metric column, and a hairline divider
/// underneath. Used for documents, suppliers, products, line items.
class DataRowItem extends StatelessWidget {
  const DataRowItem({
    super.key,
    this.leading,
    required this.primary,
    this.secondary,
    this.trailing,
    this.onTap,
    this.dividerBelow = true,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 14),
  });

  final Widget? leading;
  final String primary;
  final String? secondary;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dividerBelow;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  primary,
                  style: EditorialTypography.bodyLarge.copyWith(
                    color: EditorialColors.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (secondary != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondary!,
                    style: EditorialTypography.bodySmall.copyWith(
                      color: EditorialColors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );

    final tappable = onTap == null
        ? row
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              highlightColor: EditorialColors.surfaceContainerLow,
              splashColor: EditorialColors.surfaceContainer,
              child: row,
            ),
          );

    if (!dividerBelow) return tappable;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: AppElevation.hairlineSide),
      ),
      child: tappable,
    );
  }
}

/// Document list row. Replaces the three legacy DocumentCard variants with
/// one flat hairline-separated row: status pill, supplier + reference,
/// trailing amount + relative date.
class DocumentRow extends StatelessWidget {
  const DocumentRow({
    super.key,
    required this.supplier,
    required this.reference,
    required this.status,
    this.amount,
    this.relativeDate,
    this.onTap,
  });

  final String supplier;
  final String reference;
  final DocumentLifecycle status;
  final num? amount;
  final String? relativeDate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DataRowItem(
      onTap: onTap,
      leading: DocumentStatusPill(status: status),
      primary: supplier,
      secondary: reference,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (amount != null)
            FinancialValue(
              amount: amount!,
              size: MetricSize.small,
            ),
          if (relativeDate != null) ...[
            const SizedBox(height: 2),
            Text(
              relativeDate!,
              style: EditorialTypography.labelSmall.copyWith(
                color: EditorialColors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
