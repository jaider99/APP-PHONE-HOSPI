import 'package:flutter/foundation.dart';

@immutable
class ProductPriceStatsModel {
  final String companyId;
  final String productId;
  final int sampleCount;
  final int supplierCount;
  final double? averagePrice;
  final double? medianPrice;
  final double? stddevPrice;
  final double? minPrice;
  final double? maxPrice;
  final double? lastPrice;
  final String? lastSupplierId;
  final DateTime? lastPurchaseDate;
  final double? averageQuantity;
  final double? stddevQuantity;
  final double? thirtyDayAverage;
  final double? priorThirtyDayAverage;
  final double? trendPercent;
  final double? baselinePrice;
  final DateTime? baselineApprovedAt;
  final DateTime updatedAt;

  const ProductPriceStatsModel({
    required this.companyId,
    required this.productId,
    required this.sampleCount,
    required this.supplierCount,
    required this.updatedAt,
    this.averagePrice,
    this.medianPrice,
    this.stddevPrice,
    this.minPrice,
    this.maxPrice,
    this.lastPrice,
    this.lastSupplierId,
    this.lastPurchaseDate,
    this.averageQuantity,
    this.stddevQuantity,
    this.thirtyDayAverage,
    this.priorThirtyDayAverage,
    this.trendPercent,
    this.baselinePrice,
    this.baselineApprovedAt,
  });

  factory ProductPriceStatsModel.fromJson(Map<String, dynamic> json) {
    return ProductPriceStatsModel(
      companyId: json['company_id'] as String,
      productId: json['product_id'] as String,
      sampleCount: json['sample_count'] as int? ?? 0,
      supplierCount: json['supplier_count'] as int? ?? 0,
      averagePrice: (json['avg_price'] as num?)?.toDouble(),
      medianPrice: (json['median_price'] as num?)?.toDouble(),
      stddevPrice: (json['stddev_price'] as num?)?.toDouble(),
      minPrice: (json['min_price'] as num?)?.toDouble(),
      maxPrice: (json['max_price'] as num?)?.toDouble(),
      lastPrice: (json['last_price'] as num?)?.toDouble(),
      lastSupplierId: json['last_supplier_id'] as String?,
      lastPurchaseDate: json['last_purchase_date'] != null
          ? DateTime.tryParse(json['last_purchase_date'] as String)
          : null,
      averageQuantity: (json['avg_quantity'] as num?)?.toDouble(),
      stddevQuantity: (json['stddev_quantity'] as num?)?.toDouble(),
      thirtyDayAverage: (json['thirty_day_avg'] as num?)?.toDouble(),
      priorThirtyDayAverage: (json['prior_thirty_day_avg'] as num?)?.toDouble(),
      trendPercent: (json['trend_percent'] as num?)?.toDouble(),
      baselinePrice: (json['baseline_price'] as num?)?.toDouble(),
      baselineApprovedAt: json['baseline_approved_at'] != null
          ? DateTime.tryParse(json['baseline_approved_at'] as String)
          : null,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
