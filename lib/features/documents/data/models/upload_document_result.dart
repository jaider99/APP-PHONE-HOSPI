import 'package:flutter/foundation.dart';
import 'package:hospi_dash/models/document_model.dart';

@immutable
class UploadDocumentResult {
  final bool success;
  final String? documentId;
  final String? error;
  final bool isDuplicate;
  final String? duplicateOfId;
  final String? duplicateReferenceNumber;
  final String? duplicateReferenceSupplier;
  final DocumentMergeStatus mergeStatus;
  final double mergeConfidence;
  final String? mergedIntoId;
  final String? categoryId;
  final String? aiCategoryId;
  final double categoryConfidence;

  const UploadDocumentResult({
    required this.success,
    this.documentId,
    this.error,
    this.isDuplicate = false,
    this.duplicateOfId,
    this.duplicateReferenceNumber,
    this.duplicateReferenceSupplier,
    this.mergeStatus = DocumentMergeStatus.none,
    this.mergeConfidence = 0,
    this.mergedIntoId,
    this.categoryId,
    this.aiCategoryId,
    this.categoryConfidence = 0,
  });

  bool get categoryAutoApplied =>
      categoryId != null &&
      aiCategoryId != null &&
      categoryId == aiCategoryId &&
      categoryConfidence >= 0.85;

  bool get hasCategorySuggestion =>
      categoryId == null && aiCategoryId != null && categoryConfidence >= 0.5;

  bool get categoryNeedsReview =>
      categoryId == null && aiCategoryId != null && categoryConfidence < 0.5;
}