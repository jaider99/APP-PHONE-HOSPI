import 'package:flutter/foundation.dart';

/// Date range selection for sales filtering
enum DateRangeType {
  today,
  yesterday,
  thisWeek,
  thisMonth,
  custom,
}

/// Represents a selected date range with computed start/end times
class SalesDateRange {
  final DateRangeType type;
  final DateTime start;
  final DateTime end;
  final DateTime priorStart;
  final DateTime priorEnd;

  const SalesDateRange({
    required this.type,
    required this.start,
    required this.end,
    required this.priorStart,
    required this.priorEnd,
  });

  /// Factory to create date ranges with proper comparison periods
  factory SalesDateRange.fromType(DateRangeType type, {DateTime? customStart, DateTime? customEnd}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    DateTime start;
    DateTime end;
    DateTime priorStart;
    DateTime priorEnd;

    switch (type) {
      case DateRangeType.today:
        start = today;
        end = now;
        // Compare to yesterday same hour window
        priorStart = today.subtract(const Duration(days: 1));
        priorEnd = now.subtract(const Duration(days: 1));
        break;

      case DateRangeType.yesterday:
        start = today.subtract(const Duration(days: 1));
        end = today;
        // Compare to same day last week
        priorStart = today.subtract(const Duration(days: 8));
        priorEnd = today.subtract(const Duration(days: 7));
        break;

      case DateRangeType.thisWeek:
        // Find last Monday
        final weekday = now.weekday;
        start = today.subtract(Duration(days: weekday - 1));
        end = now;
        // Compare to previous 7 days
        priorStart = start.subtract(const Duration(days: 7));
        priorEnd = end.subtract(const Duration(days: 7));
        break;

      case DateRangeType.thisMonth:
        start = DateTime(now.year, now.month, 1);
        end = now;
        // Compare to same date range last month
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        priorStart = lastMonth;
        final dayOfMonth = now.day;
        priorEnd = DateTime(lastMonth.year, lastMonth.month, dayOfMonth, now.hour, now.minute);
        break;

      case DateRangeType.custom:
        if (customStart == null || customEnd == null) {
          throw ArgumentError('Custom date range requires start and end dates');
        }
        start = DateTime(customStart.year, customStart.month, customStart.day);
        end = DateTime(customEnd.year, customEnd.month, customEnd.day, 23, 59, 59);
        // Prior window of same length
        final duration = end.difference(start);
        priorEnd = start;
        priorStart = priorEnd.subtract(duration);
        break;
    }

    return SalesDateRange(
      type: type,
      start: start,
      end: end,
      priorStart: priorStart,
      priorEnd: priorEnd,
    );
  }

  /// Determine chart time bucket based on range
  ChartTimeBucket get timeBucket {
    final days = end.difference(start).inDays;
    if (days <= 2) return ChartTimeBucket.hourly;
    if (days <= 31) return ChartTimeBucket.daily;
    return ChartTimeBucket.weekly;
  }

  String get displayLabel {
    switch (type) {
      case DateRangeType.today:
        return 'Today';
      case DateRangeType.yesterday:
        return 'Yesterday';
      case DateRangeType.thisWeek:
        return 'This Week';
      case DateRangeType.thisMonth:
        return 'This Month';
      case DateRangeType.custom:
        return 'Custom';
    }
  }
}

/// Time bucket for chart aggregation
enum ChartTimeBucket { hourly, daily, weekly }

/// KPI summary data
class KpiData {
  final double netRevenue;
  final int totalOrders;
  final double avgOrderValue;
  final int covers;
  final double priorNetRevenue;
  final int priorTotalOrders;
  final double priorAvgOrderValue;
  final int priorCovers;

  const KpiData({
    required this.netRevenue,
    required this.totalOrders,
    required this.avgOrderValue,
    required this.covers,
    required this.priorNetRevenue,
    required this.priorTotalOrders,
    required this.priorAvgOrderValue,
    required this.priorCovers,
  });

  double get revenueChangePercent {
    if (priorNetRevenue == 0) return netRevenue > 0 ? 100 : 0;
    return ((netRevenue - priorNetRevenue) / priorNetRevenue) * 100;
  }

  double get ordersChangePercent {
    if (priorTotalOrders == 0) return totalOrders > 0 ? 100 : 0;
    return ((totalOrders - priorTotalOrders) / priorTotalOrders) * 100;
  }

  double get avgChangePercent {
    if (priorAvgOrderValue == 0) return avgOrderValue > 0 ? 100 : 0;
    return ((avgOrderValue - priorAvgOrderValue) / priorAvgOrderValue) * 100;
  }

  double get coversChangePercent {
    if (priorCovers == 0) return covers > 0 ? 100 : 0;
    return ((covers - priorCovers) / priorCovers) * 100;
  }

