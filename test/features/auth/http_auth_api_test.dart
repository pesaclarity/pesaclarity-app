import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/auth/data/http_auth_api.dart';
import 'package:pesaclarity/src/features/auth/data/json_transport.dart';
import 'package:pesaclarity/src/features/auth/domain/auth_models.dart';

class _Request {
  _Request(this.method, this.url, this.body, this.bearer);

  final String method;
  final Uri url;
  final Object? body;
  final String? bearer;
}

/// Replies with a queued response and records what was sent.
class _RecordingTransport implements JsonTransport {
  final requests = <_Request>[];
  final responses = <JsonResponse>[];
  Exception? error;

  @override
  Future<JsonResponse> send(
    String method,
    Uri url, {
    Object? body,
    String? bearer,
  }) async {
    requests.add(_Request(method, url, body, bearer));
    if (error != null) throw error!;
    return responses.removeAt(0);
  }
}

const _accountId = '3f1c6a52-1d3b-4f0e-9a61-0a4d5c9b7e21';
const _deviceId = '9b2e4c71-6f0a-4d8e-b3c5-1e7a2f9d4c60';

Map<String, Object?> _tokenJson() => {
  'access_token': 'access-a',
  'refresh_token': 'refresh-a',
  'token_type': 'bearer',
  'expires_in': 600,
  'account_id': _accountId,
  'device_id': _deviceId,
};

Future<AuthFailureKind> _failureKind(Future<Object?> future) async {
  try {
    await future;
  } on AuthFailure catch (failure) {
    return failure.kind;
  }
  fail('expected an AuthFailure');
}

