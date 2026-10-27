import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/auth_models.dart';

/// What the phone keeps between launches for a signed-in account.
///
/// The access token is deliberately absent: it lives in memory only.
@immutable
class StoredSession {
  const StoredSession({
    required this.refreshToken,
    required this.accountId,
    required this.deviceId,
    this.method,
    this.contact,
    this.displayName,
  });

  factory StoredSession.fromJson(Map<String, Object?> json) => StoredSession(
    refreshToken: json['refreshToken']! as String,
    accountId: json['accountId']! as String,
    deviceId: json['deviceId']! as String,
    method: SignInMethod.fromName(json['method'] as String?),
    contact: json['contact'] as String?,
    displayName: json['displayName'] as String?,
  );

  final String refreshToken;
  final String accountId;
  final String deviceId;
  final SignInMethod? method;

  /// The email address used to sign in, shown in Profile.
  final String? contact;

  final String? displayName;

  StoredSession copyWith({String? refreshToken, String? displayName}) =>
      StoredSession(
        refreshToken: refreshToken ?? this.refreshToken,
        accountId: accountId,
        deviceId: deviceId,
        method: method,
        contact: contact,
        displayName: displayName ?? this.displayName,
      );

  Map<String, Object?> toJson() => {
    'refreshToken': refreshToken,
    'accountId': accountId,
    'deviceId': deviceId,
    'method': method?.name,
    'contact': contact,
    'displayName': displayName,
  };
}

/// Persists the [StoredSession] (and so the refresh token).
abstract interface class SessionStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

/// Keeps the session in Android Keystore-backed secure storage
/// (AES-GCM data key wrapped by a Keystore key).
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _keyName = 'pesaclarity.auth.session.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredSession?> read() async {
    final raw = await _storage.read(key: _keyName);
    if (raw == null) return null;
    try {
      return StoredSession.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      // A damaged entry is useless; start signed out.
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(StoredSession session) =>
      _storage.write(key: _keyName, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _keyName);
}
