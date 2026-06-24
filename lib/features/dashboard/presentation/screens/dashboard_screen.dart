import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/dashboard/data/models/dashboard_grid_metrics.dart';
import 'package:hospi_dash/features/dashboard/presentation/providers/dashboard_grid_provider.dart';
import 'package:hospi_dash/features/dashboard/presentation/viewmodels/dashboard_viewmodel.dart';
import 'package:hospi_dash/features/dashboard/presentation/widgets/dashboard_intelligence_grid.dart';
import 'package:hospi_dash/features/dashboard/presentation/widgets/intelligence_section.dart';
import 'package:hospi_dash/features/dashboard/presentation/widgets/recent_activity_section.dart';
import 'package:hospi_dash/features/dashboard/presentation/widgets/top_providers_section.dart';
import 'package:hospi_dash/features/review_center/presentation/widgets/review_notification_button.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/shared/ui/ui.dart';
import 'package:hospi_dash/widgets/expenses/expense_line_chart.dart';
import 'package:intl/intl.dart';

/// Dashboard screen — Quiet Hospitality editorial overview.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardViewModelProvider);
    final gridMetrics = ref.watch(dashboardGridMetricsProvider);
    final currencySymbol = ref.watch(currencySymbolProvider).valueOrNull ?? '€';
    final reviewOpenCount = gridMetrics.valueOrNull?.reviewOpenCount ?? 0;

    return AppScaffold(
      clampContent: false,
      backgroundColor: EditorialColors.background,
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(dashboardViewModelProvider.notifier).refresh(),
        color: EditorialColors.accent,
        backgroundColor: EditorialColors.surfaceContainerLowest,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.xs,
                    AppSpacing.screenPadding,
                    0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ReviewNotificationButton(
                        openCount: reviewOpenCount,
                        onTap: () => context.go(AppRoutes.reviewCenter),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Expense chart (already hosts dynamic header + period selector)
            const SliverToBoxAdapter(child: ExpenseLineChart()),

            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),

            SliverToBoxAdapter(
              child: DashboardIntelligenceGrid(
                metrics: gridMetrics,
                currencySymbol: currencySymbol,
                onExpensesTap: () => context.go(AppRoutes.expenses),
                onResultsTap: () => _showResultsSheet(
                  context,
                  gridMetrics.valueOrNull,
                  currencySymbol,
                ),
                onSalesTap: () => context.go(AppRoutes.sales),
                onDocumentsTap: () => context.go(AppRoutes.documents),
                onRetry: () => ref.invalidate(dashboardGridMetricsProvider),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),

            // Intelligence (category + top products)
            const SliverToBoxAdapter(child: IntelligenceSection()),

            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),

            // Top providers
            SliverToBoxAdapter(
              child: TopProvidersSection(
                providers: state.topProviders,
                onViewAll: () => context.go(AppRoutes.providers),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),

            // Recent activity
            SliverToBoxAdapter(
              child: RecentActivitySection(
                activities: state.recentActivity,
                onViewHistory: () => context.push(AppRoutes.documents),
              ),
            ),

            // Loading skeleton overlay when no data yet
            if (state.isLoading && !state.hasData)
              const SliverToBoxAdapter(child: _DashboardLoadingHint()),

            // Bottom clearance for floating nav + FAB.
            const SliverToBoxAdapter(child: SizedBox(height: 140)),
          ],
        ),
      ),
    );
  }

  void _showResultsSheet(
    BuildContext context,
    DashboardGridMetrics? metrics,
    String currencySymbol,
  ) {
    if (metrics == null) return;

    final formatter = NumberFormat.currency(
      locale: 'de_DE',
      symbol: currencySymbol,
      decimalDigits: 2,
    );

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: EditorialColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 34,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Results',
                    style: EditorialTypography.titleLarge.copyWith(
                      color: EditorialColors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Sales minus expenses for ${metrics.periodLabel.toLowerCase()}.',
                    style: EditorialTypography.bodyMedium.copyWith(
                      color: EditorialColors.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _ResultSheetRow(
                    label: 'Sales',
                    value: formatter.format(metrics.salesTotal),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ResultSheetRow(
                    label: 'Expenses',
                    value: formatter.format(metrics.expensesTotal),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ResultSheetRow(
                    label: 'Result',
                    value: formatter.format(metrics.resultTotal),
                    emphasize: true,
                    valueColor: metrics.resultTotal >= 0
                        ? EditorialColors.success
                        : EditorialColors.error,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ResultSheetRow extends StatelessWidget {
  const _ResultSheetRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: EditorialTypography.bodyMedium.copyWith(
            color: EditorialColors.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: EditorialTypography.titleMedium.copyWith(
            color: valueColor ?? EditorialColors.onSurface,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DashboardLoadingHint extends StatelessWidget {
  const _DashboardLoadingHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBlock.line(height: 14),
          SizedBox(height: 12),
          SkeletonBlock.box(width: double.infinity, height: 120),
          SizedBox(height: 12),
          SkeletonBlock.box(width: double.infinity, height: 120),
        ],
      ),
    );
  }
}
