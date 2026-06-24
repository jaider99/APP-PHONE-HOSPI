import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/app_colors.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:intl/intl.dart';

/// Hero metric widget for the main revenue display
/// Editorial style with extreme typography scale
class HeroMetric extends StatelessWidget {
  const HeroMetric({
    super.key,
    required this.amount,
    required this.periodLabel,
    required this.percentageChange,
    required this.isPositive,
    this.currency = '€',
    this.label = 'TOTAL REVENUE',
  });

  final double amount;
  final String periodLabel;
  final double percentageChange;
  final bool isPositive;
  final String currency;
  final String label;

  @override
  Widget build(BuildContext context) {
    // Format amount with European style (. as thousand separator, , as decimal)
    final formatter = NumberFormat.currency(
      locale: 'de_DE',
      symbol: '',
      decimalDigits: 2,
    );
    final formattedAmount = formatter.format(amount);

    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.sm,
        bottom: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Small muted label
          Text(
            '$label · $periodLabel'.toUpperCase(),
            style: EditorialTypography.labelSmall.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.0,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: 8),

          // Large bold amount — Trade Republic style: number then symbol
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formattedAmount,
                style: EditorialTypography.headlineMedium.copyWith(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  letterSpacing: -1.5,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                currency,
                style: EditorialTypography.headlineMedium.copyWith(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  letterSpacing: -0.5,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),

          // Inline delta — ▲ 17,76 € (Trade Republic style)
          if (percentageChange != 0) ...[              
            const SizedBox(height: 8),
            _InlineDelta(
              percentage: percentageChange,
              isPositive: isPositive,
            ),
          ],
        ],
      ),
    );
  }
}

/// Inline delta indicator — Trade Republic style
/// Shows ▲ +17,6% in green or ▼ -5,2% in red on its own line
class _InlineDelta extends StatelessWidget {
  const _InlineDelta({
    required this.percentage,
    required this.isPositive,
  });

  final double percentage;
  final bool isPositive;

  @override
  Widget build(BuildContext context) {
    final color = isPositive ? AppColors.secondary : AppColors.error;
    final arrow = isPositive ? '▲' : '▼';
    final sign = isPositive ? '+' : '';
    final displayPct = percentage.abs().toStringAsFixed(1);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$arrow $sign$displayPct%',
          style: EditorialTypography.bodyMedium.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
