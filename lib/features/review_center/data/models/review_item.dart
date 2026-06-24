enum ReviewType {
  lowConfidenceField,
  duplicateDocument,
  missingCategory,
  failedExtraction,
  productMatchReview,
  supplierMatchReview,
  priceAnomaly,
  priceVariation,
  baselineReview,
  documentNeedsReview,
  unknownSupplier,
  unknownDocumentType,
  failedSalesImport,
  lowConfidenceSalesReport,
  missingSalesPeriod,
  posConnectionIssue,
  unknown;

  static ReviewType fromJson(String? value) => switch (value) {
        'low_confidence_field' => ReviewType.lowConfidenceField,
        'duplicate_document' => ReviewType.duplicateDocument,
        'missing_category' => ReviewType.missingCategory,
        'failed_extraction' => ReviewType.failedExtraction,
        'product_match_review' => ReviewType.productMatchReview,
        'supplier_match_review' => ReviewType.supplierMatchReview,
        'price_anomaly' => ReviewType.priceAnomaly,
        'price_variation' => ReviewType.priceVariation,
        'baseline_review' => ReviewType.baselineReview,
        'document_needs_review' => ReviewType.documentNeedsReview,
        'unknown_supplier' => ReviewType.unknownSupplier,
        'unknown_document_type' => ReviewType.unknownDocumentType,
        'failed_sales_import' => ReviewType.failedSalesImport,
        'low_confidence_sales_report' => ReviewType.lowConfidenceSalesReport,
        'missing_sales_period' => ReviewType.missingSalesPeriod,
        'pos_connection_issue' => ReviewType.posConnectionIssue,
        _ => ReviewType.unknown,
      };

  String get value => switch (this) {
        ReviewType.lowConfidenceField => 'low_confidence_field',
        ReviewType.duplicateDocument => 'duplicate_document',
        ReviewType.missingCategory => 'missing_category',
        ReviewType.failedExtraction => 'failed_extraction',
        ReviewType.productMatchReview => 'product_match_review',
        ReviewType.supplierMatchReview => 'supplier_match_review',
        ReviewType.priceAnomaly => 'price_anomaly',
        ReviewType.priceVariation => 'price_variation',
        ReviewType.baselineReview => 'baseline_review',
        ReviewType.documentNeedsReview => 'document_needs_review',
        ReviewType.unknownSupplier => 'unknown_supplier',
        ReviewType.unknownDocumentType => 'unknown_document_type',
        ReviewType.failedSalesImport => 'failed_sales_import',
        ReviewType.lowConfidenceSalesReport => 'low_confidence_sales_report',
        ReviewType.missingSalesPeriod => 'missing_sales_period',
        ReviewType.posConnectionIssue => 'pos_connection_issue',
        ReviewType.unknown => 'unknown',
      };

  String get label => switch (this) {
        ReviewType.lowConfidenceField => 'Field review',
        ReviewType.duplicateDocument => 'Duplicate',
        ReviewType.missingCategory => 'Category',
        ReviewType.failedExtraction => 'Extraction',
        ReviewType.productMatchReview => 'Product match',
        ReviewType.supplierMatchReview => 'Supplier match',
        ReviewType.priceAnomaly => 'Price alert',
        ReviewType.priceVariation => 'Price change',
        ReviewType.baselineReview => 'Baseline',
        ReviewType.documentNeedsReview => 'Document',
        ReviewType.unknownSupplier => 'Supplier',
        ReviewType.unknownDocumentType => 'Document type',
        ReviewType.failedSalesImport => 'Sales import',
        ReviewType.lowConfidenceSalesReport => 'Sales review',
        ReviewType.missingSalesPeriod => 'Sales period',
        ReviewType.posConnectionIssue => 'POS',
        ReviewType.unknown => 'Review',
      };

  bool get countsAsAiReview => switch (this) {
        ReviewType.failedExtraction ||
        ReviewType.lowConfidenceField ||
        ReviewType.unknownDocumentType ||
        ReviewType.documentNeedsReview ||
        ReviewType.productMatchReview ||
        ReviewType.supplierMatchReview ||
        ReviewType.lowConfidenceSalesReport => true,
        _ => false,
      };

  bool get countsAsPriceAlert => switch (this) {
        ReviewType.priceAnomaly ||
        ReviewType.priceVariation ||
        ReviewType.baselineReview => true,
        _ => false,
      };
}

