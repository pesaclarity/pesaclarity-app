import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/features/auth/application/auth_controller.dart';
import 'package:pesaclarity/src/features/auth/data/auth_api.dart';
import 'package:pesaclarity/src/features/auth/data/session_store.dart';
import 'package:pesaclarity/src/features/auth/domain/auth_models.dart';

import '../../helpers/fake_auth.dart';

void main() {
  late FakeAuthApi api;
  late InMemorySessionStore store;
  late DateTime now;
  late ProviderContainer container;

  ProviderContainer create({
    AuthApi? authApi,
    FakeGoogleIdTokenSource? google,
  }) {
    final c = ProviderContainer(
      overrides: [
        authApiProvider.overrideWithValue(authApi ?? api),
        sessionStoreProvider.overrideWithValue(store),
        deviceNameSourceProvider.overrideWithValue(
          const FakeDeviceNameSource(),
        ),
        clockProvider.overrideWithValue(() => now),
        if (google != null)
          googleIdTokenSourceProvider.overrideWithValue(google),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  AuthController auth() => container.read(authControllerProvider.notifier);

  Future<void> signInByPhone() async {
    await container.read(authControllerProvider.future);
    final challenge = await auth().startPhoneSignIn('0700 000 000');
    await auth().verifyPhoneCode(challenge, '123456');
    // Let the follow-up display name lookup finish.
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    api = FakeAuthApi();
    store = InMemorySessionStore();
    now = DateTime.utc(2026, 10, 26, 9);
    container = create();
  });

  test('starts signed out and works without an account', () async {
    expect(await container.read(authControllerProvider.future), isNull);
    expect(container.read(displayNameProvider), isNull);
  });

  test('phone sign-in keeps only the refresh token on disk', () async {
    await signInByPhone();

    expect(api.calls, containsAllInOrder(['phone/start', 'phone/verify']));
    final stored = store.session!;
    expect(stored.refreshToken, startsWith('refresh-'));
    expect(stored.toJson().values, isNot(contains(startsWith('access-'))));
    expect(stored.contact, '+254700000000');
    expect(stored.method, SignInMethod.phone);
    expect(api.devices.values.single.name, 'Tecno Spark 20');

    final session = container.read(authControllerProvider).value!;
    expect(session.deviceId, stored.deviceId);
  });

  test('a bad number fails before reaching the server', () async {
    await container.read(authControllerProvider.future);
    expect(
      () => auth().startPhoneSignIn('12'),
      throwsA(
        isA<AuthFailure>().having(
          (f) => f.kind,
          'kind',
          AuthFailureKind.invalidPhone,
        ),
      ),
    );
    expect(api.calls, isEmpty);
  });

  test('a wrong code leaves the person signed out', () async {
    await container.read(authControllerProvider.future);
    final challenge = await auth().startPhoneSignIn('0700000000');
    await expectLater(
      auth().verifyPhoneCode(challenge, '999999'),
      throwsA(isA<AuthFailure>()),
    );
    expect(container.read(authControllerProvider).value, isNull);
    expect(store.session, isNull);
  });

  test(
    'restores the session on the next launch without a network call',
    () async {
      await signInByPhone();
      api.calls.clear();

      container = create();
      final session = await container.read(authControllerProvider.future);

      expect(session?.contact, '+254700000000');
      expect(api.calls, isEmpty);
    },
  );

  test(
    'uses the in-memory access token until it expires, then rotates',
    () async {
      await signInByPhone();
      final firstRefresh = store.session!.refreshToken;
      // The display name lookup after sign-in also uses the access token.
      await Future<void>.delayed(Duration.zero);
      api.calls.clear();

      await auth().devices();
      expect(api.calls, ['devices']);

      now = now.add(const Duration(minutes: 10));
      await auth().devices();
      expect(api.calls, ['devices', 'refresh', 'devices']);
      expect(store.session!.refreshToken, isNot(firstRefresh));
    },
  );

  test('a fresh launch refreshes once even when calls overlap', () async {
    await signInByPhone();
    container = create();
    await container.read(authControllerProvider.future);
    api.calls.clear();

    await Future.wait([auth().devices(), auth().devices()]);

    expect(api.calls.where((c) => c == 'refresh'), hasLength(1));
    expect(api.revoked, isEmpty, reason: 'no refresh token reuse');
  });

  test('retries once with a new token after an early 401', () async {
    await signInByPhone();
    api.expireAccessTokens();
    api.calls.clear();

    final devices = await auth().devices();

    expect(devices.single.current, isTrue);
    expect(api.calls, ['devices', 'refresh', 'devices']);
  });

  test('a remote sign-out of this phone signs it out here', () async {
    await signInByPhone();
    api.revoked.add(store.session!.deviceId);
    api.expireAccessTokens();

    await expectLater(
      auth().devices(),
      throwsA(
        isA<AuthFailure>().having(
          (f) => f.kind,
          'kind',
          AuthFailureKind.sessionEnded,
        ),
      ),
    );
    expect(store.session, isNull);
    expect(container.read(authControllerProvider).value, isNull);
  });

  test('signs another phone out', () async {
    await signInByPhone();
    api.addOtherDevice('old', 'Infinix Hot 30', DateTime.utc(2026, 9, 3));

    await auth().signOutDevice('old');

    final devices = await auth().devices();
    expect(devices.map((d) => d.name), ['Tecno Spark 20']);
  });

  test('sign out tells the server and forgets the tokens', () async {
    await signInByPhone();
    final deviceId = store.session!.deviceId;

    expect(await auth().signOut(), isTrue);

    expect(api.revoked, contains(deviceId));
    expect(store.session, isNull);
    expect(container.read(authControllerProvider).value, isNull);
  });

  test('sign out offline still forgets the tokens here', () async {
    await signInByPhone();
    api.offline = true;

    expect(await auth().signOut(), isFalse);
    expect(store.session, isNull);
  });

  test('delete account erases on the server, then signs out', () async {
    await signInByPhone();

    await auth().deleteAccount();

    expect(api.accountDeleted, isTrue);
    expect(store.session, isNull);
  });

  test('a failed delete keeps the person signed in', () async {
    await signInByPhone();
    api.offline = true;

    await expectLater(auth().deleteAccount(), throwsA(isA<AuthFailure>()));
    expect(store.session, isNotNull);
  });

  test('keeps the display name the server provides', () async {
    api.displayName = 'John';
    await signInByPhone();

    expect(container.read(displayNameProvider), 'John');
    expect(store.session!.displayName, 'John');
  });

  test('picks up a display name from a token refresh', () async {
    await signInByPhone();
    expect(container.read(displayNameProvider), isNull);

    api.displayName = 'John';
    container = create();
    await container.read(authControllerProvider.future);
    await auth().devices(); // a fresh launch refreshes first
    expect(container.read(displayNameProvider), 'John');
    expect(store.session!.displayName, 'John');
  });

  test('looks the name up from the account when tokens lack it', () async {
    api = _NamedAccountApi();
    container = create();
    await signInByPhone();

    expect(api.calls, contains('account'));
    expect(container.read(displayNameProvider), 'John');
  });

  test('Google sign-in, and cancelling it', () async {
    final google = FakeGoogleIdTokenSource(idToken: null);
    container = create(google: google);
    await container.read(authControllerProvider.future);

    expect(await auth().signInWithGoogle(), isFalse);
    expect(api.calls, isEmpty);

    google.idToken = 'id-token';
    expect(await auth().signInWithGoogle(), isTrue);
    expect(store.session!.method, SignInMethod.google);
  });

  test('Google is unavailable by default', () async {
    await container.read(authControllerProvider.future);
    expect(
      () => auth().signInWithGoogle(),
      throwsA(
        isA<AuthFailure>().having(
          (f) => f.kind,
          'kind',
          AuthFailureKind.unavailable,
        ),
      ),
    );
  });

  test('without a server, sign-in explains that accounts come later', () async {
    container = create(authApi: const UnconfiguredAuthApi());
    await container.read(authControllerProvider.future);
    await expectLater(
      auth().startPhoneSignIn('0700000000'),
      throwsA(
        isA<AuthFailure>().having(
          (f) => f.kind,
          'kind',
          AuthFailureKind.notConfigured,
        ),
      ),
    );
  });

  test('unreadable storage starts signed out', () async {
    container = ProviderContainer(
      overrides: [
        authApiProvider.overrideWithValue(api),
        sessionStoreProvider.overrideWithValue(_BrokenStore()),
      ],
    );
    addTearDown(container.dispose);
    expect(await container.read(authControllerProvider.future), isNull);
  });
}

/// A server whose tokens carry no name but whose account does.
class _NamedAccountApi extends FakeAuthApi {
  @override
  Future<AccountInfo> getAccount(String accessToken) async {
    final account = await super.getAccount(accessToken);
    return AccountInfo(
      id: account.id,
      method: account.method,
      createdAt: account.createdAt,
      displayName: 'John',
    );
  }
}

class _BrokenStore implements SessionStore {
  @override
  Future<StoredSession?> read() => throw Exception('keystore unavailable');

  @override
  Future<void> write(StoredSession session) async {}

  @override
  Future<void> clear() async {}
}
