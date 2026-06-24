import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:hospi_dash/core/theme/app_elevation.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/shared/ui/metric_text.dart';
import 'package:hospi_dash/shared/ui/section_header.dart';

/// Editorial card surface. Flat, hairline border, optional whisper shadow.
/// Use sparingly — most things don't need a card.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: EditorialColors.surface,
      borderRadius: BorderRadius.circular(EditorialRadius.standard),
      border: AppElevation.hairlineBorder,
      boxShadow: elevated ? AppElevation.whisper : const [],
    );

    final content = Padding(padding: padding, child: child);

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: decoration,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                borderRadius:
                    BorderRadius.circular(EditorialRadius.standard),
                child: content,
              ),
      ),
    );
  }
}

/// Insight summary for a supplier. Header row (name + delta), three quiet
/// fact lines. Use under "Top suppliers" or supplier detail headers.
class SupplierInsightCard extends StatelessWidget {
  const SupplierInsightCard({
    super.key,
    required this.supplierName,
    required this.totalSpend,
    required this.deltaPercent,
    required this.invoiceCount,
    required this.lastInvoiceRelative,
    this.onTap,
  });

  final String supplierName;
  final num totalSpend;
  final double deltaPercent;
  final int invoiceCount;
  final String lastInvoiceRelative;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  supplierName,
                  style: EditorialTypography.titleMedium.copyWith(
                    color: EditorialColors.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PriceTrendIndicator(
                deltaPercent: deltaPercent,
                upIsGood: false,
              ),
            ],
          ),
          const SizedBox(height: 10),
          FinancialValue(amount: totalSpend, size: MetricSize.medium),
          const SizedBox(height: 12),
          Row(
            children: [
              _Fact(label: 'Invoices', value: '$invoiceCount'),
              const SizedBox(width: 24),
              Expanded(
                child: _Fact(
                  label: 'Last',
                  value: lastInvoiceRelative,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toLowerCase(),
          style: EditorialTypography.labelSmall.copyWith(
            color: EditorialColors.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: EditorialTypography.bodyMedium.copyWith(
            color: EditorialColors.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Single price-history series point.
class PricePoint {
  const PricePoint({required this.x, required this.price});
  final double x;
  final double price;
}

/// Editorial sparkline card for product price history. Single ink line,
/// no gradient fill, hairline axis baseline. Headline shows latest price +
/// trend; the section title is supplied via [eyebrow] / [productName].
class ProductPriceChartCard extends StatelessWidget {
  const ProductPriceChartCard({
    super.key,
    required this.productName,
    required this.unit,
    required this.points,
    this.eyebrow,
    this.onTap,
  }) : assert(points.length >= 2,
            'ProductPriceChartCard needs at least 2 points');

  final String productName;
  final String unit;
  final List<PricePoint> points;
  final String? eyebrow;
  final VoidCallback? onTap;

  double get _latest => points.last.price;
  double get _previous => points[points.length - 2].price;
  double get _delta {
    if (_previous == 0) return 0;
    return ((_latest - _previous) / _previous) * 100;
  }

  @override
  Widget build(BuildContext context) {
    final spots = points
        .map((p) => FlSpot(p.x, p.price))
        .toList(growable: false);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionHeader(
            title: productName,
            eyebrow: eyebrow,
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FinancialValue(
                amount: _latest,
                size: MetricSize.medium,
                caption: 'Latest · $unit',
              ),
              const Spacer(),
              PriceTrendIndicator(deltaPercent: _delta, upIsGood: false),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 88,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.22,
                    barWidth: 1.5,
                    color: EditorialColors.onSurface,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
