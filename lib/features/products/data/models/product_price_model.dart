import 'package:flutter/foundation.dart';

/// One price observation for a product, mapped from the `product_prices` table.
@immutable
class ProductPriceModel {
  final String id;
  final String companyId;
  final String productId;
  final String? documentId;
  final String? documentItemId;
  final String? supplierId;
  final String? supplierName;
  final double price;
  final double? quantity;
  final String? unit;
  final DateTime? date;
  final DateTime observedAt;

  const ProductPriceModel({
    required this.id,
    required this.companyId,
    required this.productId,
    this.documentId,
    this.documentItemId,
    this.supplierId,
    this.supplierName,
    required this.price,
    this.quantity,
    this.unit,
    this.date,
    required this.observedAt,
  });

  factory ProductPriceModel.fromJson(Map<String, dynamic> json) {
    return ProductPriceModel(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      productId: json['product_id'] as String,
      documentId: json['document_id'] as String?,
      documentItemId: json['document_item_id'] as String?,
      supplierId: json['supplier_id'] as String?,
      supplierName:
          ((json['providers'] as Map<String, dynamic>?)?['name'] as String?) ??
              json['supplier_name'] as String?,
      price: (json['price'] as num).toDouble(),
      quantity: (json['quantity'] as num?)?.toDouble(),
      unit: json['unit'] as String?,
      date: json['date'] != null
          ? DateTime.tryParse(json['date'] as String)
          : null,
      observedAt: DateTime.parse(json['observed_at'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ProductPriceModel && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
