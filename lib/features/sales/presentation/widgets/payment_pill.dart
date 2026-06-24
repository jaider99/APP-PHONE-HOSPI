import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/app_colors.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/sales/data/models/sales_models.dart';
import 'package:intl/intl.dart';

/// Payment method distribution pill with proportional segments
class PaymentPill extends StatelessWidget {
  final List<PaymentSplit> payments;
  
  const PaymentPill({super.key, required this.payments});
  
  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return _buildEmptyState();
    }
    
    return Container(
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
          // Header
          Text(
            'Payment Methods',
            style: EditorialTypography.titleMedium.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Pill bar
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 48,
              child: Row(
                children: payments.map((payment) {
                  return Expanded(
                    flex: (payment.percentOfTotal * 10).round().clamp(1, 1000),
                    child: Container(
                      color: _getMethodColor(payment.method),
                      alignment: Alignment.center,
                      child: payment.percentOfTotal > 15
                          ? Text(
                              '${payment.percentOfTotal.toStringAsFixed(0)}%',
                              style: EditorialTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                color: _getMethodTextColor(payment.method),
                              ),
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Legend chips
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: payments.map((payment) {
              return _PaymentChip(payment: payment);
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  Color _getMethodColor(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return AppColors.surfaceContainerLow;
      case 'card':
        return AppColors.onSurface;
      case 'online':
        return AppColors.secondary;
      default:
        return AppColors.primary;
    }
  }
  
  Color _getMethodTextColor(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return AppColors.onSurface;
      case 'card':
        return AppColors.surfaceContainerLowest;
      case 'online':
        return AppColors.surfaceContainerLowest;
      default:
        return AppColors.surfaceContainerLowest;
    }
  }
  
  Widget _buildEmptyState() {
    return Container(
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
          const SizedBox(height: 24),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Icon(
                    Icons.payments_outlined,
                    size: 40,
                    color: AppColors.outlineVariant.withOpacity(0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No payment data for this period',
                    style: EditorialTypography.bodyMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  final PaymentSplit payment;
  
  const _PaymentChip({required this.payment});
  
  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(
      locale: 'es_ES',
      symbol: '€',
      decimalDigits: 0,
    );
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _getChipColor(payment.method),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                payment.displayName,
                style: EditorialTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            currencyFormat.format(payment.amount),
            style: EditorialTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
  
  Color _getChipColor(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return AppColors.surfaceContainerHigh;
      case 'card':
        return AppColors.onSurface;
      case 'online':
        return AppColors.secondary;
      default:
        return AppColors.primary;
    }
  }
}

/// Error state
class PaymentPillError extends StatelessWidget {
  final VoidCallback onRetry;
  
  const PaymentPillError({super.key, required this.onRetry});
  
  @override
  Widget build(BuildContext context) {
    return Container(
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
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 40,
                  color: AppColors.error.withOpacity(0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'Failed to load payment data',
                  style: EditorialTypography.bodyMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                TextButton(
                  onPressed: onRetry,
                  child: Text(
                    'Retry',
                    style: EditorialTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
