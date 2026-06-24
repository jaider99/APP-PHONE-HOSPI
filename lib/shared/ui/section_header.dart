import 'package:flutter/material.dart';

import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// Editorial section header. Eyebrow label (small caps, tracked), bold
/// Fraunces title, optional trailing action. No icon, no card chrome.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 24, 20, 12),
  });

  final String title;
  final String? eyebrow;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toLowerCase(),
                    style: EditorialTypography.labelSmall.copyWith(
                      color: EditorialColors.onSurfaceVariant,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  title,
                  style: EditorialTypography.headlineSmall.copyWith(
                    color: EditorialColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            DefaultTextStyle.merge(
              style: EditorialTypography.labelMedium.copyWith(
                color: EditorialColors.accent,
                fontWeight: FontWeight.w500,
              ),
              child: trailing!,
            ),
        ],
      ),
    );
  }
}
