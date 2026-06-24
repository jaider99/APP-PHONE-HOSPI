import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/providers/expense_chart_provider.dart';

/// KPI card row + undated-documents banner.
///
/// Shows:
///  - EXPENSES total for the selected period (from [document_date])
///  - VAT total for the same period
///  - A banner when completed documents have no extracted date and are
///    therefore excluded from the chart.
///
/// Watches [chartKpiProvider] and [currencySymbolProvider] internally.
class ChartKpiCards extends ConsumerWidget {
  const ChartKpiCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpiAsync = ref.watch(chartKpiProvider);
    final currency = ref.watch(currencySymbolProvider).valueOrNull ?? '€';

    final kpi = kpiAsync.valueOrNull;
    final isLoading = kpiAsync.isLoading && kpi == null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  isLoading: isLoading,
                  label: 'EXPENSES',
                  amount: kpi?.totalExpenses ?? 0,
                  currency: currency,
                  subtitle: kpi?.comparisonLabel ?? '',
                  subtitleColor: kpi?.comparisonColor ??
                      EditorialColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _KpiCard(
                  isLoading: isLoading,
                  label: 'VAT',
                  amount: kpi?.totalTax ?? 0,
                  currency: currency,
                  subtitle: kpi == null
                      ? ''
                      : '${kpi.documentCount} document${kpi.documentCount == 1 ? '' : 's'} in period',
                  subtitleColor: EditorialColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if ((kpi?.undatedCount ?? 0) > 0) ...[
            const SizedBox(height: AppSpacing.md),
            _UndatedDocumentsBanner(count: kpi!.undatedCount),
          ],
        ],
      ),
    );
  }
}

class _UndatedDocumentsBanner extends StatelessWidget {
  const _UndatedDocumentsBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7D6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE08A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: Color(0xFF7B6000),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$count document${count == 1 ? '' : 's'} '
              '${count == 1 ? 'has' : 'have'} no invoice date and '
              '${count == 1 ? 'is' : 'are'} excluded from the chart periods.',
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF7B6000),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.isLoading,
    required this.label,
    required this.amount,
    required this.currency,
    required this.subtitle,
    required this.subtitleColor,
  });

  final bool isLoading;
  final String label;
  final double amount;
  final String currency;
  final String subtitle;
  final Color subtitleColor;

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(
      locale: 'de_DE',
      symbol: '',
      decimalDigits: 2,
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EditorialColors.hairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: EditorialTypography.labelSmall.copyWith(
              color: EditorialColors.onSurfaceVariant,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (isLoading)
            Container(
              height: 22,
              width: 80,
              decoration: BoxDecoration(
                color: EditorialColors.surfaceContainer,
                borderRadius: BorderRadius.circular(4),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    formatter.format(amount),
                    style: EditorialTypography.headlineSmall.copyWith(
                      color: EditorialColors.onSurface,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  currency,
                  style: EditorialTypography.bodyMedium.copyWith(
                    color: EditorialColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 6),
          if (!isLoading && subtitle.isNotEmpty)
            Text(
              subtitle,
              style: EditorialTypography.bodySmall.copyWith(
                color: subtitleColor,
                fontSize: 11.5,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}