  factory KpiData.empty() => const KpiData(
        netRevenue: 0,
        totalOrders: 0,
        avgOrderValue: 0,
        covers: 0,
        priorNetRevenue: 0,
        priorTotalOrders: 0,
        priorAvgOrderValue: 0,
        priorCovers: 0,
      );
}

/// Revenue data point for chart
class RevenueDataPoint {
  final DateTime timestamp;
  final double grossRevenue;
  final double netRevenue;
  final int orderCount;

  const RevenueDataPoint({
    required this.timestamp,
    required this.grossRevenue,
    required this.netRevenue,
    required this.orderCount,
  });

  @override
  String toString() =>
      'RevenueDataPoint(timestamp: $timestamp, gross: $grossRevenue, net: $netRevenue, orders: $orderCount)';
}

/// Category sales breakdown
class CategorySales {
  final String categoryId;
  final String categoryName;
  final double revenue;
  final double percentOfTotal;

  const CategorySales({
    required this.categoryId,
    required this.categoryName,
    required this.revenue,
    required this.percentOfTotal,
  });

  factory CategorySales.fromJson(Map<String, dynamic> json, double totalRevenue) {
    final revenue = (json['total_revenue'] as num?)?.toDouble() ?? 0;
    final categoryData = json['categories'] as Map<String, dynamic>?;
    
    return CategorySales(
      categoryId: json['category_id'] as String? ?? '',
      categoryName: categoryData?['name'] as String? ?? 'Uncategorized',
      revenue: revenue,
      percentOfTotal: totalRevenue > 0 ? (revenue / totalRevenue) * 100 : 0,
    );
  }
}

/// Top selling product
class TopProduct {
  final String productId;
  final String productName;
  final int quantitySold;
  final double revenue;
  final int rank;

  const TopProduct({
    required this.productId,
    required this.productName,
    required this.quantitySold,
    required this.revenue,
    required this.rank,
  });

  factory TopProduct.fromJson(Map<String, dynamic> json, int rank) {
    final productData = json['products'] as Map<String, dynamic>?;
    
    return TopProduct(
      productId: json['product_id'] as String? ?? '',
      productName: productData?['name'] as String? ?? 'Unknown Product',
      quantitySold: (json['total_quantity'] as num?)?.toInt() ?? 0,
      revenue: (json['total_revenue'] as num?)?.toDouble() ?? 0,
      rank: rank,
    );
  }
}

/// Payment method split
class PaymentSplit {
  final String method;
  final double amount;
  final double percentOfTotal;

  const PaymentSplit({
    required this.method,
    required this.amount,
    required this.percentOfTotal,
  });

  String get displayName {
    switch (method.toLowerCase()) {
      case 'cash':
        return 'Cash';
      case 'card':
        return 'Card';
      case 'online':
        return 'Online';
      default:
        return method;
    }
  }
}

/// Data for AI insight generation
class InsightData {
  final String trend;
  final bool anomaly;
  final double changePercent;
  final List<String> possibleCauses;

  const InsightData({
    required this.trend,
    required this.anomaly,
    required this.changePercent,
    required this.possibleCauses,
  });

  Map<String, dynamic> toJson() => {
        'trend': trend,
        'anomaly': anomaly,
        'changePercent': changePercent,
        'possibleCauses': possibleCauses,
      };

  factory InsightData.fromKpi(KpiData kpi) {
    final change = kpi.revenueChangePercent;
    String trend;
    if (change > 5) {
      trend = 'up';
    } else if (change < -5) {
      trend = 'down';
    } else {
      trend = 'flat';
    }

    final List<String> causes = [];
    if (kpi.covers < kpi.priorCovers * 0.7) {
      causes.add('low foot traffic');
    }
    if (kpi.avgOrderValue < kpi.priorAvgOrderValue * 0.8) {
      causes.add('lower average spend per customer');
    }

    return InsightData(
      trend: trend,
      anomaly: change.abs() > 20,
      changePercent: change,
      possibleCauses: causes,
    );
  }
}

/// Raw order data from Supabase
@immutable
class OrderData {
  final String id;
  final DateTime createdAt;
  final String status;
  final double totalAmount;
  final double taxAmount;
  final double discountAmount;
  final String paymentMethod;
  final int covers;

  const OrderData({
    required this.id,
    required this.createdAt,
    required this.status,
    required this.totalAmount,
    required this.taxAmount,
    required this.discountAmount,
    required this.paymentMethod,
    required this.covers,
  });

  double get netAmount => totalAmount - taxAmount - discountAmount;

  factory OrderData.fromJson(Map<String, dynamic> json) {
    return OrderData(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      status: json['status'] as String? ?? 'completed',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      covers: (json['covers'] as num?)?.toInt() ?? 1,
    );
  }
}
