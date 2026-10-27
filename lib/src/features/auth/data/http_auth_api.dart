import 'dart:async';
import 'dart:io';

import '../domain/auth_models.dart';
import 'auth_api.dart';
import 'json_transport.dart';

/// [AuthApi] against the Pesa Clarity server at [baseUrl].
class HttpAuthApi implements AuthApi {
  HttpAuthApi({required this.baseUrl, required this._transport});

  final Uri baseUrl;
  final JsonTransport _transport;

  Uri _url(String path) => baseUrl.replace(path: '${baseUrl.path}$path');

  Future<JsonResponse> _send(
    String method,
    String path, {
    Object? body,
    String? bearer,
  }) async {
    try {
      return await _transport.send(
        method,
        _url(path),
        body: body,
        bearer: bearer,
      );
    } on SocketException {
      throw const AuthFailure(AuthFailureKind.network);
    } on TimeoutException {
      throw const AuthFailure(AuthFailureKind.network);
    } on HttpException {
      throw const AuthFailure(AuthFailureKind.network);
    } on HandshakeException {
      throw const AuthFailure(AuthFailureKind.network);
    }
  }

  /// Maps an error status to a failure. [statuses] gives endpoint-specific
  /// meanings; 401 on an authorised call means the session has ended.
  Never _fail(
    JsonResponse response, [
    Map<int, AuthFailureKind> statuses = const {},
  ]) {
    final kind =
        statuses[response.statusCode] ??
        switch (response.statusCode) {
          401 => AuthFailureKind.sessionEnded,
          404 => AuthFailureKind.notFound,
          429 => AuthFailureKind.rateLimited,
          _ => AuthFailureKind.server,
        };
    throw AuthFailure(kind, response.detail);
  }

  Map<String, Object?> _object(JsonResponse response) {
    final body = response.body;
    if (body is Map<String, Object?>) return body;
    throw const AuthFailure(AuthFailureKind.server, 'Unexpected response');
  }

  TokenPair _tokens(JsonResponse response) {
    try {
      return TokenPair.fromJson(_object(response));
    } on TypeError {
      throw const AuthFailure(AuthFailureKind.server, 'Malformed token pair');
    }
  }

  @override
  Future<EmailChallenge> startEmailSignIn(String email) async {
    final response = await _send(
      'POST',
      '/v1/auth/email/start',
      body: {'email': email},
    );
    if (response.statusCode != 202) {
      _fail(response, {
        422: AuthFailureKind.invalidEmail,
        429: AuthFailureKind.rateLimited,
      });
    }
    final json = _object(response);
    return EmailChallenge(
      challengeId: json['challenge_id']! as String,
      email: email,
      expiresIn: Duration(seconds: (json['expires_in']! as num).toInt()),
    );
  }

  @override
  Future<TokenPair> verifyEmailSignIn({
    required String challengeId,
    required String code,
    required String deviceName,
  }) async {
    final response = await _send(
      'POST',
      '/v1/auth/email/verify',
      body: {
        'challenge_id': challengeId,
        'code': code,
        'device_name': deviceName,
      },
    );
    if (response.statusCode != 200) {
      // A malformed code fails validation (422) before it is checked.
      _fail(response, {
        401: AuthFailureKind.invalidCode,
        422: AuthFailureKind.invalidCode,
      });
    }
    return _tokens(response);
  }

  @override
  Future<TokenPair> signInWithGoogle({
    required String idToken,
    required String deviceName,
  }) async {
    final response = await _send(
      'POST',
      '/v1/auth/google',
      body: {'id_token': idToken, 'device_name': deviceName},
    );
    if (response.statusCode != 200) {
      _fail(response, {
        401: AuthFailureKind.server,
        404: AuthFailureKind.unavailable,
      });
    }
    return _tokens(response);
  }

  @override
  Future<TokenPair> refresh(String refreshToken) async {
    final response = await _send(
      'POST',
      '/v1/auth/refresh',
      body: {'refresh_token': refreshToken},
    );
    if (response.statusCode != 200) {
      _fail(response, {422: AuthFailureKind.sessionEnded});
    }
    return _tokens(response);
  }

  @override
  Future<void> signOut(String accessToken) async {
    final response = await _send(
      'POST',
      '/v1/auth/sign-out',
      bearer: accessToken,
    );
    if (response.statusCode != 204) _fail(response);
  }

  @override
  Future<List<SignedInDevice>> listDevices(String accessToken) async {
    final response = await _send(
      'GET',
      '/v1/auth/devices',
      bearer: accessToken,
    );
    if (response.statusCode != 200) _fail(response);
    final body = response.body;
    if (body is! List) {
      throw const AuthFailure(AuthFailureKind.server, 'Unexpected response');
    }
    return [
      for (final item in body.cast<Map<String, Object?>>())
        SignedInDevice.fromJson(item),
    ];
  }

  @override
  Future<void> revokeDevice(String accessToken, String deviceId) async {
    final response = await _send(
      'DELETE',
      '/v1/auth/devices/${Uri.encodeComponent(deviceId)}',
      bearer: accessToken,
    );
    if (response.statusCode != 204) _fail(response);
  }

  @override
  Future<AccountInfo> getAccount(String accessToken) async {
    final response = await _send('GET', '/v1/account', bearer: accessToken);
    if (response.statusCode != 200) _fail(response);
    return AccountInfo.fromJson(_object(response));
  }

  @override
  Future<void> deleteAccount(String accessToken) async {
    final response = await _send('DELETE', '/v1/account', bearer: accessToken);
    if (response.statusCode != 204) _fail(response);
  }
}
