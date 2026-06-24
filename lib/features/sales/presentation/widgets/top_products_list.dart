import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/app_colors.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/sales/data/models/sales_models.dart';
import 'package:intl/intl.dart';

/// Top 5 products list by quantity sold
class TopProductsList extends StatelessWidget {
  final List<TopProduct> products;
  
  const TopProductsList({super.key, required this.products});
  
  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
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
            'Top Products',
            style: EditorialTypography.titleMedium.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Products list
          ...products.map((product) => _ProductRow(product: product)),
        ],
      ),
    );
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
            'Top Products',
            style: EditorialTypography.titleMedium.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 40,
                    color: AppColors.outlineVariant.withOpacity(0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No products sold in this period',
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

class _ProductRow extends StatelessWidget {
  final TopProduct product;
  
  const _ProductRow({required this.product});
  
  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(
      locale: 'es_ES',
      symbol: '€',
      decimalDigits: 2,
    );
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          // Rank number
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: product.rank <= 3
                  ? AppColors.secondaryContainer.withOpacity(0.3)
                  : AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              '#${product.rank}',
              style: EditorialTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w800,
                color: product.rank <= 3
                    ? AppColors.secondary
                    : AppColors.primary,
              ),
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Product info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.productName,
                  style: EditorialTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${product.quantitySold} units',
                      style: EditorialTypography.bodySmall.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '•',
                      style: EditorialTypography.bodySmall.copyWith(
                        color: AppColors.outlineVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      currencyFormat.format(product.revenue),
                      style: EditorialTypography.bodySmall.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Error state
class TopProductsListError extends StatelessWidget {
  final VoidCallback onRetry;
  
  const TopProductsListError({super.key, required this.onRetry});
  
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
            'Top Products',
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
                  'Failed to load products',
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
