import 'package:flutter/foundation.dart';

import 'product_model.dart';

enum ProductPriceDirection { up, down, stable, unknown }

enum ProductPriceSeverity { stable, watch, high, critical, noPrice }

enum ProductCatalogueFilter { all, priceChanges, needsReview, uncategorized }

@immutable
class ProductIntelligenceSummaryModel {
  final ProductModel product;
  final double? latestPrice;
  final double? previousPrice;
  final double? averagePrice30d;
  final double? averagePrice90d;
  final double? variationVsPreviousPercent;
  final double? variationVsAveragePercent;
  final ProductPriceDirection direction;
  final ProductPriceSeverity severity;
  final String? supplierName;
  final DateTime? lastPurchasedAt;
  final int purchaseCount;
  final bool needsReview;
  final String? reasoning;

  const ProductIntelligenceSummaryModel({
    required this.product,
    required this.direction,
    required this.severity,
    required this.purchaseCount,
    this.latestPrice,
    this.previousPrice,
    this.averagePrice30d,
    this.averagePrice90d,
    this.variationVsPreviousPercent,
    this.variationVsAveragePercent,
    this.supplierName,
    this.lastPurchasedAt,
    this.needsReview = false,
    this.reasoning,
  });

  String get id => product.id;
  String get name => product.name;
  String? get category => product.displayCategory;
  String? get currency => product.currency;

  bool get hasPriceChange {
    final value = variationVsPreviousPercent?.abs();
    return value != null && value >= 5;
  }
}
