/// Supplier Intelligence data models.
/// These are plain Dart classes (no freezed/json_serializable) since they are
/// only used by the supplier intelligence feature and mapped from raw Supabase
/// JSON responses.

/// Aggregated supplier metrics from the v_supplier_intelligence view.
class SupplierIntelligence {
  const SupplierIntelligence({
    required this.id,
    required this.companyId,
    required this.name,
    this.category,
    required this.totalOrders,
    required this.totalSpent,
    this.lastOrderDate,
    required this.currentMonthSpent,
    required this.priorMonthSpent,
  });

  final String id;
  final String companyId;
  final String name;
  final String? category;
  final int totalOrders;
  final double totalSpent;
  final DateTime? lastOrderDate;
  final double currentMonthSpent;
  final double priorMonthSpent;

  /// Whether current-month > prior-month spend (positive trend).
  bool get isTrendUp => currentMonthSpent > priorMonthSpent;

  /// True when at least one month has spend data.
  bool get hasTrend =>
      currentMonthSpent > 0 || priorMonthSpent > 0;

  /// Two-character initials for the avatar.
  String get initials {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  factory SupplierIntelligence.fromJson(Map<String, dynamic> json) {
    return SupplierIntelligence(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      name: json['name'] as String? ?? '',
      category: json['category'] as String?,
      totalOrders: (json['total_orders'] as num?)?.toInt() ?? 0,
      totalSpent: (json['total_spent'] as num?)?.toDouble() ?? 0.0,
      lastOrderDate: json['last_order_date'] != null
          ? DateTime.tryParse(json['last_order_date'] as String)
          : null,
      currentMonthSpent:
          (json['current_month_spent'] as num?)?.toDouble() ?? 0.0,
      priorMonthSpent:
          (json['prior_month_spent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Spend breakdown for one expense category within a supplier.
class SupplierCategoryBreakdown {
  const SupplierCategoryBreakdown({
    required this.categoryName,
    required this.totalSpent,
    required this.orderCount,
  });

  final String categoryName;
  final double totalSpent;
  final int orderCount;
}

/// A single data point for the supplier's monthly spend chart.
class SupplierMonthlySpend {
  const SupplierMonthlySpend({
    required this.year,
    required this.month,
    required this.totalSpent,
    required this.orderCount,
  });

  final int year;
  final int month;
  final double totalSpent;
  final int orderCount;

  /// Human-readable month label, e.g. "Jan".
  String get monthLabel {
    const labels = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return labels[(month - 1).clamp(0, 11)];
  }
}

/// A recent document linked to a supplier.
class SupplierDocument {
  const SupplierDocument({
    required this.id,
    required this.documentType,
    required this.totalAmount,
    this.documentDate,
    this.documentNumber,
    this.currency,
  });

  final String id;
  final String documentType;
  final double totalAmount;
  final DateTime? documentDate;
  final String? documentNumber;
  final String? currency;

  factory SupplierDocument.fromJson(Map<String, dynamic> json) {
    return SupplierDocument(
      id: json['id'] as String,
      documentType: json['document_type'] as String? ?? 'unknown',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      documentDate: json['document_date'] != null
          ? DateTime.tryParse(json['document_date'] as String)
          : null,
      documentNumber: json['document_number'] as String?,
      currency: json['currency'] as String?,
    );
  }
}
