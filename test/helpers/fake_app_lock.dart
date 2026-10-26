import 'package:flutter_riverpod/misc.dart';
import 'package:pesaclarity/src/features/security/application/app_lock_controller.dart';
import 'package:pesaclarity/src/features/security/data/biometric_authenticator.dart';
import 'package:pesaclarity/src/features/security/data/key_vault.dart';
import 'package:pesaclarity/src/features/security/data/secure_store.dart';
import 'package:pesaclarity/src/features/security/domain/pin_hasher.dart';

/// Biometric prompt stand-in: [available] says whether a fingerprint is
/// enrolled and [accept] whether the next prompt succeeds.
class FakeBiometricAuthenticator implements BiometricAuthenticator {
  FakeBiometricAuthenticator({this.available = false, this.accept = true});

  bool available;
  bool accept;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate() async {
    prompts++;
    return available && accept;
  }
}

/// A cheap Argon2id cost so tests run fast. Never use outside tests.
const testPinKdfParams = PinKdfParams(memoryKiB: 64, iterations: 1);

/// A [KeyVault] on [store] that hashes PINs quickly and on the test thread.
KeyVault testKeyVault(SecureStore store) => KeyVault(
  store,
  hasher: const PinHasher(useIsolate: false),
  kdfParams: testPinKdfParams,
);

/// Provider overrides that run app lock on [store] and [biometrics].
List<Override> appLockOverrides({
  SecureStore? store,
  BiometricAuthenticator? biometrics,
}) {
  final secure = store ?? MemorySecureStore();
  return [
    secureStoreProvider.overrideWithValue(secure),
    keyVaultProvider.overrideWithValue(testKeyVault(secure)),
    biometricAuthenticatorProvider.overrideWithValue(
      biometrics ?? FakeBiometricAuthenticator(),
    ),
  ];
}
