import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Document filter options
enum DocumentFilter {
  all,
  processing,
  completed,
  invoices,
  deliveryNotes,
  expenseTickets,
  flagged,
}

/// Document types from extraction
enum DocumentType {
  invoice,
  deliveryNote,
  expenseTicket,
  unknown,
}

extension DocumentTypeExtension on DocumentType {
  String get displayName {
    switch (this) {
      case DocumentType.invoice:
        return 'Invoice';
      case DocumentType.deliveryNote:
        return 'Delivery Note';
      case DocumentType.expenseTicket:
        return 'Expense Ticket';
      case DocumentType.unknown:
        return 'Unknown';
    }
  }

  static DocumentType fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'invoice':
        return DocumentType.invoice;
      case 'delivery_note':
      case 'deliverynote':
        return DocumentType.deliveryNote;
      case 'expense_ticket':
      case 'expenseticket':
        return DocumentType.expenseTicket;
      default:
        return DocumentType.unknown;
    }
  }

  String get dbValue {
    switch (this) {
      case DocumentType.invoice:
        return 'invoice';
      case DocumentType.deliveryNote:
        return 'delivery_note';
      case DocumentType.expenseTicket:
        return 'expense_ticket';
      case DocumentType.unknown:
        return 'unknown';
    }
  }
}

/// Document processing status
enum DocumentStatus {
  processing,
  completed,
  flagged,
  failed,
}

enum DocumentMergeStatus {
  none,
  merged,
  review,
}

extension DocumentMergeStatusExtension on DocumentMergeStatus {
  static DocumentMergeStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'merged':
        return DocumentMergeStatus.merged;
      case 'review':
        return DocumentMergeStatus.review;
      case 'none':
      default:
        return DocumentMergeStatus.none;
    }
  }

  String get dbValue {
    switch (this) {
      case DocumentMergeStatus.none:
        return 'none';
      case DocumentMergeStatus.merged:
        return 'merged';
      case DocumentMergeStatus.review:
        return 'review';
    }
  }
}

extension DocumentStatusExtension on DocumentStatus {
  String get displayName {
    switch (this) {
      case DocumentStatus.processing:
        return 'Processing';
      case DocumentStatus.completed:
        return 'Completed';
      case DocumentStatus.flagged:
        return 'Flagged';
      case DocumentStatus.failed:
        return 'Failed';
    }
  }

  static DocumentStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'completed':
        return DocumentStatus.completed;
      case 'flagged':
        return DocumentStatus.flagged;
      case 'failed':
        return DocumentStatus.failed;
      case 'processing':
      default:
        return DocumentStatus.processing;
    }
  }

  String get dbValue {
    switch (this) {
      case DocumentStatus.processing:
        return 'processing';
      case DocumentStatus.completed:
        return 'completed';
      case DocumentStatus.flagged:
        return 'flagged';
      case DocumentStatus.failed:
        return 'failed';
    }
  }
}

/// Document counts by status
@immutable
class DocumentCounts {
  final int total;
  final int processing;
  final int completed;
  final int flagged;
  final int failed;

  const DocumentCounts({
    this.total = 0,
    this.processing = 0,
    this.completed = 0,
    this.flagged = 0,
    this.failed = 0,
  });

  factory DocumentCounts.fromStatusMap(Map<String, int> statusMap) {
    final processing = statusMap['processing'] ?? 0;
    final completed = statusMap['completed'] ?? 0;
    final flagged = statusMap['flagged'] ?? 0;
    final failed = statusMap['failed'] ?? 0;
    return DocumentCounts(
      total: processing + completed + flagged + failed,
      processing: processing,
      completed: completed,
      flagged: flagged,
      failed: failed,
    );
  }
}

/// Extraction confidence level
enum ExtractionConfidence {
  high,
  medium,
  low,
}

