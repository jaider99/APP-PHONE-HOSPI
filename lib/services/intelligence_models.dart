import 'package:flutter/foundation.dart';

/// Aggregated intelligence for a single expense category.
/// Mapped from the `v_category_intelligence` view.
@immutable
class CategoryIntelligence {
  const CategoryIntelligence({
    required this.id,
    required this.companyId,
    required this.name,
    this.colorHex,
    this.icon,
    required this.totalDocuments,
    required this.totalSpent,
    required this.currentMonthSpent,
    required this.priorMonthSpent,
    this.lastDocumentDate,
  });

  final String id;
  final String companyId;
  final String name;
  final String? colorHex;
  final String? icon;
  final int totalDocuments;
  final double totalSpent;
  final double currentMonthSpent;
  final double priorMonthSpent;
  final DateTime? lastDocumentDate;

  /// Month-over-month delta (positive = spending increased).
  double get monthDelta => currentMonthSpent - priorMonthSpent;

  /// True when current month spend exceeds prior month.
  bool get isTrendUp => currentMonthSpent > priorMonthSpent;

  /// True when at least one month has spend data.
  bool get hasTrend => currentMonthSpent > 0 || priorMonthSpent > 0;

  factory CategoryIntelligence.fromJson(Map<String, dynamic> json) {
    return CategoryIntelligence(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      name: json['name'] as String? ?? 'Unknown',
      colorHex: json['color_hex'] as String?,
      icon: json['icon'] as String?,
      totalDocuments: (json['total_documents'] as num?)?.toInt() ?? 0,
      totalSpent: (json['total_spent'] as num?)?.toDouble() ?? 0.0,
      currentMonthSpent:
          (json['current_month_spent'] as num?)?.toDouble() ?? 0.0,
      priorMonthSpent:
          (json['prior_month_spent'] as num?)?.toDouble() ?? 0.0,
      lastDocumentDate: json['last_document_date'] != null
          ? DateTime.tryParse(json['last_document_date'] as String)
          : null,
    );
  }
}

/// Aggregated intelligence for a single product.
/// Mapped from the `v_top_products_by_spend` view.
@immutable
class ProductIntelligenceSummary {
  const ProductIntelligenceSummary({
    required this.productId,
    required this.companyId,
    required this.productName,
    this.imageUrl,
    this.categoryId,
    this.categoryName,
    this.categoryColor,
    this.supplierId,
    this.supplierName,
    required this.totalQuantity,
    required this.totalSpent,
    required this.currentMonthSpent,
    required this.priorMonthSpent,
    this.latestPrice,
    this.minPrice,
    this.maxPrice,
    required this.purchaseCount,
  });

  final String productId;
  final String companyId;
  final String productName;
  final String? imageUrl;
  final String? categoryId;
  final String? categoryName;
  final String? categoryColor;
  final String? supplierId;
  final String? supplierName;
  final double totalQuantity;
  final double totalSpent;
  final double currentMonthSpent;
  final double priorMonthSpent;
  final double? latestPrice;
  final double? minPrice;
  final double? maxPrice;
  final int purchaseCount;

  /// Month-over-month delta (positive = more spend this month).
  double get monthDelta => currentMonthSpent - priorMonthSpent;

  /// Price variance as a percentage of min price (0 if no min price).
  double get priceVariancePct {
    if (minPrice == null || minPrice == 0 || maxPrice == null) return 0;
    return ((maxPrice! - minPrice!) / minPrice!) * 100;
  }

  factory ProductIntelligenceSummary.fromJson(Map<String, dynamic> json) {
    return ProductIntelligenceSummary(
      productId: json['product_id'] as String,
      companyId: json['company_id'] as String,
      productName: json['product_name'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      categoryId: json['category_id'] as String?,
      categoryName: json['category_name'] as String?,
      categoryColor: json['category_color'] as String?,
      supplierId: json['supplier_id'] as String?,
      supplierName: json['supplier_name'] as String?,
      totalQuantity: (json['total_quantity'] as num?)?.toDouble() ?? 0.0,
      totalSpent: (json['total_spent'] as num?)?.toDouble() ?? 0.0,
      currentMonthSpent:
          (json['current_month_spent'] as num?)?.toDouble() ?? 0.0,
      priorMonthSpent:
          (json['prior_month_spent'] as num?)?.toDouble() ?? 0.0,
      latestPrice: (json['latest_price'] as num?)?.toDouble(),
      minPrice: (json['min_price'] as num?)?.toDouble(),
      maxPrice: (json['max_price'] as num?)?.toDouble(),
      purchaseCount: (json['purchase_count'] as num?)?.toInt() ?? 0,
    );
  }
}
