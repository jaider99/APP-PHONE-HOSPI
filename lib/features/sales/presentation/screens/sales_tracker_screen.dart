import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/theme/app_colors.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/sales/data/models/sales_models.dart';
import 'package:hospi_dash/features/sales/data/providers/sales_providers.dart';
import 'package:hospi_dash/features/sales/presentation/widgets/ai_insight_banner.dart';
import 'package:hospi_dash/features/sales/presentation/widgets/category_list.dart';
import 'package:hospi_dash/features/sales/presentation/widgets/kpi_card.dart';
import 'package:hospi_dash/features/sales/presentation/widgets/payment_pill.dart';
import 'package:hospi_dash/features/sales/presentation/widgets/revenue_chart.dart';
import 'package:hospi_dash/features/sales/presentation/widgets/skeleton_loader.dart';
import 'package:hospi_dash/features/sales/presentation/widgets/top_products_list.dart';

/// Sales Tracker Screen - Multi-tenant sales analytics dashboard
/// Displays KPIs, revenue chart, AI insights, category breakdown,
/// top products, and payment method distribution
class SalesTrackerScreen extends ConsumerStatefulWidget {
  const SalesTrackerScreen({super.key});

  @override
  ConsumerState<SalesTrackerScreen> createState() => _SalesTrackerScreenState();
}

class _SalesTrackerScreenState extends ConsumerState<SalesTrackerScreen> {
  bool _isRefreshingInsight = false;

  @override
  Widget build(BuildContext context) {
    final dateRange = ref.watch(salesDateRangeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          color: AppColors.secondary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 1. Header + Date Range Picker
              SliverToBoxAdapter(
                child: _buildHeader(dateRange),
              ),

              // 2. KPI Cards - Horizontal Scroll
              SliverToBoxAdapter(
                child: _buildKpiSection(),
              ),

              // 3. Revenue Chart
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                  child: _buildRevenueChart(dateRange),
                ),
              ),

