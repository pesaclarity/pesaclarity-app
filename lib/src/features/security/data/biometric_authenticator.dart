import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

/// Asks the platform to confirm the person with a strong biometric.
abstract interface class BiometricAuthenticator {
  /// Whether a strong (class 3) biometric is enrolled and usable.
  Future<bool> isAvailable();

  /// Shows the system prompt; true once the person is confirmed.
  Future<bool> authenticate();
}

/// [BiometricAuthenticator] using BiometricPrompt through local_auth.
class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  LocalAuthBiometricAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      final enrolled = await _auth.getAvailableBiometrics();
      if (defaultTargetPlatform == TargetPlatform.android) {
        return enrolled.contains(BiometricType.strong);
      }
      return enrolled.contains(BiometricType.face) ||
          enrolled.contains(BiometricType.fingerprint);
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    // Checked again here: an enrolment can be removed while the app runs.
    if (!await isAvailable()) return false;
    try {
      return await _auth.authenticate(
        localizedReason: 'Confirm it is you to open Pesa Clarity',
        biometricOnly: true,
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Unlock Pesa Clarity',
            cancelButton: 'Use PIN',
          ),
        ],
      );
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }
}

final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>(
  (ref) => LocalAuthBiometricAuthenticator(),
);

/// Whether this phone can offer fingerprint unlock.
final biometricAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(biometricAuthenticatorProvider).isAvailable(),
);
