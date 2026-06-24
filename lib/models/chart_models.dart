import 'package:flutter/material.dart';

/// Chart periods available in the period selector.
enum ChartPeriod { oneWeek, oneMonth, threeMonths, sixMonths, oneYear }

extension ChartPeriodX on ChartPeriod {
  /// Short label shown in the period pill selector.
  String get label => const {
        ChartPeriod.oneWeek: '1W',
        ChartPeriod.oneMonth: '1M',
        ChartPeriod.threeMonths: '3M',
        ChartPeriod.sixMonths: '6M',
        ChartPeriod.oneYear: '1Y',
      }[this]!;

  /// Human-readable subtitle shown in the dynamic header.
  String get periodName => const {
        ChartPeriod.oneWeek: 'Last 7 days',
        ChartPeriod.oneMonth: 'Last 30 days',
        ChartPeriod.threeMonths: 'Last 3 months',
        ChartPeriod.sixMonths: 'Last 6 months',
        ChartPeriod.oneYear: 'Last year',
      }[this]!;
}

/// A single point in the expense chart — cumulative total up to [date].
class ChartDataPoint {
  const ChartDataPoint({
    required this.date,
    required this.value,
    required this.dailyAmount,
    this.documentCount = 0,
  });

  /// The date for this point.
  final DateTime date;

  /// Cumulative running total of expenses up to and including this date.
  final double value;

  /// Amount spent on this specific date (not cumulative).
  final double dailyAmount;

  /// Number of documents that contributed to [dailyAmount].
  final int documentCount;
}

/// KPI summary for the chart section — expenses, net profit, and comparison.
class ChartKpi {
  const ChartKpi({
    required this.totalExpenses,
    required this.netProfit,
    required this.totalTax,
    required this.comparisonLabel,
    required this.comparisonColor,
    this.undatedCount = 0,
    this.documentCount = 0,
  });

  final double totalExpenses;
  final double netProfit;
  final double totalTax;

  /// E.g. "+12.3% vs last period" or "Same as last period".
  final String comparisonLabel;

  /// Semantic color for [comparisonLabel] (green = better, red = worse).
  final Color comparisonColor;

  /// Number of completed documents with no extracted [document_date].
  /// These are not shown in the chart and need user attention.
  final int undatedCount;

  /// Total number of completed documents contributing to this period's total.
  final int documentCount;
}

/// Data carried by the touch notifier while the user drags over the chart.
class TouchedData {
  const TouchedData({
    required this.point,
    required this.x,
    required this.y,
  });

  final ChartDataPoint point;

  /// fl_chart x-coordinate of the touched spot.
  final double x;

  /// fl_chart y-coordinate of the touched spot.
  final double y;
}
