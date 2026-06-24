class Sale {
  const Sale({
    required this.id,
    required this.companyId,
    required this.saleDate,
    required this.grossAmount,
    required this.currency,
    required this.sourceType,
    this.salesImportId,
    this.saleDateTime,
    this.netAmount,
    this.taxAmount,
    this.discountAmount,
    this.tipAmount,
    this.paymentMethod,
    this.channel,
    this.posTransactionId,
    this.transactionCount = 1,
    this.notes,
  });

  final String id;
  final String companyId;
  final String? salesImportId;
  final DateTime saleDate;
  final DateTime? saleDateTime;
  final double grossAmount;
  final double? netAmount;
  final double? taxAmount;
  final double? discountAmount;
  final double? tipAmount;
  final String currency;
  final String? paymentMethod;
  final String? channel;
  final String? posTransactionId;
  final int transactionCount;
  final String? notes;
  final String sourceType;

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      salesImportId: json['sales_import_id'] as String?,
      saleDate: DateTime.parse(json['sale_date'] as String),
      saleDateTime: _readDate(json['sale_datetime']),
      grossAmount: _readDouble(json['gross_amount']) ??
          _readDouble(json['total_amount']) ??
          0,
      netAmount: _readDouble(json['net_amount']),
      taxAmount: _readDouble(json['tax_amount']),
      discountAmount: _readDouble(json['discount_amount']),
      tipAmount: _readDouble(json['tip_amount']),
      currency: json['currency'] as String? ?? 'EUR',
      paymentMethod: json['payment_method'] as String?,
      channel: json['channel'] as String?,
      posTransactionId: json['pos_transaction_id'] as String?,
      transactionCount: (json['transaction_count'] as num?)?.toInt() ?? 1,
      notes: _readNotes(json['metadata']),
      sourceType: json['source_type'] as String? ?? 'manual',
    );
  }
}

double? _readDouble(Object? value) => value is num ? value.toDouble() : null;

DateTime? _readDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

String? _readNotes(Object? value) {
  if (value is! Map) return null;
  final notes = value['notes'];
  return notes is String && notes.trim().isNotEmpty ? notes.trim() : null;
}