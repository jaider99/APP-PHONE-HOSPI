class PosConnection {
  const PosConnection({
    required this.id,
    required this.companyId,
    required this.provider,
    required this.status,
    required this.createdAt,
    this.providerKey,
    this.providerName,
    this.countryCode,
    this.connectionType,
    this.credentialsStatus,
    this.externalAccountId,
    this.lastSyncAt,
    this.syncStatus,
  });

  final String id;
  final String companyId;
  final String provider;
  final String? providerKey;
  final String? providerName;
  final String? countryCode;
  final String status;
  final String? connectionType;
  final String? credentialsStatus;
  final String? externalAccountId;
  final DateTime? lastSyncAt;
  final String? syncStatus;
  final DateTime createdAt;

  factory PosConnection.fromJson(Map<String, dynamic> json) {
    return PosConnection(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      provider: json['provider'] as String? ?? 'custom',
      providerKey: json['provider_key'] as String?,
      providerName: json['provider_name'] as String?,
      countryCode: json['country_code'] as String?,
      status: json['status'] as String? ?? 'pending',
      connectionType: json['connection_type'] as String?,
      credentialsStatus: json['credentials_status'] as String?,
      externalAccountId: json['external_account_id'] as String?,
      lastSyncAt: _readDate(json['last_sync_at']),
      syncStatus: json['sync_status'] as String?,
      createdAt: _readDate(json['created_at']) ?? DateTime.now(),
    );
  }
}

DateTime? _readDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
