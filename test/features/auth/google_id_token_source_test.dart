import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/features/auth/application/auth_controller.dart';
import 'package:pesaclarity/src/features/auth/data/google_id_token_source.dart';
import 'package:pesaclarity/src/features/auth/domain/auth_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/google_sign_in');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, handler);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  const source = PlatformGoogleIdTokenSource(
    serverClientId: 'web-client.apps.example',
    channel: channel,
  );

  test('passes the server client id and returns the token', () async {
    MethodCall? seen;
    answer((call) async {
      seen = call;
      return 'id-token';
    });
    expect(await source.requestIdToken(), 'id-token');
    expect(seen?.method, 'requestIdToken');
    expect(seen?.arguments, {'serverClientId': 'web-client.apps.example'});
  });

  test('a cancelled picker returns null', () async {
    answer((_) async => null);
    expect(await source.requestIdToken(), isNull);
  });

  test('maps platform errors to account failures', () async {
    for (final (code, kind) in [
      ('no_account', AuthFailureKind.noGoogleAccount),
      ('unavailable', AuthFailureKind.unavailable),
      ('failed', AuthFailureKind.server),
    ]) {
      answer((_) async => throw PlatformException(code: code));
      await expectLater(
        source.requestIdToken(),
        throwsA(isA<AuthFailure>().having((f) => f.kind, 'kind', kind)),
      );
    }
  });

  test('needs a server client id', () {
    expect(source.isAvailable, isTrue);
    expect(
      const PlatformGoogleIdTokenSource(serverClientId: '').isAvailable,
      isFalse,
    );
  });

  test('foss builds never use the platform source', () {
    for (final (flavor, expected) in [
      (AppFlavor.foss, UnavailableGoogleIdTokenSource),
      (AppFlavor.play, PlatformGoogleIdTokenSource),
    ]) {
      final container = ProviderContainer(
        overrides: [appFlavorProvider.overrideWithValue(flavor)],
      );
      addTearDown(container.dispose);
      expect(container.read(googleIdTokenSourceProvider).runtimeType, expected);
    }
  });
}