enum ReviewSeverity {
  low,
  medium,
  high,
  critical,
  unknown;

  static ReviewSeverity fromJson(String? value) => switch (value) {
        'low' => ReviewSeverity.low,
        'medium' => ReviewSeverity.medium,
        'high' => ReviewSeverity.high,
        'critical' => ReviewSeverity.critical,
        _ => ReviewSeverity.unknown,
      };

  String get value => switch (this) {
        ReviewSeverity.low => 'low',
        ReviewSeverity.medium => 'medium',
        ReviewSeverity.high => 'high',
        ReviewSeverity.critical => 'critical',
        ReviewSeverity.unknown => 'medium',
      };

  int get rank => switch (this) {
        ReviewSeverity.critical => 4,
        ReviewSeverity.high => 3,
        ReviewSeverity.medium => 2,
        ReviewSeverity.low => 1,
        ReviewSeverity.unknown => 0,
      };
}

enum ReviewStatus {
  open,
  resolved,
  ignored,
  dismissed,
  retrying,
  unknown;

  static ReviewStatus fromJson(String? value) => switch (value) {
        'open' => ReviewStatus.open,
        'resolved' => ReviewStatus.resolved,
        'ignored' => ReviewStatus.ignored,
        'dismissed' => ReviewStatus.dismissed,
        'retrying' => ReviewStatus.retrying,
        _ => ReviewStatus.unknown,
      };

  String get value => switch (this) {
        ReviewStatus.open => 'open',
        ReviewStatus.resolved => 'resolved',
        ReviewStatus.ignored => 'ignored',
        ReviewStatus.dismissed => 'dismissed',
        ReviewStatus.retrying => 'retrying',
        ReviewStatus.unknown => 'open',
      };
}

class ReviewItem {
  const ReviewItem({
    required this.id,
    required this.companyId,
    required this.type,
    required this.severity,
    required this.status,
    required this.sourceTable,
    required this.sourceId,
    required this.title,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.suggestedAction,
    this.resolvedAt,
    this.ignoredAt,
  });

  final String id;
  final String companyId;
  final ReviewType type;
  final ReviewSeverity severity;
  final ReviewStatus status;
  final String sourceTable;
  final String sourceId;
  final String title;
  final String? description;
  final String? suggestedAction;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? resolvedAt;
  final DateTime? ignoredAt;

  factory ReviewItem.fromJson(Map<String, dynamic> json) {
    return ReviewItem(
      id: json['id'] as String? ?? '',
      companyId: json['company_id'] as String? ?? '',
      type: ReviewType.fromJson(json['review_type'] as String?),
      severity: ReviewSeverity.fromJson(json['severity'] as String?),
      status: ReviewStatus.fromJson(json['status'] as String?),
      sourceTable: json['source_table'] as String? ?? '',
      sourceId: json['source_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Review item',
      description: json['description'] as String?,
      suggestedAction: json['suggested_action'] as String?,
      metadata: Map<String, dynamic>.from(
        json['metadata'] as Map? ?? const <String, dynamic>{},
      ),
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
      resolvedAt: _parseDate(json['resolved_at']),
      ignoredAt: _parseDate(json['ignored_at']),
    );
  }

  bool get isDocumentSource => sourceTable == 'documents';
  bool get isPriceAnomaly => type == ReviewType.priceAnomaly;
  bool get isPriceReview => type.countsAsPriceAlert;
  bool get isFailedExtraction => type == ReviewType.failedExtraction;

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}

class ReviewItemCounts {
  const ReviewItemCounts({
    required this.open,
    required this.critical,
    required this.aiReview,
    required this.priceAlerts,
    required this.byType,
    required this.bySeverity,
  });

  const ReviewItemCounts.empty()
      : open = 0,
        critical = 0,
        aiReview = 0,
        priceAlerts = 0,
        byType = const <ReviewType, int>{},
        bySeverity = const <ReviewSeverity, int>{};

  final int open;
  final int critical;
  final int aiReview;
  final int priceAlerts;
  final Map<ReviewType, int> byType;
  final Map<ReviewSeverity, int> bySeverity;
}
