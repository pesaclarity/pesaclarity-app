import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/server_config.dart';
import '../../../core/network/pinned_http_client.dart';
import '../../../core/time/clock.dart';
import '../data/auth_api.dart';
import '../data/device_name.dart';
import '../data/google_id_token_source.dart';
import '../data/http_auth_api.dart';
import '../data/json_transport.dart';
import '../data/session_store.dart';
import '../domain/auth_models.dart';
import '../domain/phone_number.dart';

/// The server's auth API, or a stand-in when the build has no server URL.
final authApiProvider = Provider<AuthApi>((ref) {
  final baseUrl = ref.watch(serverBaseUrlProvider);
  if (baseUrl == null) return const UnconfiguredAuthApi();
  return HttpAuthApi(
    baseUrl: baseUrl,
    transport: IoJsonTransport(
      client: ref.watch(httpClientFactoryProvider).create(),
    ),
  );
});

/// Where the refresh token is kept between launches.
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SecureSessionStore(),
);

final deviceNameSourceProvider = Provider<DeviceNameSource>(
  (ref) => const PlatformDeviceNameSource(),
);

/// Google sign-in. Unavailable in foss builds, and in play builds until the
/// Credential Manager integration lands.
final googleIdTokenSourceProvider = Provider<GoogleIdTokenSource>(
  (ref) => const UnavailableGoogleIdTokenSource(),
);

/// The signed-in account, as shown in Profile.
@immutable
class AccountSession {
  const AccountSession({
    required this.accountId,
    required this.deviceId,
    this.method,
    this.contact,
    this.displayName,
  });

  factory AccountSession.fromStored(StoredSession stored) => AccountSession(
    accountId: stored.accountId,
    deviceId: stored.deviceId,
    method: stored.method,
    contact: stored.contact,
    displayName: stored.displayName,
  );

  final String accountId;
  final String deviceId;
  final SignInMethod? method;

  /// The phone number used to sign in, in E.164 form, if any.
  final String? contact;

  final String? displayName;
}

/// Sign-in state: the signed-in account, or null when using the app without
/// one. Holds the short-lived access token in memory only.
class AuthController extends AsyncNotifier<AccountSession?> {
  String? _accessToken;
  DateTime? _accessExpiresAt;
  Future<String>? _refreshing;

  /// Refresh this long before the server's expiry, to allow for clock skew.
  static const _expiryMargin = Duration(seconds: 30);

  AuthApi get _api => ref.read(authApiProvider);
  SessionStore get _store => ref.read(sessionStoreProvider);
  DateTime _now() => ref.read(clockProvider)();

  @override
  Future<AccountSession?> build() async {
    try {
      final stored = await _store.read();
      return stored == null ? null : AccountSession.fromStored(stored);
    } on Object {
      // Unreadable storage means signed out, never a broken app.
      return null;
    }
  }

  AccountSession? get _session => state.value;

  /// Texts a sign-in code to [input], a Kenyan mobile number as typed.
  Future<PhoneChallenge> startPhoneSignIn(String input) {
    final phone = normaliseKenyanMobile(input);
    if (phone == null) {
      throw const AuthFailure(AuthFailureKind.invalidPhone);
    }
    return _api.startPhoneSignIn(phone);
  }