void main() {
  late _RecordingTransport transport;
  late HttpAuthApi api;

  setUp(() {
    transport = _RecordingTransport();
    api = HttpAuthApi(
      baseUrl: Uri.parse('https://api.example.org/base'),
      transport: transport,
    );
  });

  test('starts email sign-in with the server shape', () async {
    transport.responses.add(
      const JsonResponse(202, {
        'challenge_id': 'c0ffee00-0000-4000-8000-000000000001',
        'expires_in': 300,
      }),
    );

    final challenge = await api.startEmailSignIn('wanjiru@example.com');

    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(
      request.url.toString(),
      'https://api.example.org/base/v1/auth/email/start',
    );
    expect(request.body, {'email': 'wanjiru@example.com'});
    expect(request.bearer, isNull);
    expect(challenge.challengeId, 'c0ffee00-0000-4000-8000-000000000001');
    expect(challenge.expiresIn, const Duration(minutes: 5));
    expect(challenge.email, 'wanjiru@example.com');
  });

  test('maps email start errors', () async {
    transport.responses.addAll([
      const JsonResponse(422, {'detail': 'That email address is not valid'}),
      const JsonResponse(429, {'detail': 'Too many codes requested.'}),
    ]);
    expect(
      await _failureKind(api.startEmailSignIn('x')),
      AuthFailureKind.invalidEmail,
    );
    expect(
      await _failureKind(api.startEmailSignIn('x')),
      AuthFailureKind.rateLimited,
    );
  });

  test('verifies a code and parses the token pair', () async {
    transport.responses.add(JsonResponse(200, _tokenJson()));

    final tokens = await api.verifyEmailSignIn(
      challengeId: 'challenge',
      code: '123456',
      deviceName: 'Tecno Spark 20',
    );

    expect(transport.requests.single.url.path, '/base/v1/auth/email/verify');
    expect(transport.requests.single.body, {
      'challenge_id': 'challenge',
      'code': '123456',
      'device_name': 'Tecno Spark 20',
    });
    expect(tokens.accessToken, 'access-a');
    expect(tokens.refreshToken, 'refresh-a');
    expect(tokens.expiresIn, const Duration(minutes: 10));
    expect(tokens.accountId, _accountId);
    expect(tokens.deviceId, _deviceId);
    expect(tokens.displayName, isNull);
  });

  test('keeps a display name when the server sends one', () async {
    transport.responses.add(
      JsonResponse(200, {..._tokenJson(), 'display_name': ' John '}),
    );
    final tokens = await api.refresh('refresh-old');
    expect(tokens.displayName, 'John');
    expect(transport.requests.single.body, {'refresh_token': 'refresh-old'});
  });

  test(
    'a wrong code is invalidCode, a dead refresh token ends the session',
    () async {
      transport.responses.addAll([
        const JsonResponse(401, {
          'detail': 'That code is wrong or has expired',
        }),
        const JsonResponse(401, {'detail': 'Sign in again'}),
      ]);
      expect(
        await _failureKind(
          api.verifyEmailSignIn(
            challengeId: 'c',
            code: '000000',
            deviceName: 'x',
          ),
        ),
        AuthFailureKind.invalidCode,
      );
      expect(
        await _failureKind(api.refresh('old')),
        AuthFailureKind.sessionEnded,
      );
    },
  );

  test('Google sign-in switched off on the server is unavailable', () async {
    transport.responses.add(
      const JsonResponse(404, {'detail': 'Google sign-in is not enabled'}),
    );
    expect(
      await _failureKind(api.signInWithGoogle(idToken: 't', deviceName: 'x')),
      AuthFailureKind.unavailable,
    );
    expect(transport.requests.single.body, {
      'id_token': 't',
      'device_name': 'x',
    });
  });

  test('lists devices with the bearer token', () async {
    transport.responses.add(
      const JsonResponse(200, [
        {
          'id': _deviceId,
          'name': 'Tecno Spark 20',
          'created_at': '2026-10-02T08:00:00Z',
          'last_seen_at': '2026-10-20T17:30:00Z',
          'current': true,
        },
      ]),
    );

    final devices = await api.listDevices('access-a');

    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, '/base/v1/auth/devices');
    expect(request.bearer, 'access-a');
    expect(devices.single.name, 'Tecno Spark 20');
    expect(devices.single.current, isTrue);
    expect(devices.single.lastSeenAt, DateTime.utc(2026, 10, 20, 17, 30));
  });

  test('revokes, signs out and deletes with the right verbs', () async {
    transport.responses.addAll(const [
      JsonResponse(204),
      JsonResponse(204),
      JsonResponse(204),
    ]);

    await api.revokeDevice('access-a', _deviceId);
    await api.signOut('access-a');
    await api.deleteAccount('access-a');

    expect(
      [for (final r in transport.requests) '${r.method} ${r.url.path}'],
      [
        'DELETE /base/v1/auth/devices/$_deviceId',
        'POST /base/v1/auth/sign-out',
        'DELETE /base/v1/account',
      ],
    );
    expect(transport.requests.map((r) => r.bearer), everyElement('access-a'));
  });

  test('reads the account', () async {
    transport.responses.add(
      const JsonResponse(200, {
        'id': _accountId,
        'contact_kind': 'email',
        'created_at': '2026-10-02T08:00:00Z',
      }),
    );
    final account = await api.getAccount('access-a');
    expect(account.method, SignInMethod.email);
    expect(account.displayName, isNull);
  });

  test('an expired access token or revoked device ends the session', () async {
    transport.responses.add(
      const JsonResponse(401, {'detail': 'Not signed in'}),
    );
    expect(
      await _failureKind(api.listDevices('stale')),
      AuthFailureKind.sessionEnded,
    );
  });

  test('a missing device on revoke is notFound', () async {
    transport.responses.add(const JsonResponse(404, {'detail': 'Not found'}));
    expect(
      await _failureKind(api.revokeDevice('access-a', 'gone')),
      AuthFailureKind.notFound,
    );
  });

  test('connection problems are network failures', () async {
    transport.error = const SocketException('offline');
    expect(
      await _failureKind(api.startEmailSignIn('wanjiru@example.com')),
      AuthFailureKind.network,
    );
  });

  test('a garbled success body is a server failure', () async {
    transport.responses.add(const JsonResponse(200, {'access_token': 1}));
    expect(await _failureKind(api.refresh('r')), AuthFailureKind.server);
  });
}
