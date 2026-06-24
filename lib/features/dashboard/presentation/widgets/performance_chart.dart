import 'dart:math' show max, min;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/app_colors.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/data/models/sale.dart';

/// Performance chart section — clean, Trade-Republic-inspired
/// No card wrapper, green line, no fill, right Y-axis with € labels
class PerformanceChartSection extends StatelessWidget {
  const PerformanceChartSection({
    super.key,
    required this.dailyRevenue,
    this.showAverage = true,
    this.currency = '€',
  });

  final List<DailyRevenue> dailyRevenue;
  final bool showAverage;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final hasData = dailyRevenue.any((d) => d.amount > 0);
    return SizedBox(
      height: 190,
      child: hasData
          ? _RevenueChart(data: dailyRevenue, currency: currency)
          : const _EmptyChart(),
    );
  }
}

/// The actual line chart — clean, no fill, right Y-axis
class _RevenueChart extends StatelessWidget {
  const _RevenueChart({
    required this.data,
    this.currency = '€',
  });

  final List<DailyRevenue> data;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final chartData = data.length > 14 ? data.sublist(data.length - 14) : data;
    final spots = chartData.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.amount);
    }).toList();

    final rawMax = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final rawMin = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    // Add 15% headroom above and below so the line never touches the edges
    final padding = max((rawMax - rawMin) * 0.15, 1.0);
    final maxY = max(rawMax + padding, 1.0);
    final minY = min(rawMin - padding, 0.0);
    final range = maxY - minY;
    final hInterval = max(range / 4, 1.0);

    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xl,
        right: 4, // right-axis labels need less outer gap
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: hInterval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.outlineVariant.withOpacity(0.2),
              strokeWidth: 1,
              dashArray: [4, 6],
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                interval: hInterval,
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) {
                    return const SizedBox.shrink();
                  }
                  final label = value >= 1000
                      ? '${(value / 1000).toStringAsFixed(1)}k $currency'
                      : '${value.toStringAsFixed(0)} $currency';
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: EditorialTypography.bodyFont,
                        fontSize: 10,
                        color: AppColors.outline,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= chartData.length) {
                    return const SizedBox.shrink();
                  }
                  // Show only first, middle, last
                  if (index != 0 &&
                      index != chartData.length ~/ 2 &&
                      index != chartData.length - 1) {
                    return const SizedBox.shrink();
                  }
                  final d = chartData[index].date;
                  final label = '${d.day}/${d.month}';
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: EditorialTypography.bodyFont,
                        fontSize: 10,
                        color: AppColors.outline,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: max((chartData.length - 1).toDouble(), 1.0),
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              preventCurveOverShooting: true,
              color: AppColors.chartPrimary,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
          ],
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.onSurface,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '${spot.y.toStringAsFixed(0)} $currency',
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty chart placeholder
class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No data yet',
        style: TextStyle(
          fontFamily: EditorialTypography.bodyFont,
          fontSize: 13,
          color: AppColors.outline,
        ),
      ),
    );
  }
}
