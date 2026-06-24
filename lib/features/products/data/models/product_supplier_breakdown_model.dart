import 'package:flutter/foundation.dart';

@immutable
class ProductSupplierBreakdownModel {
  final String? supplierId;
  final String supplierName;
  final int purchaseCount;
  final double averagePrice;
  final double latestPrice;
  final DateTime lastPurchasedAt;

  const ProductSupplierBreakdownModel({
    required this.supplierId,
    required this.supplierName,
    required this.purchaseCount,
    required this.averagePrice,
    required this.latestPrice,
    required this.lastPurchasedAt,
  });
}