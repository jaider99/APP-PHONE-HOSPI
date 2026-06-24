import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/app_colors.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/sales/data/models/sales_models.dart';
import 'package:intl/intl.dart';

/// Revenue area chart with gross and net revenue series
class RevenueChart extends StatefulWidget {
  final List<RevenueDataPoint> data;
  final ChartTimeBucket timeBucket;
  
  const RevenueChart({
    super.key,
    required this.data,
    required this.timeBucket,
  });
  
  @override
  State<RevenueChart> createState() => _RevenueChartState();
}

class _RevenueChartState extends State<RevenueChart> {
  bool _showGross = true;
  bool _showNet = true;
  
  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) {
      return _buildEmptyState();
    }
    
    final currencyFormat = NumberFormat.currency(
      locale: 'es_ES',
      symbol: '€',
      decimalDigits: 0,
    );
    
    // Calculate Y-axis range
    double maxY = 0;
    for (final point in widget.data) {
      if (_showGross && point.grossRevenue > maxY) maxY = point.grossRevenue;
      if (_showNet && point.netRevenue > maxY) maxY = point.netRevenue;
    }
    maxY = maxY * 1.2; // Add 20% headroom
    if (maxY == 0) maxY = 100;
    
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withOpacity(0.04),
            blurRadius: 40,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with legend toggles
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Revenue',
                style: EditorialTypography.titleMedium.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              Row(
                children: [
                  _LegendChip(
                    label: 'Gross',
                    color: AppColors.secondaryContainer,
                    isActive: _showGross,
                    onTap: () => setState(() => _showGross = !_showGross),
                  ),
                  const SizedBox(width: 8),
                  _LegendChip(
                    label: 'Net',
                    color: AppColors.secondary,
                    isActive: _showNet,
                    onTap: () => setState(() => _showNet = !_showNet),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Chart
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppColors.outlineVariant.withOpacity(0.2),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 60,
                      interval: maxY / 4,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            currencyFormat.format(value),
                            style: EditorialTypography.labelSmall.copyWith(
                              fontSize: 10,
                              color: AppColors.primary,
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
                      interval: _getBottomInterval(),
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= widget.data.length) {
                          return const SizedBox.shrink();
                        }
                        final point = widget.data[index];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _formatXLabel(point.timestamp),
                            style: EditorialTypography.labelSmall.copyWith(
                              fontSize: 10,
                              color: AppColors.primary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (widget.data.length - 1).toDouble(),
                minY: 0,
                maxY: maxY,
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.onSurface,
                    tooltipRoundedRadius: 12,
                    tooltipPadding: const EdgeInsets.all(12),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final index = spot.x.toInt();
                        if (index < 0 || index >= widget.data.length) return null;
                        
                        final point = widget.data[index];
                        final isGross = spot.barIndex == 0;
                        
                        return LineTooltipItem(
                          '${isGross ? 'Gross' : 'Net'}: ${currencyFormat.format(spot.y)}\n'
                          'Orders: ${point.orderCount}',
                          EditorialTypography.bodySmall.copyWith(
                            color: AppColors.surfaceContainerLowest,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  // Gross revenue area
                  if (_showGross)
                    LineChartBarData(
                      spots: widget.data.asMap().entries.map((e) {
                        return FlSpot(e.key.toDouble(), e.value.grossRevenue);
                      }).toList(),
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: AppColors.secondary,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.secondaryContainer.withOpacity(0.3),
                      ),
                    ),
                  
                  // Net revenue line
                  if (_showNet)
                    LineChartBarData(
                      spots: widget.data.asMap().entries.map((e) {
                        return FlSpot(e.key.toDouble(), e.value.netRevenue);
                      }).toList(),
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: AppColors.secondary,
                      barWidth: 3,
                      isStrokeCapRound: true,
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
  
  double _getBottomInterval() {
    final count = widget.data.length;
    if (count <= 6) return 1;
    if (count <= 12) return 2;
    if (count <= 24) return 4;
    return (count / 6).ceilToDouble();
  }
  
  String _formatXLabel(DateTime dt) {
    switch (widget.timeBucket) {
      case ChartTimeBucket.hourly:
        return DateFormat('HH:mm').format(dt);
      case ChartTimeBucket.daily:
        return DateFormat('d MMM').format(dt);
      case ChartTimeBucket.weekly:
        return DateFormat('d MMM').format(dt);
    }
  }
  
  Widget _buildEmptyState() {
    return Container(
      height: 280,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withOpacity(0.04),
            blurRadius: 40,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart_rounded,
              size: 48,
              color: AppColors.outlineVariant.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No completed orders for this period yet',
              style: EditorialTypography.bodyMedium.copyWith(
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Legend toggle chip for chart series
class _LegendChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;
  
  const _LegendChip({
    required this.label,
    required this.color,
    required this.isActive,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.2) : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isActive ? color : AppColors.outlineVariant,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: EditorialTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w500,
                color: isActive ? AppColors.onSurface : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Error state for chart
class RevenueChartError extends StatelessWidget {
  final VoidCallback onRetry;
  
  const RevenueChartError({super.key, required this.onRetry});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withOpacity(0.04),
            blurRadius: 40,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.error.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load chart data',
              style: EditorialTypography.bodyMedium.copyWith(
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Retry',
                style: EditorialTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
