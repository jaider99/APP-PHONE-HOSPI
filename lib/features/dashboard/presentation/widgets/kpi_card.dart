import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/app_colors.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/core/theme/app_radius.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:intl/intl.dart';

/// KPI Card — flat, minimal, Trade Republic style
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.title,
    required this.amount,
    required this.subtitle,
    this.icon,
    this.iconBackgroundColor,
    this.isPositiveSubtitle = true,
    this.currency = '€',
  });

  final String title;
  final double amount;
  final String subtitle;
  final IconData? icon;
  final Color? iconBackgroundColor;
  final bool isPositiveSubtitle;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(
      locale: 'de_DE',
      symbol: '',
      decimalDigits: 2,
    );
    final formattedAmount = formatter.format(amount);
    final subtitleColor =
        isPositiveSubtitle ? AppColors.secondary : AppColors.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Small muted label
        Text(
          title.toUpperCase(),
          style: EditorialTypography.labelSmall.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: AppColors.outline,
          ),
        ),
        const SizedBox(height: 10),

        // Amount — number first, then symbol on the right
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                formattedAmount,
                style: EditorialTypography.headlineSmall.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: AppColors.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              currency,
              style: EditorialTypography.titleSmall.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // Subtitle
        Text(
          subtitle,
          style: EditorialTypography.bodySmall.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: subtitleColor,
          ),
        ),
      ],
    );
  }
}

/// Horizontal row of KPI stats — single white card with vertical divider
class KpiCardsRow extends StatelessWidget {
  const KpiCardsRow({
    super.key,
    required this.expenses,
    required this.expensesSubtitle,
    required this.netProfit,
    required this.netProfitSubtitle,
    this.isExpensesPositive = true,
    this.isNetProfitPositive = true,
    this.currency = '€',
  });

  final double expenses;
  final String expensesSubtitle;
  final double netProfit;
  final String netProfitSubtitle;
  final bool isExpensesPositive;
  final bool isNetProfitPositive;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: AppRadius.borderRadiusXxl,
        ),
        child: Row(
          children: [
            Expanded(
              child: KpiCard(
                title: 'Expenses',
                amount: expenses,
                subtitle: expensesSubtitle,
                isPositiveSubtitle: isExpensesPositive,
                currency: currency,
              ),
            ),
            // Vertical divider
            Container(
              width: 1,
              height: 56,
              color: AppColors.outlineVariant.withOpacity(0.3),
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            ),
            Expanded(
              child: KpiCard(
                title: 'Net Profit',
                amount: netProfit,
                subtitle: netProfitSubtitle,
                isPositiveSubtitle: isNetProfitPositive,
                currency: currency,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
