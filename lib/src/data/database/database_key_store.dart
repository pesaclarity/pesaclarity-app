import 'dart:async';
import 'dart:math';

/// Supplies the 256-bit SQLCipher key for the on-phone database.
abstract interface class DatabaseKeyStore {
  /// Returns the key as 64 hex characters.
  Future<String> readOrCreateKey();
}

/// Holds the database key once app lock releases it.
class ReleasedDatabaseKey {
  String? _key;
  final _released = Completer<String>();

  String? get value => _key;

  /// Completes with the key once app lock releases it.
  Future<String> get released => _released.future;

  void release(String key) {
    _key = key;
    if (!_released.isCompleted) _released.complete(key);
  }
}

/// Hands over the key that app lock released, waiting while it is locked.
///
/// The key itself lives in the Android Keystore-backed vault
/// (features/security/data/key_vault.dart); it reaches this store only after
/// the person unlocks, or straight away when no app lock is set.
///
/// A read that comes before then waits for the key rather than failing:
/// Drift keeps a failed open for the whole session, so one early read (on a
/// new phone the keystore can take a second or more to make the key) would
/// otherwise leave every screen without its records until the app restarts.
class UnlockedDatabaseKeyStore implements DatabaseKeyStore {
  UnlockedDatabaseKeyStore(this._key);

  final ReleasedDatabaseKey _key;

  @override
  Future<String> readOrCreateKey() async => _key.value ?? await _key.released;
}

/// Generates a random 256-bit key as 64 lowercase hex characters.
String generateDatabaseKey([Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(
    32,
    (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
