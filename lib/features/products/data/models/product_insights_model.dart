import 'package:flutter/foundation.dart';

@immutable
class ProductInsightsModel {
  final double latestPrice;
  final double averagePrice;
  final double minimumPrice;
  final double maximumPrice;
  final double? changeFromPrevious;
  final double? changePercentFromPrevious;
  final int purchaseCount;
  final int supplierCount;

  const ProductInsightsModel({
    required this.latestPrice,
    required this.averagePrice,
    required this.minimumPrice,
    required this.maximumPrice,
    required this.changeFromPrevious,
    required this.changePercentFromPrevious,
    required this.purchaseCount,
    required this.supplierCount,
  });
}