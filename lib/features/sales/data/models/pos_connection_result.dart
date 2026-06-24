class PosConnectionResult {
  const PosConnectionResult({
    required this.status,
    required this.message,
    this.connectionId,
    this.requestId,
    this.connectUrl,
    this.nextAction,
  });

  final String status;
  final String message;
  final String? connectionId;
  final String? requestId;
  final String? connectUrl;
  final String? nextAction;

  bool get shouldOpenImport =>
      status == 'connected_import_mode' || nextAction == 'import_reports';

  factory PosConnectionResult.fromJson(Map<String, dynamic> json) {
    return PosConnectionResult(
      status: json['status'] as String? ?? 'unknown',
      message: json['message'] as String? ?? 'POS connection request received.',
      connectionId: json['connection_id'] as String?,
      requestId: json['request_id'] as String?,
      connectUrl: json['connect_url'] as String?,
      nextAction: json['next_action'] as String?,
    );
  }
}

class PosConnectionRequestException implements Exception {
  const PosConnectionRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PosConnectionServiceUnavailableException
    extends PosConnectionRequestException {
  const PosConnectionServiceUnavailableException()
      : super(
          'POS connection service is not deployed yet. Please try again later.',
        );
}
