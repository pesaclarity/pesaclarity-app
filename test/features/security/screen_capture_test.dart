import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/security/application/app_lock_controller.dart';
import 'package:pesaclarity/src/features/security/data/key_vault.dart';
import 'package:pesaclarity/src/features/security/data/screen_capture_blocker.dart';
import 'package:pesaclarity/src/features/security/data/secure_store.dart';
import 'package:pesaclarity/src/features/security/domain/lock_settings.dart';

import '../../helpers/fake_app_lock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The channel `ScreenCaptureChannel.kt` answers on Android.
  const channel = MethodChannel('com.pesaclarity.app/screen_capture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MemorySecureStore store;
  late List<String> asked;

  /// The Android side: notes each method the app calls, then does it, or
  /// fails when [fails].
  void phone({bool fails = false}) =>
      messenger.setMockMethodCallHandler(channel, (call) async {
        asked.add(call.method);
        if (fails) throw PlatformException(code: 'boom');
        return null;
      });

  setUp(() {
    store = MemorySecureStore();
    asked = [];
    phone();
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// What is saved for the next start.
  Object? saved() => switch (store.values[KeyVault.settingsName]) {
    final String raw =>
      (jsonDecode(raw) as Map<String, Object?>)['allowScreenCapture'],
    null => null,
  };

  /// Starts the app lock as opening the app does, on a phone that lets the
  /// app block screenshots ([canBlock], as Android does), and waits until
  /// its settings are read.
  Future<ProviderContainer> start({bool canBlock = true}) async {
    final container = ProviderContainer(
      overrides: [
        ...appLockOverrides(store: store),
        canBlockScreenCaptureProvider.overrideWithValue(canBlock),
      ],
    );
    addTearDown(container.dispose);
    final loaded = Completer<void>();
    container.listen(appLockControllerProvider, (_, next) {
      if (next.status != LockStatus.loading && !loaded.isCompleted) {
        loaded.complete();
      }
    }, fireImmediately: true);
    await loaded.future;
    return container;
  }

  bool allowed(ProviderContainer container) =>
      container.read(appLockControllerProvider).settings.allowScreenCapture;

  group('the saved setting', () {
    test('is blocked unless a yes was saved', () {
      expect(const LockSettings().allowScreenCapture, isFalse);
      expect(const LockSettings().toJson()['allowScreenCapture'], isFalse);
      for (final json in <Map<String, Object?>>[
        {},
        {'allowScreenCapture': false},
        {'allowScreenCapture': null},
        {'allowScreenCapture': 'true'},
        {'allowScreenCapture': 1},
      ]) {
        expect(
          LockSettings.fromJson(json, pinSet: false).allowScreenCapture,
          isFalse,
          reason: '$json',
        );
      }
    });

    test('comes back as saved, with the other settings', () {
      const settings = LockSettings(
        hideBalancesOnOpen: true,
        allowScreenCapture: true,
      );
      final read = LockSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, Object?>,
        pinSet: false,
      );
      expect(read.allowScreenCapture, isTrue);
      expect(read.hideBalancesOnOpen, isTrue);
      expect(
        read.copyWith(lockAfter: Duration.zero).allowScreenCapture,
        isTrue,
      );
      expect(
        read.copyWith(allowScreenCapture: false).hideBalancesOnOpen,
        isTrue,
      );
    });
  });

  group('the channel', () {
    const capture = MethodChannelScreenCaptureBlocker();

    test('is the one the Android side answers on', () {
      expect(capture.channel.name, channel.name);
    });

    test('asks the phone to allow, then to block', () async {
      expect(await capture.setAllowed(true), isTrue);
      expect(await capture.setAllowed(false), isTrue);
      expect(asked, ['allow', 'block']);
    });

    test('a failing or missing channel answers no', () async {
      phone(fails: true);
      expect(await capture.setAllowed(true), isFalse);
      expect(await capture.setAllowed(false), isFalse);

      messenger.setMockMethodCallHandler(channel, null);
      expect(await capture.setAllowed(true), isFalse);
      expect(await capture.setAllowed(false), isFalse);
    });
  });

  group('the setting', () {
    test(
      'is blocked by default, and the phone is left as it started',
      () async {
        final container = await start();

        expect(allowed(container), isFalse);
        expect(saved(), isNull);
        expect(asked, isEmpty);
      },
    );

    test('turning it on saves it and asks the phone to allow', () async {
      final container = await start();
      final controller = container.read(appLockControllerProvider.notifier);

      expect(await controller.setAllowScreenCapture(true), isTrue);

      expect(allowed(container), isTrue);
      expect(saved(), isTrue);
      expect(asked, ['allow']);
    });

    test('turning it off saves it and asks the phone to block', () async {
      final container = await start();
      final controller = container.read(appLockControllerProvider.notifier);
      await controller.setAllowScreenCapture(true);

      expect(await controller.setAllowScreenCapture(false), isTrue);

      expect(allowed(container), isFalse);
      expect(saved(), isFalse);
      expect(asked, ['allow', 'block']);
    });

    test('a start applies what was saved', () async {
      await testKeyVault(store)
          .writeSettings(const LockSettings(allowScreenCapture: true));
      final opened = await start();
      expect(allowed(opened), isTrue);
      expect(asked, ['allow']);

      // Saved as blocked: the window starts blocked, so nothing is asked.
      await opened
          .read(appLockControllerProvider.notifier)
          .setAllowScreenCapture(false);
      asked.clear();
      final again = await start();
      expect(allowed(again), isFalse);
      expect(asked, isEmpty);
    });

    test('a start with app lock on applies it before the PIN', () async {
      final vault = testKeyVault(store);
      await vault.setPin('246810', await vault.readOrCreateOpenKey());
      await vault.writeSettings(
        const LockSettings(pinSet: true, allowScreenCapture: true),
      );

      final container = await start();

      expect(
        container.read(appLockControllerProvider).status,
        LockStatus.locked,
      );
      expect(allowed(container), isTrue);
      expect(asked, ['allow']);
    });

    test('changing another setting keeps it', () async {
      final container = await start();
      final controller = container.read(appLockControllerProvider.notifier);
      await controller.setAllowScreenCapture(true);

      await controller.setHideBalancesOnOpen(true);
      await controller.setLockAfter(const Duration(minutes: 1));

      expect(allowed(container), isTrue);
      expect(saved(), isTrue);
      expect(allowed(await start()), isTrue);
    });

    test('a failing channel leaves it blocked when switched on', () async {
      phone(fails: true);
      final container = await start();
      final controller = container.read(appLockControllerProvider.notifier);

      expect(await controller.setAllowScreenCapture(true), isFalse);

      expect(allowed(container), isFalse);
      expect(saved(), isFalse);
      expect(asked, ['allow']);
    });

    test('a failing channel leaves it blocked at the start', () async {
      await testKeyVault(store)
          .writeSettings(const LockSettings(allowScreenCapture: true));
      phone(fails: true);

      final container = await start();

      // The app opens as usual, and the switch shows what is in force.
      expect(
        container.read(appLockControllerProvider).status,
        LockStatus.unlocked,
      );
      expect(allowed(container), isFalse);
      expect(asked, ['allow']);

      // What the person chose is kept for a start where the phone takes it.
      expect(saved(), isTrue);
      phone();
      expect(allowed(await start()), isTrue);
    });

    test('a missing channel leaves it blocked too', () async {
      messenger.setMockMethodCallHandler(channel, null);
      final container = await start();
      final controller = container.read(appLockControllerProvider.notifier);

      expect(await controller.setAllowScreenCapture(true), isFalse);

      expect(allowed(container), isFalse);
      expect(saved(), isFalse);
    });

    test(
      'a block the phone does not take still holds from the next start',
      () async {
        final container = await start();
        final controller = container.read(appLockControllerProvider.notifier);
        await controller.setAllowScreenCapture(true);
        phone(fails: true);

        expect(await controller.setAllowScreenCapture(false), isFalse);

        expect(allowed(container), isFalse);
        expect(saved(), isFalse);
        asked.clear();
        phone();
        expect(allowed(await start()), isFalse);
        expect(asked, isEmpty);
      },
    );

    test('where the app cannot block them, nothing is switched', () async {
      await testKeyVault(store)
          .writeSettings(const LockSettings(allowScreenCapture: true));

      final container = await start(canBlock: false);
      final controller = container.read(appLockControllerProvider.notifier);

      expect(await controller.setAllowScreenCapture(true), isFalse);
      expect(await controller.setAllowScreenCapture(false), isFalse);
      expect(asked, isEmpty);
    });
  });

  group('the platform check', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    for (final (platform, canBlock) in [
      (TargetPlatform.android, true),
      (TargetPlatform.iOS, false),
    ]) {
      test('${platform.name}: the app can block screenshots: $canBlock', () {
        debugDefaultTargetPlatformOverride = platform;
        final container = ProviderContainer();
        addTearDown(container.dispose);
        expect(container.read(canBlockScreenCaptureProvider), canBlock);
      });
    }
  });
}
