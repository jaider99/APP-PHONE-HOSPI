import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/app_colors.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/core/theme/app_radius.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/data/models/provider.dart';
import 'package:hospi_dash/shared/ui/ui.dart';
import 'package:intl/intl.dart';

/// Top Providers section showing spending by provider
class TopProvidersSection extends StatelessWidget {
  const TopProvidersSection({
    super.key,
    required this.providers,
    this.onViewAll,
  });

  final List<ProviderSpending> providers;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            eyebrow: 'suppliers',
            title: 'Top providers',
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (providers.isEmpty)
                  const _EmptyState()
                else
                  ...List.generate(providers.length, (i) {
                    final isLast = i == providers.length - 1;
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: isLast ? 0 : AppSpacing.md,
                      ),
                      child: _ProviderTile(provider: providers[i]),
                    );
                  }),
                if (providers.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: EditorialColors.hairline,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onViewAll,
                      child: const Text('View all spending'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual provider tile
class _ProviderTile extends StatelessWidget {
  const _ProviderTile({required this.provider});

  final ProviderSpending provider;

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(
      locale: 'de_DE',
      symbol: '€ ',
      decimalDigits: 0,
    );

    return Row(
      children: [
        // Avatar with initials
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: AppRadius.borderRadiusMd,
          ),
          alignment: Alignment.center,
          child: Text(
            provider.initials,
            style: EditorialTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
        AppSpacing.horizontalMd,
        
        // Name and category
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.name,
                style: EditorialTypography.bodyMedium.copyWith(
                  fontSize: 15,
                  color: AppColors.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (provider.category != null) ...[
                const SizedBox(height: 2),
                Text(
                  provider.category!,
                  style: EditorialTypography.bodySmall.copyWith(
                    fontSize: 13,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
        
        // Amount
        Text(
          formatter.format(provider.totalSpent),
          style: EditorialTypography.titleSmall.copyWith(
            fontSize: 16,
            color: AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Empty state when no providers
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.business_outlined,
              size: 48,
              color: AppColors.outline.withOpacity(0.5),
            ),
            AppSpacing.verticalMd,
            Text(
              'No provider data yet',
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
