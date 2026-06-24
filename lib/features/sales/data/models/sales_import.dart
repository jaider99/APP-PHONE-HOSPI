class SalesImport {
  const SalesImport({
    required this.id,
    required this.companyId,
    required this.sourceType,
    required this.status,
    required this.currency,
    required this.createdAt,
    this.sourceName,
    this.filePath,
    this.importedAt,
    this.periodStart,
    this.periodEnd,
    this.totalGross,
    this.totalNet,
    this.totalTax,
    this.notes,
  });

  final String id;
  final String companyId;
  final String sourceType;
  final String? sourceName;
  final String? filePath;
  final String status;
  final DateTime? importedAt;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final double? totalGross;
  final double? totalNet;
  final double? totalTax;
  final String currency;
  final String? notes;
  final DateTime createdAt;

  factory SalesImport.fromJson(Map<String, dynamic> json) {
    return SalesImport(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      sourceType: json['source_type'] as String? ?? 'vlm_import',
      sourceName: json['source_name'] as String?,
      filePath: json['file_path'] as String?,
      status: json['status'] as String? ?? 'processing',
      importedAt: _readDate(json['imported_at']),
      periodStart: _readDate(json['period_start']),
      periodEnd: _readDate(json['period_end']),
      totalGross: _readDouble(json['total_gross']),
      totalNet: _readDouble(json['total_net']),
      totalTax: _readDouble(json['total_tax']),
      currency: json['currency'] as String? ?? 'EUR',
      notes: json['notes'] as String?,
      createdAt: _readDate(json['created_at']) ?? DateTime.now(),
    );
  }
}

double? _readDouble(Object? value) => value is num ? value.toDouble() : null;

DateTime? _readDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;