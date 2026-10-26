import 'dart:math';

/// Supplies the 256-bit SQLCipher key for the on-phone database.
abstract interface class DatabaseKeyStore {
  /// Returns the key as 64 hex characters.
  Future<String> readOrCreateKey();
}

/// Hands over the key that app lock released, and refuses while locked.
///
/// The key itself lives in the Android Keystore-backed vault
/// (features/security/data/key_vault.dart); it reaches this store only after
/// the person unlocks, or straight away when no app lock is set.
class UnlockedDatabaseKeyStore implements DatabaseKeyStore {
  UnlockedDatabaseKeyStore(this._releasedKey);

  final String? Function() _releasedKey;

  @override
  Future<String> readOrCreateKey() async {
    final key = _releasedKey();
    if (key == null) {
      throw StateError('The database is locked; unlock the app first');
    }
    return key;
  }
}

/// Generates a random 256-bit key as 64 lowercase hex characters.
String generateDatabaseKey([Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(
    32,
    (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
