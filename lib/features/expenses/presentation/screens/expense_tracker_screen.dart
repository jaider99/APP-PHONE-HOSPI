import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/expenses/data/models/expense_model.dart';
import 'package:hospi_dash/features/expenses/presentation/providers/expense_tracker_provider.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/shared/ui/ui.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EXPENSE TRACKER SCREEN
// ─────────────────────────────────────────────────────────────────────────────

/// Editorial category-level expense breakdown for the current month.
///
/// Data source: `documents` table — completed documents only.
/// No mock data, no hardcoded categories. Handles empty state gracefully.
class ExpenseTrackerScreen extends ConsumerWidget {
  const ExpenseTrackerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(expenseSummaryProvider);
    final currencySymbol =
        ref.watch(currencySymbolProvider).valueOrNull ?? '€';
    final now = DateTime.now();
    final monthLabel = DateFormat('MMMM yyyy').format(now);

    return AppScaffold(
      clampContent: false,
      topBar: AppTopBar(
        eyebrow: 'expenses',
        title: monthLabel,
      ),
      body: summaryAsync.when(
        loading: () => const _LoadingState(),
        error: (_, __) => ErrorState(
          message: "We couldn't load your expenses. Try again.",
          onRetry: () => ref.invalidate(expenseSummaryProvider),
        ),
        data: (summaries) {
          if (summaries.isEmpty) {
            return const AppEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No expenses yet',
              message:
                  'Upload your first invoice to start tracking spending by category.',
            );
          }

          final totalExpenses =
              summaries.fold<double>(0.0, (sum, s) => sum + s.total);

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(expenseSummaryProvider),
            color: EditorialColors.accent,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── Hero total ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.xl,
                    ),
                    child: FinancialValue(
                      amount: totalExpenses,
                      caption: 'total this month',
                      size: MetricSize.large,
                      locale: 'de_DE',
                      symbol: '$currencySymbol ',
                    ),
                  ),
                ),

                // ── Breakdown header ──────────────────────────────────
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      0,
                      AppSpacing.xl,
                      AppSpacing.md,
                    ),
                    child: SectionHeader(
                      eyebrow: 'breakdown',
                      title: 'Categories',
                    ),
                  ),
                ),

                // ── Category list (one card, hairline-divided rows) ──
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (int i = 0; i < summaries.length; i++)
                            _CategoryRow(
                              summary: summaries[i],
                              currencySymbol: currencySymbol,
                              showDivider: i < summaries.length - 1,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CATEGORY ROW
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.summary,
    required this.currencySymbol,
    required this.showDivider,
  });

  final CategorySummary summary;
  final String currencySymbol;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final dotColor = _parseColor(summary.color);
    final pctLabel = '${(summary.percentage * 100).toStringAsFixed(1)}%';

    return Container(
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: EditorialColors.hairline),
              ),
            )
          : null,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  summary.name,
                  style: EditorialTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                    color: EditorialColors.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FinancialValue(
                amount: summary.total,
                size: MetricSize.small,
                locale: 'de_DE',
                symbol: '$currencySymbol ',
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(label: pctLabel, tone: BadgeTone.neutral),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _ProgressBar(percentage: summary.percentage, color: dotColor),
        ],
      ),
    );
  }

  /// Converts a `#RRGGBB` or `#AARRGGBB` hex string to [Color].
  /// Falls back to the editorial accent when [hex] is null or malformed.
  static Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return EditorialColors.accent;
    final clean = hex.replaceFirst('#', '');
    final value = int.tryParse(
      clean.length == 6 ? 'FF$clean' : clean,
      radix: 16,
    );
    return value != null ? Color(value) : EditorialColors.accent;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROGRESS BAR (editorial: warm track + colored fill, 3px)
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.percentage,
    required this.color,
  });

  final double percentage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.maxWidth * percentage.clamp(0.0, 1.0);
        return Stack(
          children: [
            Container(
              height: 3,
              width: constraints.maxWidth,
              decoration: BoxDecoration(
                color: EditorialColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(EditorialRadius.full),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              height: 3,
              width: barWidth,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(EditorialRadius.full),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOADING STATE
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBlock.line(width: 120, height: 12),
          const SizedBox(height: AppSpacing.sm),
          SkeletonBlock.box(width: 240, height: 44),
          const SizedBox(height: AppSpacing.xxl),
          SkeletonBlock.line(width: 100, height: 12),
          const SizedBox(height: AppSpacing.md),
          for (int i = 0; i < 4; i++) ...[
            SkeletonBlock.box(width: double.infinity, height: 64),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}
