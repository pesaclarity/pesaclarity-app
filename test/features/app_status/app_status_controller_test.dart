import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/features/app_status/application/app_status_providers.dart';
import 'package:pesaclarity/src/features/app_status/application/update_links.dart';
import 'package:pesaclarity/src/features/app_status/domain/app_status.dart';

import 'app_status_fakes.dart';

void main() {
  late String publicKey;
  late FakeAppStatusSource source;
  late MemorySettings settings;
  late DateTime now;

  setUpAll(() async => publicKey = await publicKeyOf(testSeed));

  setUp(() {
    source = FakeAppStatusSource();
    settings = MemorySettings();
    now = testNow;
  });

  Future<AppStatusView?> open({
    String version = '0.3.0',
    AppFlavor flavor = AppFlavor.play,
    FakeRereader? rereader,
    String? key,
  }) async {
    final container = ProviderContainer(
      overrides: appStatusOverrides(
        source: source,
        publicKey: key ?? publicKey,
        settings: settings,
        clock: () => now,
        version: version,
        flavor: flavor,
        rereader: rereader,
      ),
    );
    addTearDown(container.dispose);
    return container.read(appStatusProvider.future);
  }

  test('offline: nothing, and asks again next time', () async {
    expect(await open(), isNull);
    expect(await open(), isNull);
    expect(source.asked, hasLength(2));
  });

  test('asks with the version, build and platform only', () async {
    source.response = await signed(payload(build: 'foss'));
    await open(flavor: AppFlavor.foss);
    expect(source.asked.single, {
      'version': '0.3.0',
      'build': 'foss',
      'platform': 'android',
    });
  });

  test('asks at most once a day', () async {
    source.response = await signed(payload(notices: [updateNotice()]));
    expect((await open())!.cards, hasLength(1));
    now = testNow.add(const Duration(hours: 23));
    expect((await open())!.cards, hasLength(1));
    expect(source.asked, hasLength(1));

    now = testNow.add(const Duration(hours: 25));
    source.response = await signed(
      payload(issuedAt: now, notices: [updateNotice()]),
    );
    expect((await open())!.cards, hasLength(1));
    expect(source.asked, hasLength(2));
  });

  test('asks again after the app is updated', () async {
    source.response = await signed(payload(notices: [updateNotice()]));
    await open();
    source.response = await signed(payload(version: '0.4.0'));
    expect((await open(version: '0.4.0'))!.cards, isEmpty);
    expect(source.asked, hasLength(2));
  });

  test('without a pinned key or a version it asks nothing', () async {
    source.response = await signed(payload());
    expect(await open(key: ''), isNull);
    expect(await open(version: ''), isNull);
    expect(source.asked, isEmpty);
  });

  test('an unverifiable response shows nothing and never blocks', () async {
    source.response = await signed(
      payload(
        notices: [updateNotice(min: '0.3.2', reason: amountsWrongReason)],
      ),
      seed: otherSeed,
    );
    expect(await open(), isNull);
  });

  test('a replayed older response is refused', () async {
    source.response = await signed(payload(notices: [infoNotice()]));
    await open();
    final replay = await signed(
      payload(
        issuedAt: testNow.subtract(const Duration(hours: 2)),
        notices: [updateNotice(min: '0.3.2', reason: amountsWrongReason)],
      ),
    );
    now = testNow.add(const Duration(days: 1, hours: 1));
    source.response = replay;
    expect(await open(), isNull);
  });

  test('blocks only for amounts_wrong', () async {
    source.response = await signed(
      payload(
        notices: [updateNotice(latest: '0.3.2', min: '0.3.2')],
      ),
    );
    final card = await open();
    expect(card!.blocking, isNull);
    expect(card.cards.single.id, 'n-040');

    settings = MemorySettings();
    source.response = await signed(
      payload(
        notices: [
          updateNotice(
            latest: '0.3.2',
            min: '0.3.2',
            reason: amountsWrongReason,
          ),
        ],
      ),
    );
    expect((await open())!.blocking?.minVersion.toString(), '0.3.2');
  });

  test(
    'a closed card stays closed, and comes back for a newer version',
    () async {
      source.response = await signed(payload(notices: [updateNotice()]));
      final container = ProviderContainer(
        overrides: appStatusOverrides(
          source: source,
          publicKey: publicKey,
          settings: settings,
          clock: () => now,
        ),
      );
      addTearDown(container.dispose);
      final view = await container.read(appStatusProvider.future);
      await container
          .read(appStatusProvider.notifier)
          .dismiss(view!.cards.single);
      expect(container.read(appStatusProvider).value!.cards, isEmpty);

      expect((await open())!.cards, isEmpty);

      now = testNow.add(const Duration(days: 2));
      source.response = await signed(
        payload(
          issuedAt: now,
          notices: [
            updateNotice(
              id: 'n-041',
              latest: '0.4.1',
              title: 'Pesa Clarity 0.4.1 is ready',
            ),
          ],
        ),
      );
      expect((await open())!.cards.single.title, 'Pesa Clarity 0.4.1 is ready');
    },
  );

  test('hands reread_from to the re-reader once it takes it', () async {
    source.response = await signed(
      payload(notices: [infoNotice(rereadFrom: '2026-11-10')]),
    );
    final busy = FakeRereader(accepts: false);
    await open(rereader: busy);
    expect(busy.asked, [DateTime(2026, 11, 10)]);

    final rereader = FakeRereader();
    await open(rereader: rereader);
    await open(rereader: rereader);
    expect(rereader.asked, [DateTime(2026, 11, 10)]);
  });

  test('update links per build', () {
    expect(
      updateUrlFor(UpdateChannel.play).toString(),
      'https://play.google.com/store/apps/details?id=com.pesaclarity.app',
    );
    expect(
      updateUrlFor(UpdateChannel.foss).toString(),
      'https://f-droid.org/packages/com.pesaclarity.app/',
    );
    expect(
      updateUrlFor(UpdateChannel.website).toString(),
      'https://pesaclarity.github.io/install/#download',
    );
    expect(
      updateChannelFor(AppFlavor.foss, distribution: 'website'),
      UpdateChannel.website,
    );
    expect(
      updateChannelFor(AppFlavor.appstore, distribution: ''),
      UpdateChannel.ios,
    );
  });
}
