import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart' as local_auth;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/models/auth_result.dart';

// ============================================================================
// iOS Setup: Add to ios/Runner/Info.plist:
// <key>NSFaceIDUsageDescription</key>
// <string>Use Face ID to sign in faster</string>
//
// Android Setup: Add to android/app/src/main/AndroidManifest.xml:
// <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
// <uses-permission android:name="android.permission.USE_FINGERPRINT"/>
// ============================================================================

/// Storage keys for biometric data
abstract class _BiometricKeys {
  static const String refreshToken = 'auth_refresh_token';
  static const String biometricsEnabled = 'biometrics_enabled';
  static const String lastAuthUserId = 'last_auth_user_id';
}

/// Type of biometric available on the device
enum BiometricType {
  fingerprint,
  faceId,
  iris,
  none,
}

/// Service for handling biometric authentication
/// Allows users to enable Face ID / Touch ID / Fingerprint for quick sign-in
class BiometricService {
  BiometricService({
    local_auth.LocalAuthentication? localAuth,
    FlutterSecureStorage? secureStorage,
  })  : _localAuth = localAuth ?? local_auth.LocalAuthentication(),
        _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final local_auth.LocalAuthentication _localAuth;
  final FlutterSecureStorage _secureStorage;
  SharedPreferences? _prefs;

  /// Lazily initialize SharedPreferences
  Future<SharedPreferences> get _sharedPrefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Check if biometric authentication is available on this device
  Future<bool> isBiometricAvailable() async {
    // Skip biometrics on web
    if (kIsWeb) return false;

    try {
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;

      if (!isDeviceSupported || !canCheckBiometrics) {
        return false;
      }

      // Check if any biometrics are enrolled
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      return availableBiometrics.isNotEmpty;
    } on PlatformException catch (e) {
      debugPrint('Biometric check failed: ${e.message}');
      return false;
    }
  }

  /// Get the primary biometric type available on this device
  Future<BiometricType> getAvailableBiometricType() async {
    if (kIsWeb) return BiometricType.none;

    try {
      final availableBiometrics = await _localAuth.getAvailableBiometrics();

      if (availableBiometrics.isEmpty) {
        return BiometricType.none;
      }

      // Prioritize Face ID on iOS, fingerprint elsewhere
      if (Platform.isIOS) {
        if (availableBiometrics.contains(local_auth.BiometricType.face) ||
            availableBiometrics.any((b) => b.name.toLowerCase().contains('face'))) {
          return BiometricType.faceId;
        }
      }

      if (availableBiometrics.contains(local_auth.BiometricType.fingerprint) ||
          availableBiometrics.any((b) => b.name.toLowerCase().contains('finger'))) {
        return BiometricType.fingerprint;
      }

      if (availableBiometrics.contains(local_auth.BiometricType.iris)) {
        return BiometricType.iris;
      }

      // Default to fingerprint if we have biometrics but can't determine type
      return BiometricType.fingerprint;
    } on PlatformException {
      return BiometricType.none;
    }
  }

  /// Get a user-friendly name for the biometric type
  Future<String> getBiometricLabel() async {
    final type = await getAvailableBiometricType();

    return switch (type) {
      BiometricType.faceId => 'Face ID',
      BiometricType.fingerprint =>
        Platform.isIOS ? 'Touch ID' : 'Fingerprint',
      BiometricType.iris => 'Iris',
      BiometricType.none => 'Biometric',
    };
  }

  /// Authenticate user with biometrics
  /// Returns true if authenticated, false if cancelled or failed
  Future<bool> authenticate({
    String? localizedReason,
    bool biometricOnly = false,
  }) async {
    if (kIsWeb) return false;

    final biometricLabel = await getBiometricLabel();
    final reason = localizedReason ?? 'Authenticate to sign in with $biometricLabel';

    try {
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
        options: local_auth.AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,
        ),
      );

      return didAuthenticate;
    } on PlatformException catch (e) {
      debugPrint('Biometric authentication failed: ${e.message}');
      return false;
    }
  }

  /// Check if biometrics are enabled for this user
  Future<bool> isBiometricsEnabled() async {
    final prefs = await _sharedPrefs;
    return prefs.getBool(_BiometricKeys.biometricsEnabled) ?? false;
  }

  /// Enable biometric login for the current session
  /// Stores the refresh token securely for later use
  Future<void> enableBiometrics(Session session) async {
    final prefs = await _sharedPrefs;

    // Store refresh token securely
    await _secureStorage.write(
      key: _BiometricKeys.refreshToken,
      value: session.refreshToken,
    );

    // Store user ID for validation
    await _secureStorage.write(
      key: _BiometricKeys.lastAuthUserId,
      value: session.user.id,
    );

    // Enable flag
    await prefs.setBool(_BiometricKeys.biometricsEnabled, true);
  }

  /// Disable biometric login
  /// Clears stored tokens
  Future<void> disableBiometrics() async {
    final prefs = await _sharedPrefs;

    // Clear stored tokens
    await _secureStorage.delete(key: _BiometricKeys.refreshToken);
    await _secureStorage.delete(key: _BiometricKeys.lastAuthUserId);

    // Disable flag
    await prefs.setBool(_BiometricKeys.biometricsEnabled, false);
  }

  /// Clear all biometric data (used on sign out)
  Future<void> clearBiometricData() async {
    await disableBiometrics();
  }

  /// Attempt to login using stored biometric credentials
  /// Returns AuthResult indicating success or failure
  Future<AuthResult> loginWithBiometrics() async {
    // Check if biometrics are enabled
    final isEnabled = await isBiometricsEnabled();
    if (!isEnabled) {
      return const AuthResult.failure('Biometric login is not enabled.');
    }

    // Authenticate with biometrics
    final authenticated = await authenticate(
      localizedReason: 'Sign in to HospiDash',
    );

    if (!authenticated) {
      return const AuthResult.failure('Biometric authentication cancelled.');
    }

    // Retrieve stored refresh token
    final refreshToken = await _secureStorage.read(
      key: _BiometricKeys.refreshToken,
    );

    if (refreshToken == null || refreshToken.isEmpty) {
      // Token not found, disable biometrics and require regular sign in
      await disableBiometrics();
      return const AuthResult.failure(
        'Biometric session expired. Please sign in with your password.',
      );
    }

    try {
      // Restore session using refresh token
      final response = await SupabaseService.client.auth.setSession(refreshToken);

      if (response.session == null) {
        await disableBiometrics();
        return const AuthResult.failure(
          'Session could not be restored. Please sign in again.',
        );
      }

      // Update stored token with new one
      await enableBiometrics(response.session!);

      return AuthResult.success(response.session!);
    } on AuthException catch (e) {
      // Token likely expired or revoked
      await disableBiometrics();
      return AuthResult.failure(e.userFriendlyMessage);
    } catch (e) {
      return const AuthResult.failure('Biometric sign in failed. Please try again.');
    }
  }

  /// Check if the stored biometric session belongs to a specific user
  Future<bool> hasStoredSessionForUser(String userId) async {
    final storedUserId = await _secureStorage.read(
      key: _BiometricKeys.lastAuthUserId,
    );
    return storedUserId == userId;
  }

  /// Get whether biometric prompt should be shown on sign-in screen
  Future<bool> shouldShowBiometricPrompt() async {
    final isAvailable = await isBiometricAvailable();
    final isEnabled = await isBiometricsEnabled();
    return isAvailable && isEnabled;
  }
}
