import 'package:flutter/foundation.dart';

@immutable
class ProductLinkedDocumentModel {
  const ProductLinkedDocumentModel({
    required this.documentId,
    required this.title,
    required this.documentType,
    required this.lineCount,
    this.supplierName,
    this.documentDate,
    this.totalAmount,
    this.currency,
  });

  final String documentId;
  final String title;
  final String documentType;
  final String? supplierName;
  final DateTime? documentDate;
  final double? totalAmount;
  final String? currency;
  final int lineCount;
}