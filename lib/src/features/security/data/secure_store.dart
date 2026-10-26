import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small key-value store for secrets and lock settings.
///
/// On Android the values are encrypted with a key held in the Android
/// Keystore.
abstract interface class SecureStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// [SecureStore] backed by flutter_secure_storage.
class FlutterSecureStore implements SecureStore {
  FlutterSecureStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// In-memory [SecureStore] for tests.
class MemorySecureStore implements SecureStore {
  MemorySecureStore([Map<String, String>? values]) : values = values ?? {};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

final secureStoreProvider = Provider<SecureStore>(
  (ref) => FlutterSecureStore(),
);
