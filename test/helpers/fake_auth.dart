import 'package:pesaclarity/src/features/auth/data/auth_api.dart';
import 'package:pesaclarity/src/features/auth/data/device_name.dart';
import 'package:pesaclarity/src/features/auth/data/google_id_token_source.dart';
import 'package:pesaclarity/src/features/auth/data/session_store.dart';
import 'package:pesaclarity/src/features/auth/domain/auth_models.dart';

/// [SessionStore] in memory, standing in for Keystore-backed storage.
class InMemorySessionStore implements SessionStore {
  InMemorySessionStore([this.session]);

  StoredSession? session;
  int writes = 0;

  @override
  Future<StoredSession?> read() async => session;

  @override
  Future<void> write(StoredSession session) async {
    writes++;
    this.session = session;
  }

  @override
  Future<void> clear() async => session = null;
}

class FakeDeviceNameSource implements DeviceNameSource {
  const FakeDeviceNameSource([this.name = 'Tecno Spark 20']);

  final String name;

  @override
  Future<String> deviceName() async => name;
}

class FakeGoogleIdTokenSource implements GoogleIdTokenSource {
  FakeGoogleIdTokenSource({this.idToken = 'google-id-token'});

  /// What the picker returns; null means the person cancelled.
  String? idToken;

  @override
  bool get isAvailable => true;

  @override
  Future<String?> requestIdToken() async => idToken;
}

/// An in-memory server that follows the real one's rules: six-digit codes,
/// refresh token rotation with reuse detection, and device revocation.
class FakeAuthApi implements AuthApi {
  FakeAuthApi({
    this.code = '123456',
    this.displayName,
    this.accessTtl = const Duration(minutes: 10),
  });

  final String code;
  String? displayName;
  Duration accessTtl;

  /// Set to make every call fail as if offline.
  bool offline = false;

  final calls = <String>[];
  final devices = <String, SignedInDevice>{};
  final revoked = <String>{};
  bool accountDeleted = false;

  final _refreshTokens = <String, String>{}; // token -> device id
  final _usedRefreshTokens = <String>{};
  final _accessTokens = <String, String>{}; // token -> device id
  var _serial = 0;

  void _check(String name) {
    calls.add(name);
    if (offline) throw const AuthFailure(AuthFailureKind.network);
  }

  String _deviceFor(String accessToken) {
    final device = _accessTokens[accessToken];
    if (device == null || revoked.contains(device) || accountDeleted) {
      throw const AuthFailure(AuthFailureKind.sessionEnded);
    }
    return device;
  }

  TokenPair _issue(String deviceId) {
    _serial++;
    final access = 'access-$_serial';
    final refresh = 'refresh-$_serial';
    _accessTokens[access] = deviceId;
    _refreshTokens[refresh] = deviceId;
    return TokenPair(
      accessToken: access,
      refreshToken: refresh,
      expiresIn: accessTtl,
      accountId: 'account-1',
      deviceId: deviceId,
      displayName: displayName,
    );
  }

  TokenPair _signIn(String deviceName) {
    final id = 'device-${devices.length + 1}';
    final now = DateTime.utc(2026, 10, 2);
    devices[id] = SignedInDevice(
      id: id,
      name: deviceName,
      createdAt: now,
      lastSeenAt: now,
      current: false,
    );
    return _issue(id);
  }

  /// Adds another phone to the account, as if signed in elsewhere.
  void addOtherDevice(String id, String name, DateTime lastSeenAt) {
    devices[id] = SignedInDevice(
      id: id,
      name: name,
      createdAt: lastSeenAt,
      lastSeenAt: lastSeenAt,
      current: false,
    );
  }

  /// Expires every access token, as after a server restart.
  void expireAccessTokens() => _accessTokens.clear();

  @override
  Future<EmailChallenge> startEmailSignIn(String email) async {
    _check('email/start');
    return EmailChallenge(
      challengeId: 'challenge-1',
      email: email,
      expiresIn: const Duration(minutes: 5),
    );
  }

  @override
  Future<TokenPair> verifyEmailSignIn({
    required String challengeId,
    required String code,
    required String deviceName,
  }) async {
    _check('email/verify');
    if (code != this.code) throw const AuthFailure(AuthFailureKind.invalidCode);
    return _signIn(deviceName);
  }

  @override
  Future<TokenPair> signInWithGoogle({
    required String idToken,
    required String deviceName,
  }) async {
    _check('google');
    return _signIn(deviceName);
  }

  @override
  Future<TokenPair> refresh(String refreshToken) async {
    _check('refresh');
    final device = _refreshTokens[refreshToken];
    if (device == null || revoked.contains(device) || accountDeleted) {
      throw const AuthFailure(AuthFailureKind.sessionEnded);
    }
    if (!_usedRefreshTokens.add(refreshToken)) {
      revoked.add(device);
      throw const AuthFailure(AuthFailureKind.sessionEnded);
    }
    return _issue(device);
  }

  @override
  Future<void> signOut(String accessToken) async {
    _check('sign-out');
    revoked.add(_deviceFor(accessToken));
  }

  @override
  Future<List<SignedInDevice>> listDevices(String accessToken) async {
    _check('devices');
    final me = _deviceFor(accessToken);
    return [
      for (final device in devices.values)
        if (!revoked.contains(device.id))
          SignedInDevice(
            id: device.id,
            name: device.name,
            createdAt: device.createdAt,
            lastSeenAt: device.lastSeenAt,
            current: device.id == me,
          ),
    ];
  }

  @override
  Future<void> revokeDevice(String accessToken, String deviceId) async {
    _check('revoke');
    _deviceFor(accessToken);
    if (!devices.containsKey(deviceId) || !revoked.add(deviceId)) {
      throw const AuthFailure(AuthFailureKind.notFound);
    }
  }

  @override
  Future<AccountInfo> getAccount(String accessToken) async {
    _check('account');
    _deviceFor(accessToken);
    return AccountInfo(
      id: 'account-1',
      method: SignInMethod.email,
      createdAt: DateTime.utc(2026, 10, 2),
      displayName: displayName,
    );
  }

  @override
  Future<void> deleteAccount(String accessToken) async {
    _check('delete');
    _deviceFor(accessToken);
    accountDeleted = true;
  }
}
