import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/app_colors.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:intl/intl.dart';

/// KPI card widget for displaying metrics with comparison delta
class KpiCard extends StatelessWidget {
  final String title;
  final double value;
  final double changePercent;
  final bool isCurrency;
  final bool isPositiveGood;
  
  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.changePercent,
    this.isCurrency = true,
    this.isPositiveGood = true,
  });
  
  @override
  Widget build(BuildContext context) {
    final isPositive = changePercent >= 0;
    final isGood = isPositiveGood ? isPositive : !isPositive;
    final deltaColor = isGood ? AppColors.secondary : EditorialColors.error;
    
    final currencyFormat = NumberFormat.currency(
      locale: 'es_ES',
      symbol: '€',
      decimalDigits: 2,
    );
    
    final compactFormat = NumberFormat.compact(locale: 'es_ES');
    
    String formattedValue;
    if (isCurrency) {
      formattedValue = currencyFormat.format(value);
    } else if (value >= 1000) {
      formattedValue = compactFormat.format(value);
    } else {
      formattedValue = value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1);
    }
    
    return Container(
      width: 180,
      height: 120,
      margin: const EdgeInsets.only(right: 16),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Title
          Text(
            title.toUpperCase(),
            style: EditorialTypography.labelSmall.copyWith(
              fontSize: 10,
              color: AppColors.primary,
              letterSpacing: 1.2,
            ),
          ),
          
          // Value and delta
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main value
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formattedValue,
                  style: EditorialTypography.headlineMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              
              const SizedBox(height: 4),
              
              // Delta badge
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPositive ? Icons.trending_up : Icons.trending_down,
                    size: 14,
                    color: deltaColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${isPositive ? '+' : ''}${changePercent.toStringAsFixed(1)}%',
                    style: EditorialTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: deltaColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Error state for KPI card
class KpiCardError extends StatelessWidget {
  final String title;
  
  const KpiCardError({super.key, required this.title});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 120,
      margin: const EdgeInsets.only(right: 16),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: EditorialTypography.labelSmall.copyWith(
              fontSize: 10,
              color: AppColors.primary,
              letterSpacing: 1.2,
            ),
          ),
          Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 16,
                color: AppColors.error.withOpacity(0.7),
              ),
              const SizedBox(width: 8),
              Text(
                "Couldn't load",
                style: EditorialTypography.bodySmall.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Empty state for KPI card
class KpiCardEmpty extends StatelessWidget {
  final String title;
  
  const KpiCardEmpty({super.key, required this.title});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 120,
      margin: const EdgeInsets.only(right: 16),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: EditorialTypography.labelSmall.copyWith(
              fontSize: 10,
              color: AppColors.primary,
              letterSpacing: 1.2,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '—',
                style: EditorialTypography.headlineMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface.withOpacity(0.3),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'No data',
                style: EditorialTypography.bodySmall.copyWith(
                  color: AppColors.primary.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
