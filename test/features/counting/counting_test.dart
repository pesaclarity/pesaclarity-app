import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/domain/privacy/consent.dart';
import 'package:pesaclarity/src/domain/privacy/privacy_policy.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/app_status/application/app_status_providers.dart';
import 'package:pesaclarity/src/features/app_status/application/update_links.dart';
import 'package:pesaclarity/src/features/counting/application/counting.dart';
import 'package:pesaclarity/src/features/counting/data/count_token_store.dart';
import 'package:pesaclarity/src/features/counting/domain/count_token.dart';
import 'package:pesaclarity/src/features/privacy/application/consent_controller.dart';
import 'package:pesaclarity/src/features/privacy/data/policy_source.dart';

import '../app_status/app_status_fakes.dart';

PrivacyPolicy policy(String version) => PrivacyPolicy(
  title: 'Privacy policy',
  version: PolicyVersion.parse(version),
  updated: CalendarDate(2026, 11, 19),
  blocks: const [],
);

void main() {
  group('CountToken', () {
    test('is 128 random bits in 22 base64url characters', () {
      final made = {
        for (var i = 0; i < 200; i++) CountToken.make(testNow).value,
      };
      expect(made, hasLength(200));
      for (final value in made) {
        expect(value, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
        expect(CountToken.isWellFormed(value), isTrue);
      }
    });

    test('belongs to its UTC month', () {
      final token = CountToken.make(DateTime.utc(2026, 11, 30, 23, 59));
      expect(token.month, '2026-11');
      expect(token.isFor(DateTime.utc(2026, 11, 2)), isTrue);
      expect(token.isFor(DateTime.utc(2026, 12, 2)), isFalse);
    });

    test('reads back only a well-formed token', () {
      final token = CountToken.make(testNow);
      expect(CountToken.fromJson(token.toJson())!.value, token.value);
      expect(
        CountToken.fromJson({'month': '2026-11', 'value': 'short'}),
        isNull,
      );
      expect(
        CountToken.fromJson({'month': 'Nov', 'value': token.value}),
        isNull,
      );
      expect(CountToken.fromJson('nope'), isNull);
    });
  });

  test('on by default except in the F-Droid build', () {
    expect(countingDefaultFor(UpdateChannel.play), isTrue);
    expect(countingDefaultFor(UpdateChannel.ios), isTrue);
    expect(countingDefaultFor(UpdateChannel.website), isTrue);
    expect(countingDefaultFor(UpdateChannel.foss), isFalse);
  });

  group('the token for a check-in', () {
    late MemorySettings settings;
    late MemoryCountTokenStore store;
    late DateTime now;

    setUp(() {
      settings = MemorySettings();
      store = MemoryCountTokenStore();
      now = testNow;
    });

    Future<ProviderContainer> container({
      String bundled = '2.4',
      String? accepted = '2.4',
      AppFlavor flavor = AppFlavor.play,
    }) async {
      if (accepted != null) {
        await settings.writeJson(
          ConsentController.recordKey,
          const ConsentRecord()
              .accept(PolicyVersion.parse(accepted), at: now, values: const {})
              .toJson(),
        );
      }
      final c = ProviderContainer(
        overrides: [
          mainSettingsRepositoryProvider.overrideWithValue(settings),
          countTokenStoreProvider.overrideWithValue(store),
          privacyPolicyProvider.overrideWithValue(AsyncData(policy(bundled))),
          appFlavorProvider.overrideWithValue(flavor),
          clockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<String?> token(ProviderContainer c) =>
        c.read(countTokenIssuerProvider).tokenForCheckIn();

    test('the same token all month, a new one the next month', () async {
      final c = await container();
      final first = await token(c);
      expect(first, isNotNull);
      expect(await token(c), first);
      now = DateTime.utc(2026, 12, 1, 6);
      final next = await token(c);
      expect(next, isNot(first));
      expect(store.token!.month, '2026-12');
    });

    test('none before the person has seen policy 2.4', () async {
      expect(
        await token(await container(accepted: '2.3', bundled: '2.3')),
        isNull,
      );
      expect(await token(await container(accepted: '2.3')), isNull);
      expect(await token(await container(accepted: null)), isNull);
      expect(store.token, isNull);
    });

    test('none while a newer policy waits for review', () async {
      expect(await token(await container(bundled: '2.5')), isNull);
    });

    test('switching it off deletes the token', () async {
      final c = await container();
      expect(await token(c), isNotNull);
      await c.read(countingControllerProvider.notifier).setEnabled(false);
      expect(store.token, isNull);
      expect(await token(c), isNull);
      expect(settings.values[CountingController.settingsKey]!['value'], false);
    });

    test('off in the F-Droid build until turned on', () async {
      final c = await container(flavor: AppFlavor.foss);
      expect(await token(c), isNull);
      await c.read(countingControllerProvider.notifier).setEnabled(true);
      expect(await token(c), isNotNull);
    });

    test('the update check sends it as a header value', () async {
      final publicKey = await publicKeyOf(testSeed);
      final source = FakeAppStatusSource(await signed(payload()));
      await settings.writeJson(
        ConsentController.recordKey,
        const ConsentRecord()
            .accept(PolicyVersion.parse('2.4'), at: now, values: const {})
            .toJson(),
      );
      final c = ProviderContainer(
        overrides: [
          ...appStatusOverrides(
            source: source,
            publicKey: publicKey,
            settings: settings,
            countTokens: store,
          ),
          privacyPolicyProvider.overrideWithValue(AsyncData(policy('2.4'))),
        ],
      );
      addTearDown(c.dispose);
      await c.read(appStatusProvider.future);
      expect(source.countTokens.single, store.token!.value);
      // Never in the query.
      expect(source.asked.single.keys, {'version', 'build', 'platform'});
    });
  });

  test('a seeded source gives a predictable token, for tests only', () {
    final a = CountToken.make(testNow, random: Random(1)).value;
    final b = CountToken.make(testNow, random: Random(1)).value;
    expect(a, b);
  });
}
