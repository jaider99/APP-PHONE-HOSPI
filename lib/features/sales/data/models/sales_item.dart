class SalesItem {
  const SalesItem({
    required this.id,
    required this.companyId,
    required this.productName,
    this.saleId,
    this.salesImportId,
    this.normalizedProductName,
    this.quantity,
    this.unitPrice,
    this.totalAmount,
    this.category,
    this.posProductId,
    this.productId,
  });

  final String id;
  final String companyId;
  final String? saleId;
  final String? salesImportId;
  final String productName;
  final String? normalizedProductName;
  final double? quantity;
  final double? unitPrice;
  final double? totalAmount;
  final String? category;
  final String? posProductId;
  final String? productId;

  factory SalesItem.fromJson(Map<String, dynamic> json) {
    return SalesItem(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      saleId: json['sale_id'] as String?,
      salesImportId: json['sales_import_id'] as String?,
      productName: json['product_name'] as String? ?? 'Unknown item',
      normalizedProductName: json['normalized_product_name'] as String?,
      quantity: _readDouble(json['quantity']),
      unitPrice: _readDouble(json['unit_price']),
      totalAmount: _readDouble(json['total_amount']),
      category: json['category'] as String?,
      posProductId: json['pos_product_id'] as String?,
      productId: json['product_id'] as String?,
    );
  }
}

double? _readDouble(Object? value) => value is num ? value.toDouble() : null;