import 'package:flutter/material.dart';

import 'package:hospi_dash/core/theme/app_elevation.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// Editorial empty state. Centered serif title, plain body, optional action
/// button. No oversized icon disc, no illustration placeholder.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 28, color: EditorialColors.onSurfaceVariant),
              const SizedBox(height: 16),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: EditorialTypography.headlineSmall.copyWith(
                color: EditorialColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: EditorialTypography.bodyMedium.copyWith(
                  color: EditorialColors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Editorial error state. Same anatomy as [AppEmptyState], tuned for retries.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.title = 'Something went wrong',
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.error_outline,
      title: title,
      message: message,
      actionLabel: onRetry == null ? null : retryLabel,
      onAction: onRetry,
    );
  }
}

/// Inline hint. Replaces the purple `AiInsightBanner`. Flat surface,
/// hairline border, small caps eyebrow, optional dismiss.
class InlineHint extends StatelessWidget {
  const InlineHint({
    super.key,
    required this.message,
    this.eyebrow,
    this.onDismiss,
    this.action,
  });

  final String message;
  final String? eyebrow;
  final VoidCallback? onDismiss;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLow,
        border: AppElevation.hairlineBorder,
        borderRadius: BorderRadius.circular(EditorialRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  message,
                  style: EditorialTypography.bodyMedium.copyWith(
                    color: EditorialColors.onSurface,
                    height: 1.45,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 8),
                  action!,
                ],
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              color: EditorialColors.onSurfaceVariant,
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}
