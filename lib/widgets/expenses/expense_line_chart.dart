import 'dart:math' show max, min;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/models/chart_models.dart';
import 'package:hospi_dash/providers/expense_chart_provider.dart';
import 'package:hospi_dash/widgets/expenses/chart_dynamic_header.dart';
import 'package:hospi_dash/widgets/expenses/chart_period_selector.dart';
import 'package:intl/intl.dart';

/// Full expense chart section — dynamic header + period selector + animated
/// Trade Republic-style line chart.
///
/// This widget owns both the [AnimationController] for the draw-on-load effect
/// and the [ValueNotifier] that drives the [ChartDynamicHeader] during touch.
class ExpenseLineChart extends ConsumerStatefulWidget {
  const ExpenseLineChart({super.key});

  @override
  ConsumerState<ExpenseLineChart> createState() => _ExpenseLineChartState();
}

class _ExpenseLineChartState extends ConsumerState<ExpenseLineChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _drawController;
  late Animation<double> _drawAnimation;

  /// Drives the header display while the user touches the chart.
  final _touchNotifier = ValueNotifier<TouchedData?>(null);

  @override
  void initState() {
    super.initState();
    _drawController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _drawAnimation = CurvedAnimation(
      parent: _drawController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _drawController.dispose();
    _touchNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Restart the draw animation whenever new chart data arrives.
    ref.listen<AsyncValue<List<ChartDataPoint>>>(chartDataProvider, (prev, next) {
      if (next.hasValue && !next.isLoading) {
        _drawController.reset();
        _drawController.forward();
      }
    });

    final chartAsync = ref.watch(chartDataProvider);
    final period = ref.watch(chartPeriodProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dynamic header — updates while user drags
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: ChartDynamicHeader(touchNotifier: _touchNotifier),
        ),
        const SizedBox(height: 20),

        // Period pills
        const ChartPeriodSelector(),
        const SizedBox(height: 12),

        // Chart area
        chartAsync.when(
          loading: _buildSkeleton,
          error: (_, __) => _buildError(),
          data: (points) => points.isEmpty
              ? _buildEmpty()
              : _buildChart(points, period),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Chart builder
  // ---------------------------------------------------------------------------

  Widget _buildChart(List<ChartDataPoint> points, ChartPeriod period) {
    // Line color determined by full-period trend, not the animation window.
    final isPositiveTrend = points.last.value >= points.first.value;
    final lineColor = isPositiveTrend
        ? const Color(0xFF1F8F5C) // EditorialColors.accent
        : const Color(0xFFB23A3A); // EditorialColors.error

    return AnimatedBuilder(
      animation: _drawAnimation,
      builder: (context, _) {
        // Clip points to the animated draw fraction.
        final visibleCount =
            (_drawAnimation.value * points.length).ceil().clamp(1, points.length);
        final visiblePoints = points.sublist(0, visibleCount);

        final spots = List<FlSpot>.generate(
          visiblePoints.length,
          (i) => FlSpot(i.toDouble(), visiblePoints[i].value),
        );

        // Y-axis bounds — always have at least 10 units of headroom.
        final rawMin = spots.map((s) => s.y).reduce(min);
        final rawMax = spots.map((s) => s.y).reduce(max);
        final range = rawMax - rawMin;
        final paddingY = max(range * 0.12, max(rawMax * 0.05, 10.0));
        final minY = max(0.0, rawMin - paddingY);
        final maxY = rawMax + paddingY;
        final yInterval = max(1.0, (maxY - minY) / 3);

        // X-axis label interval based on period.
        final xInterval = _xInterval(points.length, period);

        // Reference line at the first data point's cumulative value.
        final refY = points.first.value.clamp(minY, maxY);

        return SizedBox(
          height: 200,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: LineChart(
              duration: Duration.zero, // we drive animation ourselves
              LineChartData(
                minX: 0,
                maxX: max(1.0, (points.length - 1).toDouble()),
                minY: minY,
                maxY: maxY,

                // Dashed reference line at period start value
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: refY,
                      color: const Color(0xFFABB3B7),
                      strokeWidth: 1.2,
                      dashArray: [4, 4],
                    ),
                  ],
                ),

                // Subtle horizontal grid, no vertical lines, no border
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  drawHorizontalLine: true,
                  horizontalInterval: yInterval,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: Color(0x0D1A1C1C), // ~5% opacity of near-black
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),

                // Axis labels
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: xInterval,
                      getTitlesWidget: (value, meta) =>
                          _buildXLabel(value, points, period),
                    ),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 60,
                      interval: yInterval,
                      getTitlesWidget: (value, meta) {
                        // Skip the very top and bottom labels to avoid clipping.
                        if (value == meta.min || value == meta.max) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            _formatYLabel(value),
                            style: const TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 10,
                              color: Color(0xFF9CA3AF),
                              height: 1,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Touch: crosshair + dot + tooltip + header updates
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchCallback: (event, response) {
                    if (event is FlTapUpEvent || event is FlPanEndEvent) {
                      _touchNotifier.value = null;
                      return;
                    }
                    final lineBarSpots = response?.lineBarSpots;
                    if (lineBarSpots != null && lineBarSpots.isNotEmpty) {
                      final spot = lineBarSpots.first;
                      final idx = spot.spotIndex.clamp(0, points.length - 1);
                      _touchNotifier.value = TouchedData(
                        point: points[idx],
                        x: spot.x,
                        y: spot.y,
                      );
                    }
                  },
                  // Vertical crosshair + circle indicator
                  getTouchedSpotIndicator: (barData, spotIndexes) =>
                      spotIndexes
                          .map(
                            (index) => TouchedSpotIndicatorData(
                              const FlLine(
                                color: Color(0x261A1C1C), // ~15% opacity
                                strokeWidth: 1,
                              ),
                              FlDotData(
                                show: true,
                                getDotPainter: (spot, percent, bar, idx) =>
                                    FlDotCirclePainter(
                                  radius: 5,
                                  color: lineColor,
                                  strokeWidth: 2.5,
                                  strokeColor: Colors.white,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                  // Dark tooltip: cumulative + daily + doc count
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1A1C1C),
                    tooltipRoundedRadius: 8,
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    getTooltipItems: (touchedSpots) =>
                        touchedSpots.map((s) {
                          final idx = s.spotIndex.clamp(0, points.length - 1);
                          final p = points[idx];
                          final lines = StringBuffer();
                          lines.write('${_formatCompact(p.value)} €');
                          if (p.dailyAmount > 0) {
                            lines.write('\n+${_formatCompact(p.dailyAmount)} €');
                          }
                          if (p.documentCount > 0) {
                            lines.write(
                              '\n${p.documentCount} doc${p.documentCount == 1 ? '' : 's'}',
                            );
                          }
                          lines.write('\n${_formatTooltipDate(p.date, period)}');
                          return LineTooltipItem(
                            lines.toString(),
                            const TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          );
                        }).toList(),
                  ),
                ),

                // The data line
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: lineColor,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // State widgets
  // ---------------------------------------------------------------------------

  Widget _buildSkeleton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
      )
          .animate(onPlay: (c) => c.repeat())
          .shimmer(
            duration: const Duration(milliseconds: 1500),
            color: Colors.white.withOpacity(0.6),
          ),
    );
  }

  Widget _buildEmpty() {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart_rounded, size: 36, color: Colors.grey[300]),
            const SizedBox(height: 8),
            Text(
              'No expenses this period',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return const SizedBox(
      height: 200,
      child: Center(
        child: Text(
          'Could not load chart data',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            color: Color(0xFF9CA3AF),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Number of data points between X-axis labels.
  double _xInterval(int count, ChartPeriod period) {
    final divisions = switch (period) {
      ChartPeriod.oneWeek => 4,
      ChartPeriod.oneMonth => 5,
      ChartPeriod.threeMonths => 4,
      ChartPeriod.sixMonths => 6,
      ChartPeriod.oneYear => 12,
    };
    return max(1.0, (count / divisions).floorToDouble());
  }

  Widget _buildXLabel(
    double value,
    List<ChartDataPoint> points,
    ChartPeriod period,
  ) {
    final index = value.round();
    if (index < 0 || index >= points.length) return const SizedBox.shrink();
    final date = points[index].date;

    final label = switch (period) {
      ChartPeriod.oneWeek => DateFormat('E').format(date),
      ChartPeriod.oneMonth => '${date.day}/${date.month}',
      ChartPeriod.threeMonths => DateFormat('MMM d').format(date),
      ChartPeriod.sixMonths || ChartPeriod.oneYear => DateFormat('MMM').format(date),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 10,
          color: Color(0xFF9CA3AF),
          height: 1,
        ),
      ),
    );
  }

  /// Compact Y-axis label: "1.2k €", "500 €", etc.
  String _formatYLabel(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M €';
    }
    if (value >= 1000) {
      final k = value / 1000;
      return '${k >= 100 ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}k €';
    }
    return '${value.toStringAsFixed(0)} €';
  }

  /// Compact value for the tooltip body.
  String _formatCompact(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return NumberFormat('#,##0.00', 'de_DE').format(value);
  }

  String _formatTooltipDate(DateTime date, ChartPeriod period) {
    return switch (period) {
      ChartPeriod.oneWeek => DateFormat('EEE, d MMM').format(date),
      ChartPeriod.oneMonth ||
      ChartPeriod.threeMonths =>
        DateFormat('d MMM').format(date),
      ChartPeriod.sixMonths ||
      ChartPeriod.oneYear =>
        DateFormat('MMM yyyy').format(date),
    };
  }
}
