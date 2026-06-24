import 'package:flutter/foundation.dart';

/// A product in the catalogue, mapped from the `products` table.
@immutable
class ProductModel {
  final String id;
  final String companyId;
  final String? providerId;
  final String name;
  final String? nameNormalized;
  final String? sku;
  final String? barcode;
  final String? description;
  final String? category;
  final String? categoryId;
  final String? categoryName;
  final String? subcategory;
  final double? unitPrice;
  final String? currency;
  final String? unitType;
  final double? taxRate;
  final bool trackInventory;
  final double? minStockLevel;
  final double? currentStock;
  final String? imageUrl;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProductModel({
    required this.id,
    required this.companyId,
    this.providerId,
    required this.name,
    this.nameNormalized,
    this.sku,
    this.barcode,
    this.description,
    this.category,
    this.categoryId,
    this.categoryName,
    this.subcategory,
    this.unitPrice,
    this.currency,
    this.unitType,
    this.taxRate,
    this.trackInventory = false,
    this.minStockLevel,
    this.currentStock,
    this.imageUrl,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      providerId: json['provider_id'] as String?,
      name: json['name'] as String? ?? '',
      nameNormalized: json['name_normalized'] as String?,
      sku: json['sku'] as String?,
      barcode: json['barcode'] as String?,
      description: json['description'] as String?,
        category: json['category'] as String?,
      categoryId: json['category_id'] as String?,
        categoryName: ((json['categories'] as Map<String, dynamic>?)?['name'] ??
            json['category_name']) as String? ??
          json['category'] as String?,
      subcategory: json['subcategory'] as String?,
      unitPrice: (json['unit_price'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      unitType: json['unit_type'] as String?,
      taxRate: (json['tax_rate'] as num?)?.toDouble(),
      trackInventory: json['track_inventory'] as bool? ?? false,
      minStockLevel: (json['min_stock_level'] as num?)?.toDouble(),
      currentStock: (json['current_stock'] as num?)?.toDouble(),
      imageUrl: json['image_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'company_id': companyId,
        'provider_id': providerId,
        'name': name,
        'sku': sku,
        'barcode': barcode,
        'description': description,
        'category': category,
        'category_id': categoryId,
        'category_name': categoryName,
        'subcategory': subcategory,
        'unit_price': unitPrice,
        'currency': currency,
        'unit_type': unitType,
        'tax_rate': taxRate,
        'track_inventory': trackInventory,
        'min_stock_level': minStockLevel,
        'current_stock': currentStock,
        'image_url': imageUrl,
        'is_active': isActive,
      };

  ProductModel copyWith({
    String? id,
    String? name,
    String? imageUrl,
    double? unitPrice,
    bool? isActive,
    double? currentStock,
  }) {
    return ProductModel(
      id: id ?? this.id,
      companyId: companyId,
      providerId: providerId,
      name: name ?? this.name,
      nameNormalized: nameNormalized,
      sku: sku,
      barcode: barcode,
      description: description,
      category: category,
      categoryId: categoryId,
      categoryName: categoryName,
      subcategory: subcategory,
      unitPrice: unitPrice ?? this.unitPrice,
      currency: currency,
      unitType: unitType,
      taxRate: taxRate,
      trackInventory: trackInventory,
      minStockLevel: minStockLevel,
      currentStock: currentStock ?? this.currentStock,
      imageUrl: imageUrl ?? this.imageUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ProductModel && id == other.id;

  @override
  int get hashCode => id.hashCode;

  String? get displayCategory => categoryName ?? category;
}
