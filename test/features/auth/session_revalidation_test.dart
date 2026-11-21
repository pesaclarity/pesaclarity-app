import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/features/auth/application/auth_controller.dart';
import 'package:pesaclarity/src/features/auth/data/auth_api.dart';
import 'package:pesaclarity/src/features/auth/data/http_auth_api.dart';
import 'package:pesaclarity/src/features/auth/data/json_transport.dart';
import 'package:pesaclarity/src/features/auth/data/session_store.dart';
import 'package:pesaclarity/src/features/auth/presentation/keep_session_fresh.dart';

import '../../helpers/fake_auth.dart';

/// A server behind a network that fails with [error] while [offline].
class _FlakyTransport implements JsonTransport {
  _FlakyTransport(this.error);

  Object error;
  bool offline = true;
  final calls = <String>[];

  @override
  Future<JsonResponse> send(
    String method,
    Uri url, {
    Object? body,
    String? bearer,
    Map<String, String> headers = const {},
  }) async {
    calls.add('$method ${url.path}');
    if (offline) throw error;
    return const JsonResponse(200, {
      'access_token': 'access-new',
      'refresh_token': 'refresh-new',
      'expires_in': 600,
      'account_id': 'account-test-1',
      'device_id': 'device-test-1',
    });
  }
}

void main() {
  late FakeAuthApi api;
  late InMemorySessionStore store;
  late DateTime now;

  ProviderContainer create({AuthApi? authApi}) {
    final c = ProviderContainer(
      overrides: [
        authApiProvider.overrideWithValue(authApi ?? api),
        sessionStoreProvider.overrideWithValue(store),
        deviceNameSourceProvider.overrideWithValue(
          const FakeDeviceNameSource(),
        ),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Signs in, then opens the app again the next day, as after a night
  /// away: the refresh token on disk, no access token in memory.
  Future<ProviderContainer> signedInYesterday() async {
    final first = create();
    await first.read(authControllerProvider.future);
    final auth = first.read(authControllerProvider.notifier);
    final challenge = await auth.startEmailSignIn('wanjiru@example.com');
    await auth.verifyEmailCode(challenge, '123456');
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(days: 1));
    final next = create();
    await next.read(authControllerProvider.future);
    api.calls.clear();
    return next;
  }

  setUp(() {
    api = FakeAuthApi();
    store = InMemorySessionStore();
    now = DateTime.utc(2026, 11, 20, 9);
  });

  test('offline, start and resume change nothing', () async {
    final container = await signedInYesterday();
    final stored = store.session;
    final writes = store.writes;
    api.offline = true;

    final auth = container.read(authControllerProvider.notifier);
    await auth.revalidate(); // start
    now = now.add(const Duration(minutes: 5));
    await auth.revalidate(); // resume

    expect(store.session, same(stored));
    expect(store.writes, writes);
    expect(container.read(authControllerProvider).value, isNotNull);
  });

  test('back online, the session is renewed once', () async {
    final container = await signedInYesterday();
    final auth = container.read(authControllerProvider.notifier);
    final before = store.session!.refreshToken;
    api.offline = true;
    await auth.revalidate();

    api.offline = false;
    api.calls.clear();
    await auth.revalidate();
    await auth.revalidate();
    now = now.add(const Duration(hours: 1));
    await auth.revalidate();

    expect(api.calls, ['refresh']);
    expect(store.session!.refreshToken, isNot(before));
    expect(container.read(authControllerProvider).value, isNotNull);

    // A few hours on, it checks again.
    now = now.add(AuthController.revalidateEvery);
    await auth.revalidate();
    expect(api.calls, ['refresh', 'refresh']);
    expect(api.revoked, isEmpty, reason: 'no refresh token reuse');
  });

  test('a session the server ended signs this phone out', () async {
    final container = await signedInYesterday();
    api.revoked.add(store.session!.deviceId);

    await container.read(authControllerProvider.notifier).revalidate();

    expect(store.session, isNull);
    expect(container.read(authControllerProvider).value, isNull);
  });

  test('a passing server error keeps the session', () async {
    final container = await signedInYesterday();
    // A server that is up but failing answers 500.
    final failing = HttpAuthApi(
      baseUrl: Uri.parse('https://api.pesaclarity.test'),
      transport: const _Answering(JsonResponse(500, {'detail': 'down'})),
    );
    container.dispose();
    final again = create(authApi: failing);
    await again.read(authControllerProvider.future);
    await again.read(authControllerProvider.notifier).revalidate();

    expect(store.session, isNotNull);
    expect(again.read(authControllerProvider).value, isNotNull);
  });

  testWidgets('the app renews the session on start and on return, '
      'at most every few hours', (tester) async {
    // The app's work runs on real futures, as on a phone.
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    final container = await tester.runAsync(signedInYesterday);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container!,
        child: const KeepSessionFresh(child: SizedBox.shrink()),
      ),
    );
    await settle();
    expect(api.calls, ['refresh']);

    void resume() {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    resume();
    await settle();
    expect(api.calls, ['refresh'], reason: 'renewed a moment ago');

    now = now.add(AuthController.revalidateEvery);
    resume();
    await settle();
    expect(api.calls, ['refresh', 'refresh']);
  });

  // Every way a phone can fail to reach the server.
  final offlineErrors = <String, Object>{
    'no address': const SocketException('Failed host lookup'),
    'refused': const SocketException('Connection refused'),
    'timeout': TimeoutException('timed out'),
    'dropped': const HttpException('Connection closed'),
    'captive portal': const HandshakeException('captive portal'),
    'TLS': const TlsException('tls'),
    'no route': const OSError('Network is unreachable', 101),
  };
  for (final MapEntry(key: name, value: error) in offlineErrors.entries) {
    test('a flaky network ($name) never signs out', () async {
      store = InMemorySessionStore(
        const StoredSession(
          refreshToken: 'refresh-made-up-0001',
          accountId: 'account-test-1',
          deviceId: 'device-test-1',
        ),
      );
      final transport = _FlakyTransport(error);
      final container = create(
        authApi: HttpAuthApi(
          baseUrl: Uri.parse('https://api.pesaclarity.test'),
          transport: transport,
        ),
      );
      final auth = container.read(authControllerProvider.notifier);
      expect(await container.read(authControllerProvider.future), isNotNull);
      expect(transport.calls, isEmpty, reason: 'opening needs no network');

      await auth.revalidate();
      await expectLater(auth.accessToken(), throwsA(anything));
      expect(store.session, isNotNull);
      expect(container.read(authControllerProvider).value, isNotNull);

      transport.offline = false;
      await auth.revalidate();
      expect(store.session!.refreshToken, 'refresh-new');
      expect(await auth.accessToken(), 'access-new');
    });
  }
}

/// Always answers [response].
class _Answering implements JsonTransport {
  const _Answering(this.response);

  final JsonResponse response;

  @override
  Future<JsonResponse> send(
    String method,
    Uri url, {
    Object? body,
    String? bearer,
    Map<String, String> headers = const {},
  }) async => response;
}
