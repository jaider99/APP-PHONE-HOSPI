import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/providers/data/models/supplier_intelligence_model.dart';
import 'package:hospi_dash/features/providers/providers/supplier_intelligence_providers.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/shared/widgets/app_back_button.dart';

/// Full-screen supplier intelligence detail page.
///
/// Sections:
///  • HEADER — avatar, name, total spend, order count, trend badge
///  • MONTHLY SPEND — bar chart (last 12 months)
///  • CATEGORY BREAKDOWN — ranked horizontal bars
///  • RECENT DOCUMENTS — last 10 linked invoices
class SupplierDetailScreen extends ConsumerWidget {
  const SupplierDetailScreen({super.key, required this.supplierId});

  final String supplierId;

  static final _currencyFmt = NumberFormat.currency(
    locale: 'es_ES',
    symbol: '€',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supplierAsync = ref.watch(supplierDetailProvider(supplierId));
    final currencySymbol =
        ref.watch(currencySymbolProvider).valueOrNull ?? '€';

    return Scaffold(
      backgroundColor: EditorialColors.background,
      body: supplierAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: EditorialColors.primary,
            strokeWidth: 2,
          ),
        ),
        error: (e, _) => _buildError(context, e.toString()),
        data: (supplier) {
          if (supplier == null) {
            return _buildError(context, 'Supplier not found');
          }
          return _buildContent(context, ref, supplier, currencySymbol);
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    SupplierIntelligence supplier,
    String currencySymbol,
  ) {
    final monthlyAsync = ref.watch(supplierMonthlySpendProvider(supplierId));
    final categoriesAsync =
        ref.watch(supplierCategoryBreakdownProvider(supplierId));
    final docsAsync = ref.watch(supplierRecentDocumentsProvider(supplierId));

    return CustomScrollView(
      slivers: [
        // ── App bar with back button ─────────────────────────────────────
        SliverAppBar(
          pinned: true,
          elevation: 0,
          backgroundColor: EditorialColors.background,
          surfaceTintColor: Colors.transparent,
          leading: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: AppBackButton(fallbackRoute: AppRoutes.providers),
          ),
          title: Text(
            supplier.name,
            style: EditorialTypography.titleMedium.copyWith(
              color: EditorialColors.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // ── HEADER ────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _SupplierHeader(
            supplier: supplier,
            currencyFmt: _currencyFmt,
          ),
        ),

        // ── MONTHLY SPEND CHART ──────────────────────────────────────────
        SliverToBoxAdapter(
          child: monthlyAsync.when(
            loading: () => const _ChartSkeleton(),
            error: (_, __) => const SizedBox.shrink(),
            data: (months) {
              if (months.isEmpty) return const SizedBox.shrink();
              return _MonthlySpendChart(
                months: months,
                currencySymbol: currencySymbol,
              );
            },
          ),
        ),

        // ── CATEGORY BREAKDOWN ───────────────────────────────────────────
        SliverToBoxAdapter(
          child: categoriesAsync.when(
            loading: () => const _SectionSkeleton(),
            error: (_, __) => const SizedBox.shrink(),
            data: (cats) {
              if (cats.isEmpty) return const SizedBox.shrink();
              return _CategoryBreakdown(
                categories: cats,
                currencyFmt: _currencyFmt,
              );
            },
          ),
        ),

        // ── RECENT DOCUMENTS ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: docsAsync.when(
            loading: () => const _SectionSkeleton(),
            error: (_, __) => const SizedBox.shrink(),
            data: (docs) {
              if (docs.isEmpty) return const SizedBox.shrink();
              return _RecentDocuments(docs: docs, currencyFmt: _currencyFmt);
            },
          ),
        ),

        // Bottom clearance
        const SliverToBoxAdapter(child: SizedBox(height: 48)),
      ],
    );
  }

  Widget _buildError(BuildContext context, String message) {
    return Scaffold(
      backgroundColor: EditorialColors.background,
      appBar: AppBar(
        backgroundColor: EditorialColors.background,
        elevation: 0,
        leading: const AppBackButton(fallbackRoute: AppRoutes.providers),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: EditorialColors.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: EditorialTypography.bodyMedium.copyWith(
                color: EditorialColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _SupplierHeader extends StatelessWidget {
  const _SupplierHeader({
    required this.supplier,
    required this.currencyFmt,
  });

  final SupplierIntelligence supplier;
  final NumberFormat currencyFmt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.lg,
        AppSpacing.screenPadding,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + name row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Large avatar
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: EditorialColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    supplier.initials,
                    style: EditorialTypography.headlineSmall.copyWith(
                      color: EditorialColors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supplier.name,
                      style: EditorialTypography.titleLarge.copyWith(
                        color: EditorialColors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (supplier.category != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        supplier.category!,
                        style: EditorialTypography.bodySmall.copyWith(
                          color: EditorialColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // KPI row
          Row(
            children: [
              _KpiPill(
                label: 'Total spent',
                value: supplier.totalSpent > 0
                    ? currencyFmt.format(supplier.totalSpent)
                    : '—',
              ),
              const SizedBox(width: AppSpacing.sm),
              _KpiPill(
                label: 'Documents',
                value: supplier.totalOrders.toString(),
              ),
              if (supplier.hasTrend) ...[
                const SizedBox(width: AppSpacing.sm),
                _TrendPill(isUp: supplier.isTrendUp),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _KpiPill extends StatelessWidget {
  const _KpiPill({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: EditorialColors.onSurface.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: EditorialTypography.labelSmall.copyWith(
              color: EditorialColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: EditorialTypography.titleSmall.copyWith(
              color: EditorialColors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendPill extends StatelessWidget {
  const _TrendPill({required this.isUp});
  final bool isUp;

  @override
  Widget build(BuildContext context) {
    final color = isUp ? EditorialColors.error : EditorialColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isUp
            ? EditorialColors.errorLight
            : EditorialColors.accentContainer.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isUp ? 'Spending up' : 'Spending down',
            style: EditorialTypography.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Monthly spend chart ──────────────────────────────────────────────────────

class _MonthlySpendChart extends StatelessWidget {
  const _MonthlySpendChart({required this.months, required this.currencySymbol});
  final List<SupplierMonthlySpend> months;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final maxVal = months.map((m) => m.totalSpent).reduce((a, b) => a > b ? a : b);
    final displayMonths = months.length > 12 ? months.sublist(months.length - 12) : months;

    return _Section(
      title: 'Monthly Spend',
      child: SizedBox(
        height: 160,
        child: BarChart(
          BarChartData(
            maxY: maxVal * 1.25,
            minY: 0,
            barGroups: displayMonths.asMap().entries.map((e) {
              final idx = e.key;
              final month = e.value;
              final isCurrentMonth =
                  month.year == DateTime.now().year &&
                  month.month == DateTime.now().month;
              return BarChartGroupData(
                x: idx,
                barRods: [
                  BarChartRodData(
                    toY: month.totalSpent,
                    color: isCurrentMonth
                        ? EditorialColors.primary
                        : EditorialColors.surfaceContainerHigh,
                    width: 18,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                ],
              );
            }).toList(),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= displayMonths.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        displayMonths[idx].monthLabel,
                        style: EditorialTypography.labelSmall.copyWith(
                          color: EditorialColors.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxVal / 4,
              getDrawingHorizontalLine: (value) => FlLine(
                color: EditorialColors.surfaceContainerHigh,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => EditorialColors.primary,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final month = displayMonths[group.x];
                  return BarTooltipItem(
                    '$currencySymbol ${rod.toY.toStringAsFixed(0)}\n',
                    EditorialTypography.labelSmall.copyWith(
                      color: EditorialColors.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    children: [
                      TextSpan(
                        text: '${month.monthLabel} ${month.year}',
                        style: EditorialTypography.labelSmall.copyWith(
                          color: EditorialColors.onPrimary.withOpacity(0.7),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Category breakdown ───────────────────────────────────────────────────────

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({
    required this.categories,
    required this.currencyFmt,
  });

  final List<SupplierCategoryBreakdown> categories;
  final NumberFormat currencyFmt;

  @override
  Widget build(BuildContext context) {
    final maxVal = categories.map((c) => c.totalSpent).reduce((a, b) => a > b ? a : b);

    return _Section(
      title: 'By Category',
      child: Column(
        children: categories.take(6).map((cat) {
          final fraction = maxVal > 0 ? cat.totalSpent / maxVal : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _CategoryBar(
              name: cat.categoryName,
              fraction: fraction,
              amount: currencyFmt.format(cat.totalSpent),
              count: cat.orderCount,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.name,
    required this.fraction,
    required this.amount,
    required this.count,
  });

  final String name;
  final double fraction;
  final String amount;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                name,
                style: EditorialTypography.bodySmall.copyWith(
                  color: EditorialColors.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              amount,
              style: EditorialTypography.labelSmall.copyWith(
                color: EditorialColors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (ctx, constraints) {
            return Stack(
              children: [
                Container(
                  height: 6,
                  width: constraints.maxWidth,
                  decoration: BoxDecoration(
                    color: EditorialColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Container(
                  height: 6,
                  width: constraints.maxWidth * fraction.clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    color: EditorialColors.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 3),
        Text(
          '$count doc${count == 1 ? '' : 's'}',
          style: EditorialTypography.labelSmall.copyWith(
            color: EditorialColors.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

// ─── Recent documents ─────────────────────────────────────────────────────────

class _RecentDocuments extends StatelessWidget {
  const _RecentDocuments({required this.docs, required this.currencyFmt});
  final List<SupplierDocument> docs;
  final NumberFormat currencyFmt;

  String _formatDate(DateTime? date) {
    if (date == null) return '—';
    return DateFormat('d MMM yyyy').format(date);
  }

  String _docTypeLabel(String type) {
    switch (type) {
      case 'invoice':        return 'Invoice';
      case 'delivery_note':  return 'Delivery Note';
      case 'expense_ticket': return 'Ticket';
      case 'credit_note':    return 'Credit Note';
      default:               return 'Document';
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Recent Documents',
      child: Column(
        children: docs.map((doc) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: EditorialColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: EditorialColors.onSurface.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Type icon
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: EditorialColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      size: 18,
                      color: EditorialColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _docTypeLabel(doc.documentType),
                          style: EditorialTypography.bodySmall.copyWith(
                            color: EditorialColors.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          doc.documentNumber != null
                              ? '${doc.documentNumber!} · ${_formatDate(doc.documentDate)}'
                              : _formatDate(doc.documentDate),
                          style: EditorialTypography.labelSmall.copyWith(
                            color: EditorialColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    currencyFmt.format(doc.totalAmount),
                    style: EditorialTypography.titleSmall.copyWith(
                      color: EditorialColors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Section wrapper ──────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        0,
        AppSpacing.screenPadding,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: EditorialTypography.labelSmall.copyWith(
              color: EditorialColors.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

// ─── Skeletons ────────────────────────────────────────────────────────────────

class _ChartSkeleton extends StatelessWidget {
  const _ChartSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        0,
        AppSpacing.screenPadding,
        AppSpacing.xl,
      ),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: EditorialColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        0,
        AppSpacing.screenPadding,
        AppSpacing.xl,
      ),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: EditorialColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