  /// Checks [code] against [challenge] and signs in.
  Future<void> verifyPhoneCode(PhoneChallenge challenge, String code) async {
    final digits = code.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6,8}$').hasMatch(digits)) {
      throw const AuthFailure(AuthFailureKind.invalidCode);
    }
    final tokens = await _api.verifyPhoneSignIn(
      challengeId: challenge.challengeId,
      code: digits,
      deviceName: await ref.read(deviceNameSourceProvider).deviceName(),
    );
    await _establish(tokens, SignInMethod.phone, contact: challenge.phone);
  }

  /// Signs in with Google. Returns false when the person cancels.
  Future<bool> signInWithGoogle() async {
    final google = ref.read(googleIdTokenSourceProvider);
    if (!google.isAvailable) {
      throw const AuthFailure(AuthFailureKind.unavailable);
    }
    final idToken = await google.requestIdToken();
    if (idToken == null) return false;
    final tokens = await _api.signInWithGoogle(
      idToken: idToken,
      deviceName: await ref.read(deviceNameSourceProvider).deviceName(),
    );
    await _establish(tokens, SignInMethod.google);
    return true;
  }

  /// Signs this phone out. Local tokens are always removed; returns whether
  /// the server also confirmed it.
  Future<bool> signOut() async {
    if (_session == null) return true;
    var confirmed = false;
    try {
      await _authorised((api, token) => api.signOut(token));
      confirmed = true;
    } on AuthFailure catch (failure) {
      confirmed = failure.kind == AuthFailureKind.sessionEnded;
    }
    await _endLocally();
    return confirmed;
  }

  /// Deletes the account on the server, then signs out here.
  Future<void> deleteAccount() async {
    await _authorised((api, token) => api.deleteAccount(token));
    await _endLocally();
  }

  /// Phones signed in to this account, this one included.
  Future<List<SignedInDevice>> devices() =>
      _authorised((api, token) => api.listDevices(token));

  /// Signs another phone out of this account.
  Future<void> signOutDevice(String deviceId) =>
      _authorised((api, token) => api.revokeDevice(token, deviceId));

  Future<void> _establish(
    TokenPair tokens,
    SignInMethod method, {
    String? contact,
  }) async {
    final stored = StoredSession(
      refreshToken: tokens.refreshToken,
      accountId: tokens.accountId,
      deviceId: tokens.deviceId,
      method: method,
      contact: contact,
      displayName: tokens.displayName,
    );
    await _store.write(stored);
    _keepAccessToken(tokens);
    state = AsyncData(AccountSession.fromStored(stored));
    if (tokens.displayName == null) unawaited(_loadDisplayName());
  }

  Future<void> _loadDisplayName() async {
    try {
      final account = await _authorised((api, token) => api.getAccount(token));
      final name = account.displayName;
      final stored = await _store.read();
      if (name == null || stored == null) return;
      final updated = stored.copyWith(displayName: name);
      await _store.write(updated);
      state = AsyncData(AccountSession.fromStored(updated));
    } on Object {
      // Optional; the greeting falls back to a plain "Hi".
    }
  }

  void _keepAccessToken(TokenPair tokens) {
    _accessToken = tokens.accessToken;
    _accessExpiresAt = _now().add(tokens.expiresIn - _expiryMargin);
  }

  Future<void> _endLocally() async {
    _accessToken = null;
    _accessExpiresAt = null;
    try {
      await _store.clear();
    } on Object {
      // Nothing more to do; the token is unusable once the server revokes it.
    }
    state = const AsyncData(null);
  }

  /// Runs [call] with a valid access token, refreshing once on a 401.
  Future<T> _authorised<T>(
    Future<T> Function(AuthApi api, String token) call,
  ) async {
    if (_session == null) {
      throw const AuthFailure(AuthFailureKind.sessionEnded);
    }
    final api = _api;
    // A failed refresh has already ended the session, so it propagates as is.
    final token = await _validAccessToken();
    try {
      return await call(api, token);
    } on AuthFailure catch (failure) {
      if (failure.kind != AuthFailureKind.sessionEnded) rethrow;
    }
    // The access token was rejected early, for example after a server
    // restart; a refresh tells a revoked device apart from that.
    _accessToken = null;
    try {
      return await call(api, await _validAccessToken());
    } on AuthFailure catch (failure) {
      if (failure.kind == AuthFailureKind.sessionEnded) await _endLocally();
      rethrow;
    }
  }

  Future<String> _validAccessToken() {
    final token = _accessToken;
    final expiresAt = _accessExpiresAt;
    if (token != null && expiresAt != null && _now().isBefore(expiresAt)) {
      return Future.value(token);
    }
    // One refresh at a time: reusing a rotated token signs the device out.
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh() async {
    final stored = await _store.read();
    if (stored == null) {
      await _endLocally();
      throw const AuthFailure(AuthFailureKind.sessionEnded);
    }
    final TokenPair tokens;
    try {
      tokens = await _api.refresh(stored.refreshToken);
    } on AuthFailure catch (failure) {
      if (failure.kind == AuthFailureKind.sessionEnded) await _endLocally();
      rethrow;
    }
    final updated = stored.copyWith(
      refreshToken: tokens.refreshToken,
      displayName: tokens.displayName,
    );
    await _store.write(updated);
    _keepAccessToken(tokens);
    if (tokens.displayName != null &&
        tokens.displayName != _session?.displayName) {
      state = AsyncData(AccountSession.fromStored(updated));
    }
    return tokens.accessToken;
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AccountSession?>(AuthController.new);

/// The signed-in person's name for the Home greeting ("Hi, John"), or null.
final displayNameProvider = Provider<String?>(
  (ref) => ref.watch(authControllerProvider).value?.displayName,
);
