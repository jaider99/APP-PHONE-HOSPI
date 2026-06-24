import 'package:flutter/foundation.dart';

/// Status of an expense record
enum ExpenseStatus {
  draft,
  completed;

  String get dbValue => name;

  static ExpenseStatus fromString(String? value) {
    if (value == 'completed') return ExpenseStatus.completed;
    return ExpenseStatus.draft;
  }
}

/// Persisted expense record
@immutable
class ExpenseModel {
  final String? id;
  final String companyId;
  final String? supplierName;
  final DateTime? documentDate;
  final double? totalAmount;
  final String currency;
  final String? categoryId;
  final String? documentType;
  final String? paymentMethod;
  final String? purchaseOrderId;
  final String? incident;
  final bool isPaid;
  final ExpenseStatus status;
  final String? documentId;
  final DateTime? createdAt;

  const ExpenseModel({
    this.id,
    required this.companyId,
    this.supplierName,
    this.documentDate,
    this.totalAmount,
    this.currency = 'EUR',
    this.categoryId,
    this.documentType,
    this.paymentMethod,
    this.purchaseOrderId,
    this.incident,
    this.isPaid = false,
    this.status = ExpenseStatus.draft,
    this.documentId,
    this.createdAt,
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    return ExpenseModel(
      id: json['id'] as String?,
      companyId: json['company_id'] as String,
      supplierName: json['supplier_name'] as String?,
      documentDate: json['document_date'] != null
          ? DateTime.tryParse(json['document_date'] as String)
          : null,
      totalAmount: (json['total_amount'] as num?)?.toDouble(),
      currency: json['currency'] as String? ?? 'EUR',
      categoryId: json['category_id'] as String?,
      documentType: json['document_type'] as String?,
      paymentMethod: json['payment_method'] as String?,
      purchaseOrderId: json['purchase_order_id'] as String?,
      incident: json['incident'] as String?,
      isPaid: json['is_paid'] as bool? ?? false,
      status: ExpenseStatus.fromString(json['status'] as String?),
      documentId: json['document_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'company_id': companyId,
      if (supplierName != null) 'supplier_name': supplierName,
      if (documentDate != null)
        'document_date': documentDate!.toIso8601String().split('T').first,
      if (totalAmount != null) 'total_amount': totalAmount,
      'currency': currency,
      if (categoryId != null) 'category_id': categoryId,
      if (documentType != null) 'document_type': documentType,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (purchaseOrderId != null) 'purchase_order_id': purchaseOrderId,
      if (incident != null) 'incident': incident,
      'is_paid': isPaid,
      'status': status.dbValue,
    };
  }
}

/// Category from the categories table
@immutable
class ExpenseCategory {
  final String id;
  final String name;
  final String? icon;
  final String? colorHex;
  final String? parentId;
  final int sortOrder;
  final bool isActive;

  const ExpenseCategory({
    required this.id,
    required this.name,
    this.icon,
    this.colorHex,
    this.parentId,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    return ExpenseCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String?,
      colorHex: json['color_hex'] as String?,
      parentId: json['parent_id'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

/// Category breakdown derived from the `documents` table.
///
/// Used by [ExpenseTrackerScreen] to show per-category totals with
/// their share of the total spend for the current period.
@immutable
class CategorySummary {
  final String categoryId;
  final String name;
  final double total;

  /// 0.0–1.0 fraction of total spend.
  final double percentage;

  /// Optional hex color string from the categories table, e.g. `#FF5733`.
  final String? color;

  const CategorySummary({
    required this.categoryId,
    required this.name,
    required this.total,
    required this.percentage,
    this.color,
  });
}

@immutable
class ExpenseCategorySummary {
  final String categoryId;
  final String categoryName;
  final String? colorHex;
  final int expenseCount;
  final double totalAmount;

  const ExpenseCategorySummary({
    required this.categoryId,
    required this.categoryName,
    this.colorHex,
    required this.expenseCount,
    required this.totalAmount,
  });
}
