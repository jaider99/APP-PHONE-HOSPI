import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/app_colors.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/sales/data/models/sales_models.dart';
import 'package:intl/intl.dart';

/// Sales breakdown by category with progress bars
class CategoryList extends StatefulWidget {
  final List<CategorySales> categories;
  final int initialDisplayCount;
  
  const CategoryList({
    super.key,
    required this.categories,
    this.initialDisplayCount = 8,
  });
  
  @override
  State<CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends State<CategoryList> {
  bool _showAll = false;
  
  @override
  Widget build(BuildContext context) {
    if (widget.categories.isEmpty) {
      return _buildEmptyState();
    }
    
    final displayList = _showAll
        ? widget.categories
        : widget.categories.take(widget.initialDisplayCount).toList();
    
    final hasMore = widget.categories.length > widget.initialDisplayCount;
    
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
            'Sales by Category',
            style: EditorialTypography.titleMedium.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Category list
          ...displayList.map((category) => _CategoryRow(category: category)),
          
          // Show all button
          if (hasMore && !_showAll) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => setState(() => _showAll = true),
                child: Text(
                  'Show all (${widget.categories.length})',
                  style: EditorialTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondary,
                  ),
                ),
              ),
            ),
          ],
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
            'Sales by Category',
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
                    Icons.category_outlined,
                    size: 40,
                    color: AppColors.outlineVariant.withOpacity(0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No category data for this period',
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

class _CategoryRow extends StatelessWidget {
  final CategorySales category;
  
  const _CategoryRow({required this.category});
  
  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(
      locale: 'es_ES',
      symbol: '€',
      decimalDigits: 2,
    );
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name and amount row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  category.categoryName,
                  style: EditorialTypography.bodyMedium.copyWith(
                    color: AppColors.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 16),
              Row(
                children: [
                  Text(
                    currencyFormat.format(category.revenue),
                    style: EditorialTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${category.percentOfTotal.toStringAsFixed(1)}%',
                    style: EditorialTypography.bodySmall.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(
                  height: 8,
                  width: double.infinity,
                  color: AppColors.surfaceContainerLow,
                ),
                FractionallySizedBox(
                  widthFactor: category.percentOfTotal / 100,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.secondaryContainer.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4),
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

/// Error state
class CategoryListError extends StatelessWidget {
  final VoidCallback onRetry;
  
  const CategoryListError({super.key, required this.onRetry});
  
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
            'Sales by Category',
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
                  'Failed to load categories',
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
