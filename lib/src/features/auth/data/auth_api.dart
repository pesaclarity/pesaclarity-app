import '../domain/auth_models.dart';

/// The server's auth and account endpoints (`/v1/auth`, `/v1/account`).
///
/// Every method throws [AuthFailure] on failure.
abstract interface class AuthApi {
  /// `POST /v1/auth/phone/start`: texts a one-time code to [phone].
  Future<PhoneChallenge> startPhoneSignIn(String phone);

  /// `POST /v1/auth/phone/verify`: signs in, or signs up on first use.
  Future<TokenPair> verifyPhoneSignIn({
    required String challengeId,
    required String code,
    required String deviceName,
  });

  /// `POST /v1/auth/google`: signs in with a Google ID token (Play build).
  Future<TokenPair> signInWithGoogle({
    required String idToken,
    required String deviceName,
  });

  /// `POST /v1/auth/refresh`: rotates [refreshToken]. The old one stops
  /// working, and using it again signs the device out.
  Future<TokenPair> refresh(String refreshToken);

  /// `POST /v1/auth/sign-out`: signs this device out.
  Future<void> signOut(String accessToken);

  /// `GET /v1/auth/devices`: phones signed in to the account.
  Future<List<SignedInDevice>> listDevices(String accessToken);

  /// `DELETE /v1/auth/devices/{id}`: signs another phone out.
  Future<void> revokeDevice(String accessToken, String deviceId);

  /// `GET /v1/account`.
  Future<AccountInfo> getAccount(String accessToken);

  /// `DELETE /v1/account`: erases the account, its devices, sign-in history
  /// and every vault backup.
  Future<void> deleteAccount(String accessToken);
}

/// Stands in for the server when the build has no server URL.
class UnconfiguredAuthApi implements AuthApi {
  const UnconfiguredAuthApi();

  Never _fail() => throw const AuthFailure(AuthFailureKind.notConfigured);

  @override
  Future<PhoneChallenge> startPhoneSignIn(String phone) async => _fail();

  @override
  Future<TokenPair> verifyPhoneSignIn({
    required String challengeId,
    required String code,
    required String deviceName,
  }) async => _fail();

  @override
  Future<TokenPair> signInWithGoogle({
    required String idToken,
    required String deviceName,
  }) async => _fail();

  @override
  Future<TokenPair> refresh(String refreshToken) async => _fail();

  @override
  Future<void> signOut(String accessToken) async => _fail();

  @override
  Future<List<SignedInDevice>> listDevices(String accessToken) async => _fail();

  @override
  Future<void> revokeDevice(String accessToken, String deviceId) async =>
      _fail();

  @override
  Future<AccountInfo> getAccount(String accessToken) async => _fail();

  @override
  Future<void> deleteAccount(String accessToken) async => _fail();
}