extension ExtractionConfidenceExtension on ExtractionConfidence {
  static ExtractionConfidence fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'high':
        return ExtractionConfidence.high;
      case 'medium':
        return ExtractionConfidence.medium;
      case 'low':
      default:
        return ExtractionConfidence.low;
    }
  }
}

/// Line item from extracted document
@immutable
class DocumentLineItem {
  final String? id;
  final String? documentId;
  final String? companyId;
  final String? productId;
  final String description;
  final double quantity;
  final String? unit;
  final double? unitPrice;
  final double? lineTotal;
  final String? productCode;
  final double? vatRate;

  const DocumentLineItem({
    this.id,
    this.documentId,
    this.companyId,
    this.productId,
    required this.description,
    required this.quantity,
    this.unit,
    this.unitPrice,
    this.lineTotal,
    this.productCode,
    this.vatRate,
  });

  factory DocumentLineItem.fromJson(Map<String, dynamic> json) {
    return DocumentLineItem(
      id: json['id'] as String?,
      documentId: json['document_id'] as String?,
      companyId: json['company_id'] as String?,
      productId: json['product_id'] as String?,
      description: json['description'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      unit: json['unit_type'] as String? ?? json['unit'] as String?,
      unitPrice: (json['unit_price'] as num?)?.toDouble(),
      lineTotal: (json['line_total'] as num?)?.toDouble() ??
          (json['total_price'] as num?)?.toDouble(),
      productCode: json['product_code'] as String?,
      vatRate: (json['vat_rate'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (documentId != null) 'document_id': documentId,
      if (companyId != null) 'company_id': companyId,
      if (productId != null) 'product_id': productId,
      'description': description,
      'quantity': quantity,
      if (unit != null) 'unit': unit,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (lineTotal != null) 'line_total': lineTotal,
      if (productCode != null) 'product_code': productCode,
      if (vatRate != null) 'vat_rate': vatRate,
    };
  }

  DocumentLineItem copyWith({
    String? id,
    String? documentId,
    String? companyId,
    String? productId,
    String? description,
    double? quantity,
    String? unit,
    double? unitPrice,
    double? lineTotal,
    String? productCode,
    double? vatRate,
  }) {
    return DocumentLineItem(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      companyId: companyId ?? this.companyId,
      productId: productId ?? this.productId,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      lineTotal: lineTotal ?? this.lineTotal,
      productCode: productCode ?? this.productCode,
      vatRate: vatRate ?? this.vatRate,
    );
  }
}

/// Extraction result from VLM pipeline
@immutable
class ExtractionResult {
  final DocumentType documentType;
  final String? supplierName;
  final String? supplierTaxId;
  final String? supplierAddress;
  final String? supplierPhone;
  final String? supplierEmail;
  final String? documentNumber;
  final DateTime? documentDate;
  final DateTime? deliveryDate;
  final DateTime? dueDate;
  final List<DocumentLineItem> lineItems;
  final double? subtotal;
  final double? taxRate;
  final double? taxAmount;
  final double? discountAmount;
  final double? totalAmount;
  final String currency;
  final String? notes;
  final ExtractionConfidence confidence;
  final double confidenceScore;
  final String? rawJson;

  const ExtractionResult({
    required this.documentType,
    this.supplierName,
    this.supplierTaxId,
    this.supplierAddress,
    this.supplierPhone,
    this.supplierEmail,
    this.documentNumber,
    this.documentDate,
    this.deliveryDate,
    this.dueDate,
    this.lineItems = const [],
    this.subtotal,
    this.taxRate,
    this.taxAmount,
    this.discountAmount,
    this.totalAmount,
    this.currency = 'EUR',
    this.notes,
    this.confidence = ExtractionConfidence.low,
    this.confidenceScore = 0,
    this.rawJson,
  });

  factory ExtractionResult.fromJson(Map<String, dynamic> json, {String? rawJson}) {
    DateTime? parseDate(String? dateStr) {
      if (dateStr == null || dateStr.isEmpty) return null;
      try {
        return DateTime.parse(dateStr);
      } catch (_) {
        return null;
      }
    }

    final lineItemsJson = json['line_items'] as List<dynamic>? ?? [];
    final lineItems = lineItemsJson
        .map((item) => DocumentLineItem.fromJson(item as Map<String, dynamic>))
        .toList();

    // Handle nested supplier object (Python-style) or flat fields
    String? supplierName = json['supplier_name'] as String?;
    String? supplierTaxId = json['supplier_tax_id'] as String?;
    String? supplierAddress;
    String? supplierPhone;
    String? supplierEmail;

    final supplierObj = json['supplier'];
    if (supplierObj is Map<String, dynamic>) {
      supplierName ??= supplierObj['name'] as String?;
      supplierTaxId ??= supplierObj['tax_id'] as String?;
      supplierAddress = supplierObj['address'] as String?;
      supplierPhone = supplierObj['phone'] as String?;
      supplierEmail = supplierObj['email'] as String?;
    }

    // Calculate numeric confidence
    final numericScore = _calculateConfidenceScore(
      json,
      supplierName: supplierName,
      supplierTaxId: supplierTaxId,
      lineItems: lineItems,
    );

    // Derive enum from numeric score
    ExtractionConfidence confidenceEnum;
    final rawConfidence = json['confidence'];
    if (rawConfidence is num) {
      confidenceEnum = rawConfidence >= 70
          ? ExtractionConfidence.high
          : rawConfidence >= 40
              ? ExtractionConfidence.medium
              : ExtractionConfidence.low;
    } else if (rawConfidence is String) {
      confidenceEnum = ExtractionConfidenceExtension.fromString(rawConfidence);
    } else {
      confidenceEnum = numericScore >= 70
          ? ExtractionConfidence.high
          : numericScore >= 40
              ? ExtractionConfidence.medium
              : ExtractionConfidence.low;
    }

    return ExtractionResult(
      documentType: DocumentTypeExtension.fromString(json['document_type'] as String?),
      supplierName: supplierName,
      supplierTaxId: supplierTaxId,
      supplierAddress: supplierAddress,
      supplierPhone: supplierPhone,
      supplierEmail: supplierEmail,
      documentNumber: json['document_number'] as String? ?? json['invoice_number'] as String?,
      documentDate: parseDate(json['document_date'] as String? ?? json['invoice_date'] as String?),
      deliveryDate: parseDate(json['delivery_date'] as String?),
      dueDate: parseDate(json['due_date'] as String?),
      lineItems: lineItems,
      subtotal: (json['subtotal'] as num?)?.toDouble(),
      taxRate: (json['tax_rate'] as num?)?.toDouble(),
      taxAmount: (json['tax_amount'] as num?)?.toDouble(),
      discountAmount: (json['discount_amount'] as num?)?.toDouble(),
      totalAmount: (json['total_amount'] as num?)?.toDouble(),
      currency: json['currency'] as String? ?? 'EUR',
      notes: json['notes'] as String?,
      confidence: confidenceEnum,
      confidenceScore: numericScore,
      rawJson: rawJson,
    );
  }

  /// Algorithmic confidence scoring (0-100) based on extracted field completeness
  static double _calculateConfidenceScore(
    Map<String, dynamic> json, {
    String? supplierName,
    String? supplierTaxId,
    List<DocumentLineItem>? lineItems,
  }) {
    double score = 0;

    // Core fields (50 points)
    final docType = json['document_type'] as String?;
    if (docType != null && docType != 'unknown') score += 5;
    if ((json['document_number'] ?? json['invoice_number']) != null) score += 10;
    if ((json['document_date'] ?? json['invoice_date']) != null) score += 10;
    if (json['total_amount'] != null) score += 15;
    if (json['subtotal'] != null) score += 5;
    if (json['tax_amount'] != null) score += 5;

    // Supplier info (20 points)
    if (supplierName != null && supplierName.isNotEmpty) score += 10;
    if (supplierTaxId != null && supplierTaxId.isNotEmpty) score += 5;
    final supplierObj = json['supplier'];
    if (supplierObj is Map && (supplierObj['address'] ?? '').toString().isNotEmpty) {
      score += 5;
    }

    // Line items (20 points)
    final items = lineItems ?? <DocumentLineItem>[];
    if (items.isNotEmpty) {
      score += 10;
      final completeItems = items
          .where((i) => i.description.isNotEmpty && i.lineTotal != null)
          .length;
      if (completeItems > 0) score += (completeItems * 2).clamp(0, 10).toDouble();
    }

    // Bonus (10 points)
    final currency = json['currency'] as String?;
    if (currency != null && currency != 'EUR') score += 2;
    if (json['due_date'] != null) score += 3;
    final customer = json['customer'];
    if (customer is Map && (customer['name'] ?? '').toString().isNotEmpty) score += 3;
    if (json['payment'] != null) score += 2;

    return score.clamp(0, 100);
  }

  Map<String, dynamic> toJson() {
    return {
      'document_type': documentType.dbValue,
      if (supplierName != null) 'supplier_name': supplierName,
      if (supplierTaxId != null) 'supplier_tax_id': supplierTaxId,
      if (supplierAddress != null) 'supplier_address': supplierAddress,
      if (supplierPhone != null) 'supplier_phone': supplierPhone,
      if (supplierEmail != null) 'supplier_email': supplierEmail,
      if (documentNumber != null) 'document_number': documentNumber,
      if (documentDate != null) 'document_date': documentDate!.toIso8601String().split('T').first,
      if (deliveryDate != null) 'delivery_date': deliveryDate!.toIso8601String().split('T').first,
      if (dueDate != null) 'due_date': dueDate!.toIso8601String().split('T').first,
      'line_items': lineItems.map((e) => e.toJson()).toList(),
      if (subtotal != null) 'subtotal': subtotal,
      if (taxRate != null) 'tax_rate': taxRate,
      if (taxAmount != null) 'tax_amount': taxAmount,
      if (discountAmount != null) 'discount_amount': discountAmount,
      if (totalAmount != null) 'total_amount': totalAmount,
      'currency': currency,
      if (notes != null) 'notes': notes,
      'confidence': confidenceScore,
    };
  }
}

/// Main document model
@immutable
class DocumentModel {
  final String id;
  final String companyId;
  final DateTime createdAt;
  final String? uploadedBy;
  final String fileUrl;
  final String? filePath;
  final String fileName;
  final String fileType;
  final DocumentStatus status;
  final DocumentType documentType;
  final String? supplierId;
  final String? supplierName;
  final bool isDuplicate;
  final String? duplicateOfId;
  final DocumentMergeStatus mergeStatus;
  final double mergeConfidence;
  final String? mergedIntoId;
  final String? mergeGroupId;
  final String? normalizedDocumentNumber;
  final String? normalizedSupplier;
  final String? documentNumber;
  final DateTime? documentDate;
  final String? categoryId;
  final String? aiCategoryId;
  final double categoryConfidence;
  final double? totalAmount;
  final double? taxAmount;
  final String currency;
  final Map<String, dynamic>? extractionRaw;
  final Map<String, dynamic>? extractionClean;
  final String? notes;
  final List<DocumentLineItem> lineItems;

  const DocumentModel({
    required this.id,
    required this.companyId,
    required this.createdAt,
    this.uploadedBy,
    required this.fileUrl,
    this.filePath,
    required this.fileName,
    required this.fileType,
    required this.status,
    required this.documentType,
    this.supplierId,
    this.supplierName,
    this.isDuplicate = false,
    this.duplicateOfId,
    this.mergeStatus = DocumentMergeStatus.none,
    this.mergeConfidence = 0,
    this.mergedIntoId,
    this.mergeGroupId,
    this.normalizedDocumentNumber,
    this.normalizedSupplier,
    this.documentNumber,
    this.documentDate,
    this.categoryId,
    this.aiCategoryId,
    this.categoryConfidence = 0,
    this.totalAmount,
    this.taxAmount,
    this.currency = 'EUR',
    this.extractionRaw,
    this.extractionClean,
    this.notes,
    this.lineItems = const [],
  });

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    // Safely decode a field that may arrive as a Map<String,dynamic> (JSONB)
    // or as a pre-serialized JSON String (text column / PostgREST quirk).
    Map<String, dynamic>? parseJsonField(dynamic value) {
      if (value == null) return null;
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      if (value is String) {
        try {
          // ignore: avoid_dynamic_calls
          final decoded = (const JsonDecoder()).convert(value);
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {}
      }
      return null;
    }

    final lineItemsJson = json['document_items'] as List<dynamic>?;
    final lineItems = lineItemsJson
            ?.map((item) => DocumentLineItem.fromJson(item as Map<String, dynamic>))
            .toList() ??
        [];
    final extractionClean = parseJsonField(json['extraction_clean']);

    // Prefer extraction value first; use joined provider name only as fallback.
    String? supplierName =
      json['supplier_name'] as String? ?? extractionClean?['supplier_name'] as String?;
    if ((supplierName == null || supplierName.trim().isEmpty) &&
        json['providers'] != null &&
        json['providers'] is Map) {
      supplierName = (json['providers'] as Map)['name'] as String?;
    }

    final resolvedDocumentType =
      (json['document_type'] as String?) ?? extractionClean?['document_type'] as String?;
    final resolvedDocumentNumber =
      json['document_number'] as String? ?? extractionClean?['document_number'] as String?;
    final resolvedDocumentDate =
      parseDate(json['document_date']) ?? parseDate(extractionClean?['document_date']);
    final resolvedTotalAmount =
      (json['total_amount'] as num?)?.toDouble() ??
      (extractionClean?['total_amount'] as num?)?.toDouble();
    final resolvedTaxAmount =
      (json['tax_amount'] as num?)?.toDouble() ??
      (extractionClean?['tax_amount'] as num?)?.toDouble();
    final resolvedCurrency =
      json['currency'] as String? ?? extractionClean?['currency'] as String? ?? 'EUR';

    return DocumentModel(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
      uploadedBy: json['uploaded_by'] as String?,
      fileUrl: json['file_url'] as String? ?? '',
      filePath: json['file_path'] as String?,
      fileName: json['file_name'] as String? ?? 'unknown',
      fileType: json['file_type'] as String? ?? 'application/octet-stream',
      status: DocumentStatusExtension.fromString(json['status'] as String?),
      documentType: DocumentTypeExtension.fromString(resolvedDocumentType),
      supplierId: json['provider_id'] as String?,
      supplierName: supplierName,
      isDuplicate: json['is_duplicate'] as bool? ?? false,
      duplicateOfId: json['duplicate_of'] as String?,
      mergeStatus: DocumentMergeStatusExtension.fromString(
        json['merge_status'] as String?,
      ),
      mergeConfidence: (json['merge_confidence'] as num?)?.toDouble() ?? 0,
      mergedIntoId: json['merged_into'] as String?,
      mergeGroupId: json['merge_group_id'] as String?,
      normalizedDocumentNumber: json['normalized_document_number'] as String?,
      normalizedSupplier: json['normalized_supplier'] as String?,
      documentNumber: resolvedDocumentNumber,
      documentDate: resolvedDocumentDate,
      categoryId: json['category_id'] as String?,
      aiCategoryId: json['ai_category_id'] as String?,
      categoryConfidence: (json['category_confidence'] as num?)?.toDouble() ?? 0,
      totalAmount: resolvedTotalAmount,
      taxAmount: resolvedTaxAmount,
      currency: resolvedCurrency,
      extractionRaw: parseJsonField(json['extraction_raw']),
      extractionClean: extractionClean,
      notes: json['notes'] as String?,
      lineItems: lineItems,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'company_id': companyId,
      'created_at': createdAt.toIso8601String(),
      if (uploadedBy != null) 'uploaded_by': uploadedBy,
      'file_url': fileUrl,
      if (filePath != null) 'file_path': filePath,
      'file_name': fileName,
      'file_type': fileType,
      'status': status.dbValue,
      'document_type': documentType.dbValue,
      if (supplierId != null) 'provider_id': supplierId,
      'is_duplicate': isDuplicate,
      if (duplicateOfId != null) 'duplicate_of': duplicateOfId,
      'merge_status': mergeStatus.dbValue,
      'merge_confidence': mergeConfidence,
      if (mergedIntoId != null) 'merged_into': mergedIntoId,
      if (mergeGroupId != null) 'merge_group_id': mergeGroupId,
      if (normalizedDocumentNumber != null)
        'normalized_document_number': normalizedDocumentNumber,
      if (normalizedSupplier != null) 'normalized_supplier': normalizedSupplier,
      if (documentNumber != null) 'document_number': documentNumber,
      if (documentDate != null) 'document_date': documentDate!.toIso8601String().split('T').first,
      if (categoryId != null) 'category_id': categoryId,
      if (aiCategoryId != null) 'ai_category_id': aiCategoryId,
      'category_confidence': categoryConfidence,
      if (totalAmount != null) 'total_amount': totalAmount,
      if (taxAmount != null) 'tax_amount': taxAmount,
      'currency': currency,
      if (extractionRaw != null) 'extraction_raw': extractionRaw,
      if (extractionClean != null) 'extraction_clean': extractionClean,
      if (notes != null) 'notes': notes,
    };
  }

  /// Create insert map for new document
  Map<String, dynamic> toInsertJson() {
    return {
      'company_id': companyId,
      if (uploadedBy != null) 'uploaded_by': uploadedBy,
      'file_url': fileUrl,
      if (filePath != null) 'file_path': filePath,
      'file_name': fileName,
      'file_type': fileType,
      'status': status.dbValue,
      'document_type': documentType.dbValue,
      'currency': currency,
    };
  }

  DocumentModel copyWith({
    String? id,
    String? companyId,
    DateTime? createdAt,
    String? uploadedBy,
    String? fileUrl,
    String? filePath,
    String? fileName,
    String? fileType,
    DocumentStatus? status,
    DocumentType? documentType,
    String? supplierId,
    String? supplierName,
    bool? isDuplicate,
    String? duplicateOfId,
    DocumentMergeStatus? mergeStatus,
    double? mergeConfidence,
    String? mergedIntoId,
    String? mergeGroupId,
    String? normalizedDocumentNumber,
    String? normalizedSupplier,
    String? documentNumber,
    DateTime? documentDate,
    String? categoryId,
    String? aiCategoryId,
    double? categoryConfidence,
    double? totalAmount,
    double? taxAmount,
    String? currency,
    Map<String, dynamic>? extractionRaw,
    Map<String, dynamic>? extractionClean,
    String? notes,
    List<DocumentLineItem>? lineItems,
  }) {
    return DocumentModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      createdAt: createdAt ?? this.createdAt,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      fileUrl: fileUrl ?? this.fileUrl,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileType: fileType ?? this.fileType,
      status: status ?? this.status,
      documentType: documentType ?? this.documentType,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      isDuplicate: isDuplicate ?? this.isDuplicate,
      duplicateOfId: duplicateOfId ?? this.duplicateOfId,
      mergeStatus: mergeStatus ?? this.mergeStatus,
      mergeConfidence: mergeConfidence ?? this.mergeConfidence,
      mergedIntoId: mergedIntoId ?? this.mergedIntoId,
      mergeGroupId: mergeGroupId ?? this.mergeGroupId,
      normalizedDocumentNumber:
          normalizedDocumentNumber ?? this.normalizedDocumentNumber,
      normalizedSupplier: normalizedSupplier ?? this.normalizedSupplier,
      documentNumber: documentNumber ?? this.documentNumber,
      documentDate: documentDate ?? this.documentDate,
      categoryId: categoryId ?? this.categoryId,
      aiCategoryId: aiCategoryId ?? this.aiCategoryId,
      categoryConfidence: categoryConfidence ?? this.categoryConfidence,
      totalAmount: totalAmount ?? this.totalAmount,
      taxAmount: taxAmount ?? this.taxAmount,
      currency: currency ?? this.currency,
      extractionRaw: extractionRaw ?? this.extractionRaw,
      extractionClean: extractionClean ?? this.extractionClean,
      notes: notes ?? this.notes,
      lineItems: lineItems ?? this.lineItems,
    );
  }

  /// Check if document is an image type
  bool get isImage => fileType.startsWith('image/');

  /// Check if document is a PDF
  bool get isPdf =>
      fileType == 'application/pdf' ||
      fileType == 'pdf' ||
      fileName.toLowerCase().endsWith('.pdf');

    bool get categoryAutoApplied =>
      categoryId != null &&
      aiCategoryId != null &&
      categoryId == aiCategoryId &&
      categoryConfidence >= 0.85;

    bool get hasCategorySuggestion =>
      categoryId == null && aiCategoryId != null && categoryConfidence >= 0.5;

    bool get categoryNeedsReview =>
      categoryId == null && aiCategoryId != null && categoryConfidence < 0.5;

  /// Get display title (supplier name or filename)
  String get displayTitle {
    if (supplierName != null && supplierName!.isNotEmpty) {
      return supplierName!;
    }
    if (status != DocumentStatus.processing) {
      return 'Unknown supplier';
    }
    // Remove extension and truncate
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    if (nameWithoutExt.length > 25) {
      return '${nameWithoutExt.substring(0, 22)}...';
    }
    return nameWithoutExt;
  }

  /// Get subtitle text
  String get displaySubtitle {
    if (status == DocumentStatus.flagged) {
      return notes ?? 'Verification needed';
    }
    if (mergeStatus == DocumentMergeStatus.merged) {
      return 'Merged into related invoice';
    }
    if (mergeStatus == DocumentMergeStatus.review) {
      final percent = (mergeConfidence * 100).round();
      return 'Possible duplicate • $percent% confidence';
    }
    if (isDuplicate) {
      if (documentNumber != null && documentNumber!.isNotEmpty) {
        return 'Duplicate of invoice $documentNumber';
      }
      return 'Possible duplicate invoice';
    }
    if (categoryNeedsReview) {
      return 'Category needs review';
    }
    if (hasCategorySuggestion) {
      return 'Suggested category • ${(categoryConfidence * 100).round()}% confidence';
    }
    final parts = <String>[];
    if (documentNumber != null && documentNumber!.isNotEmpty) {
      parts.add(documentNumber!);
    }
    if (documentDate != null) {
      parts.add(_formatDate(documentDate!));
    }
    if (parts.isEmpty) {
      return 'Uploaded ${_formatDate(createdAt)}';
    }
    return parts.join(' • ');
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

/// Supplier model for upsert operations
@immutable
class SupplierModel {
  final String? id;
  final String companyId;
  final String name;
  final String? taxId;
  final String? email;
  final String? phone;
  final String? address;

  const SupplierModel({
    this.id,
    required this.companyId,
    required this.name,
    this.taxId,
    this.email,
    this.phone,
    this.address,
  });

  factory SupplierModel.fromJson(Map<String, dynamic> json) {
    return SupplierModel(
      id: json['id'] as String?,
      companyId: json['company_id'] as String,
      name: json['name'] as String,
      taxId: json['tax_id'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'company_id': companyId,
      'name': name,
      if (taxId != null) 'tax_id': taxId,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (address != null) 'address': address,
    };
  }
}
