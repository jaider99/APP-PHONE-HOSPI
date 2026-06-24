import 'package:flutter/foundation.dart';

@immutable
class PriceAnomalyModel {
  final String id;
  final String companyId;
  final String productId;
  final String? supplierId;
  final String? supplierName;
  final String? documentId;
  final String? documentItemId;
  final String? productPriceId;
  final String anomalyType;
  final double? currentPrice;
  final double? expectedPrice;
  final double? deviationPercent;
  final String severity;
  final double confidenceScore;
  final String? explanation;
  final Map<String, dynamic> heuristicDetails;
  final double? aiConfidence;
  final String? aiExplanation;
  final bool resolved;
  final String resolutionStatus;
  final DateTime createdAt;

  const PriceAnomalyModel({
    required this.id,
    required this.companyId,
    required this.productId,
    required this.anomalyType,
    required this.severity,
    required this.confidenceScore,
    required this.heuristicDetails,
    required this.resolved,
    required this.resolutionStatus,
    required this.createdAt,
    this.supplierId,
    this.supplierName,
    this.documentId,
    this.documentItemId,
    this.productPriceId,
    this.currentPrice,
    this.expectedPrice,
    this.deviationPercent,
    this.explanation,
    this.aiConfidence,
    this.aiExplanation,
  });

  factory PriceAnomalyModel.fromJson(Map<String, dynamic> json) {
    return PriceAnomalyModel(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      productId: json['product_id'] as String,
      supplierId: json['supplier_id'] as String?,
      supplierName:
          ((json['providers'] as Map<String, dynamic>?)?['name'] as String?) ??
              json['supplier_name'] as String?,
      documentId: json['document_id'] as String?,
      documentItemId: json['document_item_id'] as String?,
      productPriceId: json['product_price_id'] as String?,
      anomalyType: json['anomaly_type'] as String,
      currentPrice: (json['current_price'] as num?)?.toDouble(),
      expectedPrice: (json['expected_price'] as num?)?.toDouble(),
      deviationPercent: (json['deviation_percent'] as num?)?.toDouble(),
      severity: json['severity'] as String? ?? 'low',
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0,
      explanation: json['explanation'] as String?,
      heuristicDetails:
          (json['heuristic_details'] as Map?)?.cast<String, dynamic>() ??
              const {},
      aiConfidence: (json['ai_confidence'] as num?)?.toDouble(),
      aiExplanation: json['ai_explanation'] as String?,
      resolved: json['resolved'] as bool? ?? false,
      resolutionStatus: json['resolution_status'] as String? ?? 'open',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  String get title {
    switch (anomalyType) {
      case 'price_spike':
        return 'Price spike';
      case 'supplier_overpricing':
        return 'Supplier overpricing';
      case 'inflation_trend':
        return 'Inflation trend';
      case 'quantity_anomaly':
        return 'Quantity anomaly';
      case 'duplicate_price_pattern':
        return 'Duplicate pattern';
      default:
        return anomalyType.replaceAll('_', ' ');
    }
  }

  bool get isOpen => !resolved && resolutionStatus == 'open';
}
