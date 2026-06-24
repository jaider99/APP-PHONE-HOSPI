import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/theme/app_colors.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/dashboard/presentation/widgets/ethereal_card.dart';
import 'package:hospi_dash/features/dashboard/providers/intelligence_providers.dart';
import 'package:hospi_dash/services/intelligence_models.dart';
import 'package:hospi_dash/shared/ui/ui.dart';
import 'package:intl/intl.dart';

// ─── Section ──────────────────────────────────────────────────────────────────

/// Dashboard section that renders two intelligence cards side-by-side:
///   • Category spend breakdown (current month, ranked by spend)
///   • Top products by spend (current month)
class IntelligenceSection extends ConsumerWidget {
  const IntelligenceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            eyebrow: 'this month',
            title: 'Intelligence',
            trailing: GestureDetector(
              onTap: () => context.go(AppRoutes.expenses),
              child: Text(
                'Details',
                style: EditorialTypography.labelMedium.copyWith(
                  color: EditorialColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Category breakdown card ─────────────────────────────────────
          const _CategoryBreakdownCard(),
          AppSpacing.verticalMd,

          // ── Top products card ───────────────────────────────────────────
          const _TopProductsCard(),
        ],
      ),
    );
  }
}

// ─── Category breakdown ───────────────────────────────────────────────────────

class _CategoryBreakdownCard extends ConsumerWidget {
  const _CategoryBreakdownCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(categoryIntelligenceProvider);

    return EtherealCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spend by Category',
            style: EditorialTypography.labelLarge.copyWith(
              color: AppColors.outline,
              letterSpacing: 0.8,
            ),
          ),
          AppSpacing.verticalLg,
          state.when(
            data: (categories) {
              final active =
                  categories.where((c) => c.currentMonthSpent > 0).toList();
              if (active.isEmpty) {
                return const _EmptyHint(
                  icon: Icons.pie_chart_outline_rounded,
                  message: 'No categorised expenses this month.',
                );
              }
              final total =
                  active.fold(0.0, (sum, c) => sum + c.currentMonthSpent);
              return Column(
                children: active
                    .take(6)
                    .map((c) => _CategoryRow(category: c, total: total))
                    .toList(),
              );
            },
            loading: () => const _CardShimmer(),
            error: (_, __) => const _EmptyHint(
              icon: Icons.error_outline_rounded,
              message: 'Could not load categories.',
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.total,
  });

  final CategoryIntelligence category;
  final double total;

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? category.currentMonthSpent / total : 0.0;
    final barColor = _parseHex(category.colorHex) ?? AppColors.primary;
    final fmt = NumberFormat.currency(symbol: '€', decimalDigits: 0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: barColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    category.name,
                    style: EditorialTypography.bodyMedium.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    fmt.format(category.currentMonthSpent),
                    style: EditorialTypography.bodyMedium.copyWith(
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _TrendChip(category: category),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: AppColors.surfaceContainerLow,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }

  static Color? _parseHex(String? hex) {
    if (hex == null) return null;
    final clean = hex.replaceAll('#', '');
    final val = int.tryParse(
      clean.length == 6 ? 'FF$clean' : clean,
      radix: 16,
    );
    return val != null ? Color(val) : null;
  }
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.category});

  final CategoryIntelligence category;

  @override
  Widget build(BuildContext context) {
    if (!category.hasTrend) return const SizedBox.shrink();
    final isUp = category.isTrendUp;
    final icon =
        isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
    final color = isUp ? const Color(0xFFE05252) : const Color(0xFF4CAF50);
    return Icon(icon, size: 12, color: color);
  }
}

// ─── Top products ─────────────────────────────────────────────────────────────

class _TopProductsCard extends ConsumerWidget {
  const _TopProductsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(topProductsDashboardProvider);

    return EtherealCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Top Products',
                style: EditorialTypography.labelLarge.copyWith(
                  color: AppColors.outline,
                  letterSpacing: 0.8,
                ),
              ),
              GestureDetector(
                onTap: () => context.go(AppRoutes.products),
                child: Text(
                  'See all',
                  style: EditorialTypography.labelSmall.copyWith(
                    color: AppColors.outline,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.verticalLg,
          state.when(
            data: (products) {
              if (products.isEmpty) {
                return const _EmptyHint(
                  icon: Icons.inventory_2_outlined,
                  message: 'No product data this month.',
                );
              }
              return Column(
                children: products
                    .take(5)
                    .map((p) => _ProductRow(product: p))
                    .toList(),
              );
            },
            loading: () => const _CardShimmer(),
            error: (_, __) => const _EmptyHint(
              icon: Icons.error_outline_rounded,
              message: 'Could not load products.',
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});

  final ProductIntelligenceSummary product;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: '€', decimalDigits: 2);
    final categoryColor =
        _parseHex(product.categoryColor) ?? AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          // Product avatar (image or initial)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: product.imageUrl != null
                ? Image.network(
                    product.imageUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _ProductAvatar(name: product.productName, color: categoryColor),
                  )
                : _ProductAvatar(name: product.productName, color: categoryColor),
          ),
          const SizedBox(width: 12),
          // Name + supplier
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EditorialTypography.bodyMedium.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (product.supplierName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    product.supplierName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EditorialTypography.labelSmall.copyWith(
                      color: AppColors.outline,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Spend amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                fmt.format(product.currentMonthSpent),
                style: EditorialTypography.bodyMedium.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (product.purchaseCount > 1)
                Text(
                  '${product.purchaseCount}×',
                  style: EditorialTypography.labelSmall.copyWith(
                    color: AppColors.outline,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Color? _parseHex(String? hex) {
    if (hex == null) return null;
    final clean = hex.replaceAll('#', '');
    final val = int.tryParse(
      clean.length == 6 ? 'FF$clean' : clean,
      radix: 16,
    );
    return val != null ? Color(val) : null;
  }
}

class _ProductAvatar extends StatelessWidget {
  const _ProductAvatar({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isNotEmpty
        ? name.trim()[0].toUpperCase()
        : '?';
    return Container(
      width: 44,
      height: 44,
      color: color.withOpacity(0.15),
      child: Center(
        child: Text(
          initials,
          style: EditorialTypography.labelLarge.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ─── Shared helpers ────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: EditorialTypography.bodySmall.copyWith(
                color: AppColors.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardShimmer extends StatelessWidget {
  const _CardShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Container(
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    );
  }
}
