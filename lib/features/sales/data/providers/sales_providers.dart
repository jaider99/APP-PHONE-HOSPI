import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/auth_service.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/features/sales/data/models/sales_models.dart';
import 'package:hospi_dash/features/sales/data/services/insight_service.dart';

// =============================================================================
// VENUE/COMPANY ID PROVIDER
// =============================================================================

/// Alias for venue ID (company_id in this multi-tenant app)
// Legacy alias — consumers should migrate to companyIdProvider
final venueIdProvider = companyIdProvider;

// =============================================================================
// DATE RANGE PROVIDER
// =============================================================================

/// Selected date range state
final salesDateRangeProvider = StateProvider<SalesDateRange>((ref) {
  return SalesDateRange.fromType(DateRangeType.today);
});

// =============================================================================
// KPI DATA PROVIDER
// =============================================================================

/// Fetches KPI data for the selected date range
final kpiDataProvider = FutureProvider.autoDispose<KpiData>((ref) async {
  // Read synchronous state BEFORE the first await (Riverpod 2 rule).
  final dateRange = ref.watch(salesDateRangeProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  
  if (companyId == null) {
    throw Exception('No company selected');
  }
  
  final supabase = SupabaseService.client;
  
  // Fetch current period data
  final currentData = await supabase
      .from('orders')
      .select('id, total_amount, tax_amount, discount_amount, covers')
      .eq('company_id', companyId)
      .eq('status', 'completed')
      .gte('created_at', dateRange.start.toIso8601String())
      .lt('created_at', dateRange.end.toIso8601String());
  
  // Fetch prior period data for comparison
  final priorData = await supabase
      .from('orders')
      .select('id, total_amount, tax_amount, discount_amount, covers')
      .eq('company_id', companyId)
      .eq('status', 'completed')
      .gte('created_at', dateRange.priorStart.toIso8601String())
      .lt('created_at', dateRange.priorEnd.toIso8601String());
  
  // Calculate current period KPIs
  double netRevenue = 0;
  int covers = 0;
  for (final row in currentData) {
    final total = (row['total_amount'] as num?)?.toDouble() ?? 0;
    final tax = (row['tax_amount'] as num?)?.toDouble() ?? 0;
    final discount = (row['discount_amount'] as num?)?.toDouble() ?? 0;
    netRevenue += total - tax - discount;
    covers += (row['covers'] as num?)?.toInt() ?? 0;
  }
  final totalOrders = currentData.length;
  final avgOrderValue = totalOrders > 0 ? netRevenue / totalOrders : 0.0;
  
  // Calculate prior period KPIs
  double priorNetRevenue = 0;
  int priorCovers = 0;
  for (final row in priorData) {
    final total = (row['total_amount'] as num?)?.toDouble() ?? 0;
    final tax = (row['tax_amount'] as num?)?.toDouble() ?? 0;
    final discount = (row['discount_amount'] as num?)?.toDouble() ?? 0;
    priorNetRevenue += total - tax - discount;
    priorCovers += (row['covers'] as num?)?.toInt() ?? 0;
  }
  final priorTotalOrders = priorData.length;
  final priorAvgOrderValue = priorTotalOrders > 0 ? priorNetRevenue / priorTotalOrders : 0.0;
  
  return KpiData(
    netRevenue: netRevenue,
    totalOrders: totalOrders,
    avgOrderValue: avgOrderValue,
    covers: covers,
    priorNetRevenue: priorNetRevenue,
    priorTotalOrders: priorTotalOrders,
    priorAvgOrderValue: priorAvgOrderValue,
    priorCovers: priorCovers,
  );
});

// =============================================================================
// REVENUE CHART DATA PROVIDER
// =============================================================================

/// Fetches and aggregates order data for the revenue chart
final revenueChartDataProvider = FutureProvider.autoDispose<List<RevenueDataPoint>>((ref) async {
  // Read synchronous state BEFORE the first await (Riverpod 2 rule).
  final dateRange = ref.watch(salesDateRangeProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  
  if (companyId == null) {
    throw Exception('No company selected');
  }
  
  final supabase = SupabaseService.client;
  
  // Fetch all completed orders in the period
  final orders = await supabase
      .from('orders')
      .select('id, created_at, total_amount, tax_amount, discount_amount')
      .eq('company_id', companyId)
      .eq('status', 'completed')
      .gte('created_at', dateRange.start.toIso8601String())
      .lt('created_at', dateRange.end.toIso8601String())
      .order('created_at', ascending: true);
  
  if (orders.isEmpty) {
    return [];
  }
  
  // Parse orders
  final parsedOrders = orders.map((json) => OrderData.fromJson(json)).toList();
  
  // Aggregate by time bucket
  return _aggregateByBucket(parsedOrders, dateRange);
});

/// Aggregate orders into time buckets
List<RevenueDataPoint> _aggregateByBucket(List<OrderData> orders, SalesDateRange dateRange) {
  final bucket = dateRange.timeBucket;
  final Map<DateTime, _BucketAccumulator> buckets = {};
  
  // Generate bucket keys
  for (final order in orders) {
    final key = _getBucketKey(order.createdAt, bucket);
    buckets.putIfAbsent(key, () => _BucketAccumulator());
    buckets[key]!.addOrder(order);
  }
  
  // Fill in empty buckets for continuous chart
  final filledBuckets = _fillEmptyBuckets(buckets, dateRange, bucket);
  
  // Convert to data points
  return filledBuckets.entries
      .map((e) => RevenueDataPoint(
            timestamp: e.key,
            grossRevenue: e.value.grossRevenue,
            netRevenue: e.value.netRevenue,
            orderCount: e.value.orderCount,
          ))
      .toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
}

DateTime _getBucketKey(DateTime dt, ChartTimeBucket bucket) {
  switch (bucket) {
    case ChartTimeBucket.hourly:
      return DateTime(dt.year, dt.month, dt.day, dt.hour);
    case ChartTimeBucket.daily:
      return DateTime(dt.year, dt.month, dt.day);
    case ChartTimeBucket.weekly:
      // Start of week (Monday)
      final weekday = dt.weekday;
      return DateTime(dt.year, dt.month, dt.day - (weekday - 1));
  }
}

Map<DateTime, _BucketAccumulator> _fillEmptyBuckets(
  Map<DateTime, _BucketAccumulator> buckets,
  SalesDateRange dateRange,
  ChartTimeBucket bucket,
) {
  final result = Map<DateTime, _BucketAccumulator>.from(buckets);
  
  DateTime current = _getBucketKey(dateRange.start, bucket);
  final end = dateRange.end;
  
  while (current.isBefore(end)) {
    result.putIfAbsent(current, () => _BucketAccumulator());
    
    switch (bucket) {
      case ChartTimeBucket.hourly:
        current = current.add(const Duration(hours: 1));
        break;
      case ChartTimeBucket.daily:
        current = current.add(const Duration(days: 1));
        break;
      case ChartTimeBucket.weekly:
        current = current.add(const Duration(days: 7));
        break;
    }
  }
  
  return result;
}

class _BucketAccumulator {
  double grossRevenue = 0;
  double netRevenue = 0;
  int orderCount = 0;
  
  void addOrder(OrderData order) {
    grossRevenue += order.totalAmount;
    netRevenue += order.netAmount;
    orderCount++;
  }
}

// =============================================================================
// AI INSIGHT PROVIDER
// =============================================================================

/// Service provider for InsightService
final insightServiceProvider = Provider<InsightService>((ref) {
  return InsightService();
});

/// Generates AI insight from KPI data
final aiInsightProvider = FutureProvider.autoDispose<String>((ref) async {
  final kpiAsync = ref.watch(kpiDataProvider);
  
  return kpiAsync.when(
    data: (kpi) async {
      final insightData = InsightData.fromKpi(kpi);
      final service = ref.watch(insightServiceProvider);
      return service.generateInsight(insightData);
    },
    loading: () => Future.value('Analyzing your sales data...'),
    error: (e, _) => Future.value('Unable to generate insight at this time.'),
  );
});

/// Trigger to manually refresh insight
final insightRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// AI insight with manual refresh capability
final refreshableInsightProvider = FutureProvider.autoDispose<String>((ref) async {
  // Watch the refresh trigger to invalidate on demand
  ref.watch(insightRefreshTriggerProvider);
  
  final insight = await ref.watch(aiInsightProvider.future);
  return insight;
});

// =============================================================================
// CATEGORY SALES PROVIDER
// =============================================================================

/// Fetches sales breakdown by category
final categorySalesProvider = FutureProvider.autoDispose<List<CategorySales>>((ref) async {
  // Read synchronous state BEFORE the first await (Riverpod 2 rule).
  final dateRange = ref.watch(salesDateRangeProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  
  if (companyId == null) {
    throw Exception('No company selected');
  }
  
  final supabase = SupabaseService.client;
  
  // Fetch order items with category join, filtered by order date
  final data = await supabase
      .from('order_items')
      .select('''
        line_total,
        category_id,
        categories(name),
        orders!inner(created_at, status, company_id)
      ''')
      .eq('orders.company_id', companyId)
      .eq('orders.status', 'completed')
      .gte('orders.created_at', dateRange.start.toIso8601String())
      .lt('orders.created_at', dateRange.end.toIso8601String());
  
  if (data.isEmpty) {
    return [];
  }
  
  // Group by category
  final Map<String, _CategoryAccumulator> categories = {};
  double totalRevenue = 0;
  
  for (final row in data) {
    final categoryId = row['category_id'] as String? ?? 'uncategorized';
    final categoryData = row['categories'] as Map<String, dynamic>?;
    final categoryName = categoryData?['name'] as String? ?? 'Uncategorized';
    final lineTotal = (row['line_total'] as num?)?.toDouble() ?? 0;
    
    categories.putIfAbsent(categoryId, () => _CategoryAccumulator(categoryId, categoryName));
    categories[categoryId]!.revenue += lineTotal;
    totalRevenue += lineTotal;
  }
  
  // Convert to CategorySales with percentages
  final result = categories.values
      .map((acc) => CategorySales(
            categoryId: acc.categoryId,
            categoryName: acc.categoryName,
            revenue: acc.revenue,
            percentOfTotal: totalRevenue > 0 ? (acc.revenue / totalRevenue) * 100 : 0,
          ))
      .toList()
    ..sort((a, b) => b.revenue.compareTo(a.revenue));
  
  return result;
});

class _CategoryAccumulator {
  final String categoryId;
  final String categoryName;
  double revenue = 0;
  
  _CategoryAccumulator(this.categoryId, this.categoryName);
}

// =============================================================================
// TOP PRODUCTS PROVIDER
// =============================================================================

/// Fetches top 5 products by quantity sold
final topProductsProvider = FutureProvider.autoDispose<List<TopProduct>>((ref) async {
  // Read synchronous state BEFORE the first await (Riverpod 2 rule).
  final dateRange = ref.watch(salesDateRangeProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  
  if (companyId == null) {
    throw Exception('No company selected');
  }
  
  final supabase = SupabaseService.client;
  
  // Fetch order items with product join
  final data = await supabase
      .from('order_items')
      .select('''
        quantity,
        line_total,
        product_id,
        products(name),
        orders!inner(created_at, status, company_id)
      ''')
      .eq('orders.company_id', companyId)
      .eq('orders.status', 'completed')
      .gte('orders.created_at', dateRange.start.toIso8601String())
      .lt('orders.created_at', dateRange.end.toIso8601String());
  
  if (data.isEmpty) {
    return [];
  }
  
  // Group by product
  final Map<String, _ProductAccumulator> products = {};
  
  for (final row in data) {
    final productId = row['product_id'] as String? ?? '';
    final productData = row['products'] as Map<String, dynamic>?;
    final productName = productData?['name'] as String? ?? 'Unknown';
    final quantity = (row['quantity'] as num?)?.toInt() ?? 0;
    final lineTotal = (row['line_total'] as num?)?.toDouble() ?? 0;
    
    products.putIfAbsent(productId, () => _ProductAccumulator(productId, productName));
    products[productId]!.quantity += quantity;
    products[productId]!.revenue += lineTotal;
  }
  
  // Sort by quantity and take top 5
  final sorted = products.values.toList()
    ..sort((a, b) => b.quantity.compareTo(a.quantity));
  
  return sorted
      .take(5)
      .toList()
      .asMap()
      .entries
      .map((entry) => TopProduct(
            productId: entry.value.productId,
            productName: entry.value.productName,
            quantitySold: entry.value.quantity,
            revenue: entry.value.revenue,
            rank: entry.key + 1,
          ))
      .toList();
});

class _ProductAccumulator {
  final String productId;
  final String productName;
  int quantity = 0;
  double revenue = 0;
  
  _ProductAccumulator(this.productId, this.productName);
}

// =============================================================================
// PAYMENT SPLIT PROVIDER
// =============================================================================

/// Fetches payment method distribution
final paymentSplitProvider = FutureProvider.autoDispose<List<PaymentSplit>>((ref) async {
  // Read synchronous state BEFORE the first await (Riverpod 2 rule).
  final dateRange = ref.watch(salesDateRangeProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  
  if (companyId == null) {
    throw Exception('No company selected');
  }
  
  final supabase = SupabaseService.client;
  
  // Fetch orders grouped by payment method
  final data = await supabase
      .from('orders')
      .select('payment_method, total_amount')
      .eq('company_id', companyId)
      .eq('status', 'completed')
      .gte('created_at', dateRange.start.toIso8601String())
      .lt('created_at', dateRange.end.toIso8601String());
  
  if (data.isEmpty) {
    return [];
  }
  
  // Group by payment method
  final Map<String, double> methods = {};
  double totalAmount = 0;
  
  for (final row in data) {
    final method = row['payment_method'] as String? ?? 'cash';
    final amount = (row['total_amount'] as num?)?.toDouble() ?? 0;
    methods[method] = (methods[method] ?? 0) + amount;
    totalAmount += amount;
  }
  
  // Convert to PaymentSplit with percentages
  // Order: cash, card, online (for consistent UI)
  const methodOrder = ['cash', 'card', 'online'];
  final result = <PaymentSplit>[];
  
  for (final method in methodOrder) {
    final amount = methods[method];
    if (amount != null && amount > 0) {
      result.add(PaymentSplit(
        method: method,
        amount: amount,
        percentOfTotal: totalAmount > 0 ? (amount / totalAmount) * 100 : 0,
      ));
    }
  }
  
  // Add any other methods not in the standard list
  for (final entry in methods.entries) {
    if (!methodOrder.contains(entry.key) && entry.value > 0) {
      result.add(PaymentSplit(
        method: entry.key,
        amount: entry.value,
        percentOfTotal: totalAmount > 0 ? (entry.value / totalAmount) * 100 : 0,
      ));
    }
  }
  
  return result;
});