              // 4. AI Insight Banner
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: _buildAiInsight(),
                ),
              ),

              // 5. Sales by Category
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: _buildCategorySection(),
                ),
              ),

              // 6. Top Products
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: _buildTopProductsSection(),
                ),
              ),

              // 7. Payment Split
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: _buildPaymentSection(),
                ),
              ),

              // Bottom padding for nav
              const SliverToBoxAdapter(
                child: SizedBox(height: 80),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // HEADER & DATE PICKER
  // ============================================================

  Widget _buildHeader(SalesDateRange dateRange) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            'Sales',
            style: EditorialTypography.headlineMedium.copyWith(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.onSurface,
            ),
          ),

          const SizedBox(height: 20),

          // Date range picker pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: DateRangeType.values.map((type) {
                final isSelected = dateRange.type == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _DateRangePill(
                    label: _getDateRangeLabel(type),
                    isSelected: isSelected,
                    onTap: () => _selectDateRange(type),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _getDateRangeLabel(DateRangeType type) {
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

  void _selectDateRange(DateRangeType type) async {
    if (type == DateRangeType.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange: DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 7)),
          end: DateTime.now(),
        ),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: AppColors.secondary,
                onPrimary: Colors.white,
                surface: AppColors.surfaceContainerLowest,
                onSurface: AppColors.onSurface,
              ),
            ),
            child: child!,
          );
        },
      );

      if (picked != null) {
        ref.read(salesDateRangeProvider.notifier).state = SalesDateRange.fromType(
          DateRangeType.custom,
          customStart: picked.start,
          customEnd: picked.end,
        );
      }
    } else {
      ref.read(salesDateRangeProvider.notifier).state = SalesDateRange.fromType(type);
    }
  }

  // ============================================================
  // KPI SECTION
  // ============================================================

  Widget _buildKpiSection() {
    final kpiAsync = ref.watch(kpiDataProvider);

    return SizedBox(
      height: 140,
      child: kpiAsync.when(
        loading: () => ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          itemCount: 4,
          itemBuilder: (context, index) => const KpiCardSkeleton(),
        ),
        error: (_, __) => ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: const [
            KpiCardError(title: 'Net Revenue'),
            KpiCardError(title: 'Total Orders'),
            KpiCardError(title: 'Avg. Order Value'),
            KpiCardError(title: 'Covers'),
          ],
        ),
        data: (kpi) {
          if (kpi.totalOrders == 0) {
            return ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: const [
                KpiCardEmpty(title: 'Net Revenue'),
                KpiCardEmpty(title: 'Total Orders'),
                KpiCardEmpty(title: 'Avg. Order Value'),
                KpiCardEmpty(title: 'Covers'),
              ],
            );
          }

          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            children: [
              KpiCard(
                title: 'Net Revenue',
                value: kpi.netRevenue,
                changePercent: kpi.revenueChangePercent,
                isCurrency: true,
              ),
              KpiCard(
                title: 'Total Orders',
                value: kpi.totalOrders.toDouble(),
                changePercent: kpi.ordersChangePercent,
                isCurrency: false,
              ),
              KpiCard(
                title: 'Avg. Order Value',
                value: kpi.avgOrderValue,
                changePercent: kpi.avgChangePercent,
                isCurrency: true,
              ),
              KpiCard(
                title: 'Covers',
                value: kpi.covers.toDouble(),
                changePercent: kpi.coversChangePercent,
                isCurrency: false,
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // REVENUE CHART
  // ============================================================

  Widget _buildRevenueChart(SalesDateRange dateRange) {
    final chartAsync = ref.watch(revenueChartDataProvider);

    return chartAsync.when(
      loading: () => const ChartSkeleton(),
      error: (_, __) => RevenueChartError(
        onRetry: () => ref.invalidate(revenueChartDataProvider),
      ),
      data: (data) => RevenueChart(
        data: data,
        timeBucket: dateRange.timeBucket,
      ),
    );
  }

  // ============================================================
  // AI INSIGHT
  // ============================================================

  Widget _buildAiInsight() {
    final insightAsync = ref.watch(refreshableInsightProvider);

    return insightAsync.when(
      loading: () => const InsightSkeleton(),
      error: (_, __) => AiInsightError(
        onRetry: _refreshInsight,
      ),
      data: (insight) => AiInsightBanner(
        insight: insight,
        onRefresh: _refreshInsight,
        isRefreshing: _isRefreshingInsight,
      ),
    );
  }

  void _refreshInsight() {
    setState(() => _isRefreshingInsight = true);
    ref.read(insightRefreshTriggerProvider.notifier).state++;
    ref.invalidate(refreshableInsightProvider);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _isRefreshingInsight = false);
      }
    });
  }

  // ============================================================
  // CATEGORY SECTION
  // ============================================================

  Widget _buildCategorySection() {
    final categoryAsync = ref.watch(categorySalesProvider);

    return categoryAsync.when(
      loading: () => Container(
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
            Text(
              'Sales by Category',
              style: EditorialTypography.titleMedium.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 20),
            const CategoryListSkeleton(),
          ],
        ),
      ),
      error: (_, __) => CategoryListError(
        onRetry: () => ref.invalidate(categorySalesProvider),
      ),
      data: (categories) => CategoryList(categories: categories),
    );
  }

  // ============================================================
  // TOP PRODUCTS SECTION
  // ============================================================

  Widget _buildTopProductsSection() {
    final productsAsync = ref.watch(topProductsProvider);

    return productsAsync.when(
      loading: () => Container(
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
            Text(
              'Top Products',
              style: EditorialTypography.titleMedium.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 20),
            const TopProductsSkeleton(),
          ],
        ),
      ),
      error: (_, __) => TopProductsListError(
        onRetry: () => ref.invalidate(topProductsProvider),
      ),
      data: (products) => TopProductsList(products: products),
    );
  }

  // ============================================================
  // PAYMENT SECTION
  // ============================================================

  Widget _buildPaymentSection() {
    final paymentAsync = ref.watch(paymentSplitProvider);

    return paymentAsync.when(
      loading: () => Container(
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
            Text(
              'Payment Methods',
              style: EditorialTypography.titleMedium.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 20),
            const PaymentPillSkeleton(),
          ],
        ),
      ),
      error: (_, __) => PaymentPillError(
        onRetry: () => ref.invalidate(paymentSplitProvider),
      ),
      data: (payments) => PaymentPill(payments: payments),
    );
  }

  // ============================================================
  // REFRESH
  // ============================================================

  Future<void> _refreshAll() async {
    ref.invalidate(kpiDataProvider);
    ref.invalidate(revenueChartDataProvider);
    ref.invalidate(refreshableInsightProvider);
    ref.invalidate(categorySalesProvider);
    ref.invalidate(topProductsProvider);
    ref.invalidate(paymentSplitProvider);

    // Wait a bit for providers to refresh
    await Future.delayed(const Duration(milliseconds: 500));
  }
}

// ============================================================
// DATE RANGE PILL WIDGET
// ============================================================

class _DateRangePill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DateRangePill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.onSurface : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          label,
          style: EditorialTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w500,
            color: isSelected ? AppColors.surfaceContainerLowest : AppColors.primary,
          ),
        ),
      ),
    );
  }
}
