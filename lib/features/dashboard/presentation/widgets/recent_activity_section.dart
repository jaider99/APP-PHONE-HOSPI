import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/app_colors.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/core/theme/app_radius.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/data/models/activity.dart';
import 'package:hospi_dash/shared/ui/ui.dart';
import 'package:intl/intl.dart';

/// Recent Activity section combining sales and documents
class RecentActivitySection extends StatelessWidget {
  const RecentActivitySection({
    super.key,
    required this.activities,
    this.onViewHistory,
  });

  final List<Activity> activities;
  final VoidCallback? onViewHistory;

  @override
  Widget build(BuildContext context) {
    final shown = activities.take(5).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            eyebrow: 'recent',
            title: 'Activity',
            trailing: onViewHistory == null
                ? null
                : GestureDetector(
                    onTap: onViewHistory,
                    child: Text(
                      'View history',
                      style: EditorialTypography.labelMedium.copyWith(
                        color: EditorialColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (shown.isEmpty)
            const AppCard(child: _EmptyState())
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: List.generate(shown.length, (i) {
                  final isLast = i == shown.length - 1;
                  return _ActivityTile(
                    activity: shown[i],
                    showDivider: !isLast,
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

/// Individual activity tile
class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity, this.showDivider = false});

  final Activity activity;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(
      locale: 'de_DE',
      symbol: '€ ',
      decimalDigits: 2,
    );

    // Icon and color based on activity type
    IconData icon;
    Color iconBgColor;
    Color iconColor;
    
    switch (activity.type) {
      case ActivityType.sale:
        icon = Icons.check_circle_outline;
        iconBgColor = AppColors.successLight;
        iconColor = AppColors.success;
        break;
      case ActivityType.document:
        icon = Icons.shopping_cart_outlined;
        iconBgColor = AppColors.surfaceContainerLow;
        iconColor = AppColors.primary;
        break;
      case ActivityType.order:
        icon = Icons.inventory_2_outlined;
        iconBgColor = AppColors.infoLight;
        iconColor = AppColors.info;
        break;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(
                bottom: BorderSide(
                  color: EditorialColors.hairline,
                  width: 1,
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: AppRadius.borderRadiusMd,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 22,
              color: iconColor,
            ),
          ),
          AppSpacing.horizontalMd,
          
          // Title and subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  style: EditorialTypography.bodyMedium.copyWith(
                    fontSize: 15,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  activity.subtitle,
                  style: EditorialTypography.bodySmall.copyWith(
                    fontSize: 13,
                    color: AppColors.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          // Amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${activity.isPositive ? '+' : '-'}${formatter.format(activity.amount)}',
                style: EditorialTypography.titleSmall.copyWith(
                  fontSize: 15,
                  color: activity.isPositive ? AppColors.success : AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatTimestamp(activity.timestamp),
                style: EditorialTypography.bodySmall.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    
    if (diff.inDays == 0) {
      return 'Today, ${DateFormat.Hm().format(timestamp)}';
    } else if (diff.inDays == 1) {
      return 'Yesterday, ${DateFormat.Hm().format(timestamp)}';
    } else {
      return DateFormat('MMM d').format(timestamp);
    }
  }
}

/// Empty state when no activity
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.history_outlined,
              size: 48,
              color: AppColors.outline.withOpacity(0.5),
            ),
            AppSpacing.verticalMd,
            Text(
              'No recent activity',
              style: EditorialTypography.bodyMedium.copyWith(
                color: AppColors.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
