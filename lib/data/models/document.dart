import 'package:freezed_annotation/freezed_annotation.dart';

part 'document.freezed.dart';
part 'document.g.dart';

/// Document domain model
/// Represents invoices, receipts, delivery notes from providers
@freezed
class Document with _$Document {
  const factory Document({
    required String id,
    @JsonKey(name: 'company_id') required String companyId,
    @JsonKey(name: 'provider_id') String? providerId,
    @JsonKey(name: 'document_type') @Default('invoice') String documentType,
    @JsonKey(name: 'document_number') String? documentNumber,
    @JsonKey(name: 'document_date') required DateTime documentDate,
    @JsonKey(name: 'due_date') DateTime? dueDate,
    @JsonKey(name: 'total_amount') required double totalAmount,
    @JsonKey(name: 'tax_amount') @Default(0) double taxAmount,
    @JsonKey(name: 'subtotal_amount') @Default(0) double subtotalAmount,
    String? currency,
    @JsonKey(name: 'payment_status') @Default('pending') String paymentStatus,
    @JsonKey(name: 'paid_date') DateTime? paidDate,
    @JsonKey(name: 'paid_amount') @Default(0) double paidAmount,
    @JsonKey(name: 'ocr_status') @Default('pending') String ocrStatus,
    @JsonKey(name: 'storage_path') String? storagePath,
    String? notes,
    @JsonKey(name: 'is_archived') @Default(false) bool isArchived,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
    // Joined data
    @JsonKey(name: 'provider') Map<String, dynamic>? providerData,
  }) = _Document;

  const Document._();

  factory Document.fromJson(Map<String, dynamic> json) =>
      _$DocumentFromJson(json);

  /// Get provider name from joined data
  String? get providerName => providerData?['name'] as String?;

  /// Check if document is overdue
  bool get isOverdue =>
      paymentStatus == 'pending' &&
      dueDate != null &&
      dueDate!.isBefore(DateTime.now());
}

/// Document summary for dashboard metrics
@freezed
class DocumentSummary with _$DocumentSummary {
  const factory DocumentSummary({
    required double totalExpenses,
    required double previousPeriodExpenses,
    required double percentageChange,
    required bool isPositive,
    required int pendingCount,
    required int overdueCount,
  }) = _DocumentSummary;

  const DocumentSummary._();

  factory DocumentSummary.empty() => const DocumentSummary(
    totalExpenses: 0,
    previousPeriodExpenses: 0,
    percentageChange: 0,
    isPositive: true,
    pendingCount: 0,
    overdueCount: 0,
  );
}
