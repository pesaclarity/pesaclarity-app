import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/database_key_store.dart';
import 'package:pesaclarity/src/features/security/data/key_vault.dart';
import 'package:pesaclarity/src/features/security/data/secure_store.dart';
import 'package:pesaclarity/src/features/security/domain/lock_settings.dart';
import 'package:pesaclarity/src/features/security/domain/pin_hasher.dart';
import 'package:pesaclarity/src/features/security/domain/unlock_delay.dart';

import '../../helpers/fake_app_lock.dart';

void main() {
  late MemorySecureStore store;
  late KeyVault vault;

  setUp(() {
    store = MemorySecureStore();
    vault = testKeyVault(store);
  });

  group('without a PIN', () {
    test('creates the key once and keeps it', () async {
      final key = await vault.readOrCreateOpenKey();
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(await vault.readOrCreateOpenKey(), key);
      expect((await vault.readSettings()).pinSet, isFalse);
    });

    test('keeps the key an earlier version stored', () async {
      final key = generateDatabaseKey();
      store.values[KeyVault.plainKeyName] = key;
      expect(await vault.readOrCreateOpenKey(), key);
    });
  });

  group('with a PIN', () {
    late String key;

    setUp(() async {
      key = await vault.readOrCreateOpenKey();
      await vault.setPin('246810', key);
    });

    test('removes the open copy and stores neither PIN nor key', () async {
      expect(store.values.containsKey(KeyVault.plainKeyName), isFalse);
      final stored = store.values.values.join();
      expect(stored, isNot(contains('246810')));
      expect(stored, isNot(contains(key)));
      expect((await vault.readSettings()).pinSet, isTrue);
    });

    test('releases the key only for the right PIN', () async {
      expect(await vault.unlockWithPin('246810'), key);
      expect(await vault.unlockWithPin('246811'), isNull);
      expect(await vault.unlockWithPin('000000'), isNull);
    });

    test('refuses to hand out the key without the PIN', () async {
      expect(vault.readOrCreateOpenKey, throwsStateError);
    });

    test('salts each PIN differently', () async {
      final first = store.values[KeyVault.pinRecordName];
      await vault.setPin('246810', key);
      expect(store.values[KeyVault.pinRecordName], isNot(first));
      expect(await vault.unlockWithPin('246810'), key);
    });

    test('changing the PIN keeps the same database key', () async {
      await vault.setPin('135790', key);
      expect(await vault.unlockWithPin('246810'), isNull);
      expect(await vault.unlockWithPin('135790'), key);
    });

    test('turning the lock off puts the key back', () async {
      await vault.enableBiometric(key);
      await vault.removePin(key);
      expect(await vault.readOrCreateOpenKey(), key);
      expect(await vault.readBiometricKey(), isNull);
      expect((await vault.readSettings()).pinSet, isFalse);
    });

    test('tidies up an open copy left by an interrupted change', () async {
      store.values[KeyVault.plainKeyName] = key;
      await vault.readSettings();
      expect(store.values.containsKey(KeyVault.plainKeyName), isFalse);
    });

    test('rejects a PIN of the wrong length', () {
      expect(() => vault.setPin('1234', key), throwsArgumentError);
    });
  });

  test('saves settings and wrong-PIN counts', () async {
    await vault.readOrCreateOpenKey();
    await vault.setPin('246810', generateDatabaseKey());
    await vault.writeSettings(
      const LockSettings(
        pinSet: true,
        biometricEnabled: true,
        lockAfter: Duration(minutes: 5),
        hideBalancesOnOpen: true,
      ),
    );
    final settings = await vault.readSettings();
    expect(settings.biometricEnabled, isTrue);
    expect(settings.lockAfter, const Duration(minutes: 5));
    expect(settings.hideBalancesOnOpen, isTrue);

    final at = DateTime.utc(2026, 10, 26, 8);
    await vault.writeAttempts(PinAttempts(failed: 5, retryAt: at));
    final attempts = await vault.readAttempts();
    expect(attempts.failed, 5);
    expect(attempts.retryAt, at);
    await vault.clearAttempts();
    expect((await vault.readAttempts()).failed, 0);
  });

  test('fingerprint unlock is off whenever no PIN is set', () async {
    await vault.writeSettings(const LockSettings(biometricEnabled: true));
    expect((await vault.readSettings()).biometricEnabled, isFalse);
  });

  test('the real Argon2id cost runs off the UI thread', () async {
    const hasher = PinHasher();
    final salt = List.filled(16, 7);
    final a = await hasher.derive('246810', salt, PinKdfParams.recommended);
    final b = await hasher.derive('246810', salt, PinKdfParams.recommended);
    final c = await hasher.derive('246811', salt, PinKdfParams.recommended);
    expect(constantTimeEquals(a.verifier, b.verifier), isTrue);
    expect(constantTimeEquals(a.verifier, c.verifier), isFalse);
    expect(a.verifier, isNot(a.wrappingKey));
  });

  test('waits grow after the free tries, up to an hour', () {
    expect(
      [for (var n = 1; n <= 11; n++) unlockDelayAfter(n)],
      const [
        Duration.zero,
        Duration.zero,
        Duration.zero,
        Duration.zero,
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(minutes: 5),
        Duration(minutes: 15),
        Duration(hours: 1),
        Duration(hours: 1),
        Duration(hours: 1),
      ],
    );
  });

  test('PINs are six digits', () {
    expect(isValidPin('012345'), isTrue);
    expect(isValidPin('12345'), isFalse);
    expect(isValidPin('12345a'), isFalse);
  });
}
