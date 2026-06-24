import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

enum LocalAuthResult {
  success,
  cancelled,
  failed,
  unavailable,
  notConfigured,
  error,
  skipped,
}

class LocalAuthService {
  LocalAuthService({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  Future<LocalAuthResult> authenticateForSensitiveAction({
    required String reason,
    bool required = true,
    bool biometricOnly = false,
  }) async {
    if (kIsWeb) {
      return required ? LocalAuthResult.unavailable : LocalAuthResult.skipped;
    }

    try {
      final isSupported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;

      if (!isSupported || (biometricOnly && !canCheck)) {
        return required ? LocalAuthResult.unavailable : LocalAuthResult.skipped;
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: false,
          useErrorDialogs: true,
        ),
      );

      return didAuthenticate
          ? LocalAuthResult.success
          : LocalAuthResult.cancelled;
    } on PlatformException catch (e) {
      debugPrint('[LOCAL AUTH] PlatformException: ${e.code}');

      if (e.code == 'NotAvailable' || e.code == 'NotEnrolled') {
        return required ? LocalAuthResult.unavailable : LocalAuthResult.skipped;
      }

      if (e.code == 'PasscodeNotSet') {
        return required
            ? LocalAuthResult.notConfigured
            : LocalAuthResult.skipped;
      }

      if (e.code == 'LockedOut' || e.code == 'PermanentlyLockedOut') {
        return LocalAuthResult.failed;
      }

      return required ? LocalAuthResult.error : LocalAuthResult.skipped;
    } catch (e, st) {
      debugPrint('[LOCAL AUTH] Unexpected error: $e');
      debugPrintStack(stackTrace: st);
      return required ? LocalAuthResult.error : LocalAuthResult.skipped;
    }
  }
}
