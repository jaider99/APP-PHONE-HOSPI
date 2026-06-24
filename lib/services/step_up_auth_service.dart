import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hospi_dash/core/security/local_auth_service.dart';
import 'package:hospi_dash/core/utils/app_logger.dart';

final localAuthServiceProvider = Provider<LocalAuthService>((ref) {
  return LocalAuthService();
});

final stepUpAuthServiceProvider = Provider<StepUpAuthService>((ref) {
  return StepUpAuthService(ref.watch(localAuthServiceProvider));
});

enum StepUpAction {
  deleteDocument,
  inviteUser,
  removeMember,
  changeMemberRole,
  resolvePriceAnomaly,
  approvePriceAnomalyBaseline,
  exportData,
  changeCompanySettings,
  deleteSalesData,
  managePosConnection,
}

extension StepUpActionLabel on StepUpAction {
  String get reason {
    return switch (this) {
      StepUpAction.deleteDocument =>
        'Confirm your identity with biometrics or device passcode to delete this document.',
      StepUpAction.inviteUser =>
        'Confirm your identity with biometrics or device passcode to invite a company member.',
      StepUpAction.removeMember =>
        'Confirm your identity with biometrics or device passcode to remove a company member.',
      StepUpAction.changeMemberRole =>
        'Confirm your identity with biometrics or device passcode to change a member role.',
      StepUpAction.resolvePriceAnomaly =>
        'Confirm your identity with biometrics or device passcode to resolve this price anomaly.',
      StepUpAction.approvePriceAnomalyBaseline =>
        'Confirm your identity with biometrics or device passcode to approve this price baseline.',
      StepUpAction.exportData =>
        'Confirm your identity with biometrics or device passcode to export company data.',
      StepUpAction.changeCompanySettings =>
        'Confirm your identity with biometrics or device passcode to change company settings.',
      StepUpAction.deleteSalesData =>
        'Confirm your identity with biometrics or device passcode to delete sales data.',
      StepUpAction.managePosConnection =>
        'Confirm your identity with biometrics or device passcode to manage this POS connection.',
    };
  }

  String get logName => switch (this) {
        StepUpAction.deleteDocument => 'delete_document',
        StepUpAction.inviteUser => 'invite_user',
        StepUpAction.removeMember => 'remove_member',
        StepUpAction.changeMemberRole => 'change_member_role',
        StepUpAction.resolvePriceAnomaly => 'resolve_price_anomaly',
        StepUpAction.approvePriceAnomalyBaseline =>
          'approve_price_anomaly_baseline',
        StepUpAction.exportData => 'export_data',
        StepUpAction.changeCompanySettings => 'change_company_settings',
        StepUpAction.deleteSalesData => 'delete_sales_data',
        StepUpAction.managePosConnection => 'manage_pos_connection',
      };
}

class StepUpAuthException implements Exception {
  const StepUpAuthException(this.message, {required this.result});

  final String message;
  final LocalAuthResult result;

  @override
  String toString() => message;
}

class StepUpAuthService {
  StepUpAuthService(
    this._localAuthService, {
    this.recentAuthDuration = const Duration(minutes: 5),
  });

  final LocalAuthService _localAuthService;
  final Duration recentAuthDuration;
  DateTime? _lastStepUpAt;

  bool get hasRecentStepUp {
    final lastStepUpAt = _lastStepUpAt;
    if (lastStepUpAt == null) return false;
    return DateTime.now().difference(lastStepUpAt) < recentAuthDuration;
  }

  Future<void> requireStepUp({
    required StepUpAction action,
    bool biometricOnly = false,
    bool force = false,
    bool required = true,
  }) async {
    if (!force && hasRecentStepUp) {
      AppLogger.debug(
        '[StepUpAuthService] Recent step-up reused for ${action.logName}',
      );
      return;
    }

    final authResult = await _localAuthService.authenticateForSensitiveAction(
      reason: action.reason,
      required: required,
      biometricOnly: biometricOnly,
    );

    if (authResult == LocalAuthResult.skipped) {
      AppLogger.warning(
        '[StepUpAuthService] Step-up skipped (local auth unavailable, not required) for ${action.logName}',
      );
      return;
    }

    if (authResult != LocalAuthResult.success) {
      AppLogger.warning(
        '[StepUpAuthService] Step-up authentication ${authResult.name} for ${action.logName}',
      );
      throw StepUpAuthException(
        _messageForResult(authResult, action),
        result: authResult,
      );
    }

    _lastStepUpAt = DateTime.now();
    AppLogger.info(
      '[StepUpAuthService] Step-up authentication completed for ${action.logName}',
    );
  }

  void expire() {
    _lastStepUpAt = null;
  }

  String _messageForResult(LocalAuthResult result, StepUpAction action) {
    final isDelete = action == StepUpAction.deleteDocument ||
        action == StepUpAction.deleteSalesData;

    return switch (result) {
      LocalAuthResult.cancelled =>
        isDelete ? 'Delete cancelled' : 'Action cancelled',
      LocalAuthResult.failed => isDelete
          ? 'Authentication failed. Document was not deleted.'
          : 'Authentication failed. No changes were made.',
      LocalAuthResult.unavailable =>
        'Authentication is unavailable. Use your device passcode or try again.',
      LocalAuthResult.notConfigured =>
        'Device authentication is not configured. Set up a passcode and try again.',
      LocalAuthResult.error =>
        "We couldn't verify your identity. Please try again.",
      LocalAuthResult.success || LocalAuthResult.skipped => '',
    };
  }
}
