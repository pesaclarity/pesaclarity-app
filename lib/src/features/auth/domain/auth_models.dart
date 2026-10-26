import 'package:flutter/foundation.dart';

/// How an account signs in. Matches the server's `contact_kind`.
enum SignInMethod {
  phone,
  google;

  static SignInMethod? fromName(String? name) => switch (name) {
    'phone' => SignInMethod.phone,
    'google' => SignInMethod.google,
    _ => null,
  };
}

/// A one-time code sent by SMS, waiting to be verified.
@immutable
class PhoneChallenge {
  const PhoneChallenge({
    required this.challengeId,
    required this.phone,
    required this.expiresIn,
  });

  final String challengeId;

  /// The number the code went to, in international form (+254...).
  final String phone;

  final Duration expiresIn;
}

/// Tokens returned by every sign-in and refresh (`TokenPair` on the server).
@immutable
class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.accountId,
    required this.deviceId,
    this.displayName,
  });

  factory TokenPair.fromJson(Map<String, Object?> json) => TokenPair(
    accessToken: json['access_token']! as String,
    refreshToken: json['refresh_token']! as String,
    expiresIn: Duration(seconds: (json['expires_in']! as num).toInt()),
    accountId: json['account_id']! as String,
    deviceId: json['device_id']! as String,
    displayName: _nonEmpty(json['display_name']),
  );

  final String accessToken;
  final String refreshToken;
  final Duration expiresIn;
  final String accountId;
  final String deviceId;

  /// The person's name, when the server provides one.
  final String? displayName;
}

/// The signed-in account as the server describes it (`GET /v1/account`).
@immutable
class AccountInfo {
  const AccountInfo({
    required this.id,
    required this.method,
    required this.createdAt,
    this.displayName,
  });

  factory AccountInfo.fromJson(Map<String, Object?> json) => AccountInfo(
    id: json['id']! as String,
    method: SignInMethod.fromName(json['contact_kind'] as String?),
    createdAt: DateTime.parse(json['created_at']! as String),
    displayName: _nonEmpty(json['display_name']),
  );

  final String id;
  final SignInMethod? method;
  final DateTime createdAt;
  final String? displayName;
}

/// A phone signed in to the account (`DeviceOut` on the server).
@immutable
class SignedInDevice {
  const SignedInDevice({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.lastSeenAt,
    required this.current,
  });

  factory SignedInDevice.fromJson(Map<String, Object?> json) => SignedInDevice(
    id: json['id']! as String,
    name: json['name']! as String,
    createdAt: DateTime.parse(json['created_at']! as String),
    lastSeenAt: DateTime.parse(json['last_seen_at']! as String),
    current: json['current']! as bool,
  );

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime lastSeenAt;

  /// Whether this is the phone the app is running on.
  final bool current;
}

/// Why an account request failed.
enum AuthFailureKind {
  /// No server is configured in this build.
  notConfigured,

  /// The server could not be reached.
  network,

  /// The phone number was rejected.
  invalidPhone,

  /// Too many codes were requested.
  rateLimited,

  /// The SMS code is wrong or has expired.
  invalidCode,

  /// The session has ended: signed out remotely, or the refresh token expired.
  sessionEnded,

  /// The sign-in method is switched off on the server or missing in this build.
  unavailable,

  /// The device or account no longer exists.
  notFound,

  /// Anything else the server returned.
  server,
}

/// A failed account request, with a message fit to show the person.
class AuthFailure implements Exception {
  const AuthFailure(this.kind, [this.serverMessage]);

  final AuthFailureKind kind;

  /// The server's `detail`, kept for logs and tests.
  final String? serverMessage;

  String get message => switch (kind) {
    AuthFailureKind.notConfigured =>
      'Accounts arrive in a later update. The app works fully without one.',
    AuthFailureKind.network =>
      'Could not reach Pesa Clarity. Check your connection and try again.',
    AuthFailureKind.invalidPhone =>
      'Enter a Kenyan mobile number, for example 712 345 678.',
    AuthFailureKind.rateLimited =>
      'Too many codes requested. Try again in an hour.',
    AuthFailureKind.invalidCode =>
      'That code is wrong or has expired. Check it, or send a new one.',
    AuthFailureKind.sessionEnded => 'You were signed out. Sign in again.',
    AuthFailureKind.unavailable =>
      'This way of signing in arrives in a later update. Use your phone '
          'number for now.',
    AuthFailureKind.notFound => 'That phone is already signed out.',
    AuthFailureKind.server => 'Something went wrong. Try again in a moment.',
  };

  @override
  String toString() => 'AuthFailure($kind, $serverMessage)';
}

String? _nonEmpty(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
