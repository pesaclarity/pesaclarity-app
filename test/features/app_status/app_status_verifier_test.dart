import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/app_status/data/app_status_verifier.dart';
import 'package:pesaclarity/src/features/app_status/domain/app_status.dart';
import 'package:pesaclarity/src/features/app_status/domain/app_version.dart';
import 'package:pesaclarity/src/features/app_status/domain/pinned_keys.dart';

import 'app_status_fakes.dart';

void main() {
  late AppStatusVerifier verifier;

  setUpAll(() async {
    verifier = AppStatusVerifier([await publicKeyOf(testSeed)]);
  });

  Future<AppStatus?> check(
    Object? envelope, {
    String version = '0.3.0',
    String build = 'play',
    String platform = 'android',
    DateTime? now,
    DateTime? notBefore,
  }) => verifier.verify(
    envelope,
    version: version,
    build: build,
    platform: platform,
    now: now ?? testNow,
    notBefore: notBefore,
  );

  test('reads a response signed with the pinned key', () async {
    final status = await check(
      await signed(payload(notices: [updateNotice(), infoNotice()])),
    );
    expect(status, isNotNull);
    expect(status!.issuedAt, testNow);
    expect(status.notices.map((n) => n.kind), [
      AppNoticeKind.update,
      AppNoticeKind.info,
    ]);
    expect(status.notices.first.latestVersion, AppVersion.tryParse('0.4.0'));
  });

  test('refuses a response signed with another key', () async {
    expect(await check(await signed(payload(), seed: otherSeed)), isNull);
  });

  test('refuses a changed payload', () async {
    final good = await signed(payload(notices: [updateNotice()]));
    final forged = {
      ...good,
      'payload': base64.encode(
        utf8.encode(
          jsonEncode(
            payload(
              notices: [updateNotice(min: '0.4.0', reason: amountsWrongReason)],
            ),
          ),
        ),
      ),
    };
    expect(await check(forged), isNull);
  });

  test('refuses unsigned and malformed responses', () async {
    final good = await signed(payload());
    expect(await check(null), isNull);
    expect(await check('not json'), isNull);
    expect(await check(payload()), isNull);
    expect(await check({...good, 'signature': null}), isNull);
    expect(await check({...good, 'signature': 'AAAA'}), isNull);
    expect(await check({...good, 'signature': '%%%'}), isNull);
    expect(await check({...good, 'alg': 'none'}), isNull);
  });

  test(
    'refuses a response made for another version, build or platform',
    () async {
      final good = await signed(payload());
      expect(await check(good, version: '0.3.1'), isNull);
      expect(await check(good, build: 'foss'), isNull);
      expect(await check(good, platform: 'ios'), isNull);
      expect(await check(await signed({...payload(), 'format': 2})), isNull);
    },
  );

  test('refuses an old response and one from the future', () async {
    final old = await signed(
      payload(issuedAt: testNow.subtract(const Duration(days: 3))),
    );
    expect(await check(old), isNull);
    final future = await signed(
      payload(issuedAt: testNow.add(const Duration(hours: 2))),
    );
    expect(await check(future), isNull);
    final recent = await signed(
      payload(issuedAt: testNow.subtract(const Duration(hours: 20))),
    );
    expect(await check(recent), isNotNull);
  });

  test('refuses a replayed response older than one already seen', () async {
    final earlier = await signed(
      payload(issuedAt: testNow.subtract(const Duration(hours: 5))),
    );
    expect(
      await check(
        earlier,
        notBefore: testNow.subtract(const Duration(hours: 1)),
      ),
      isNull,
    );
    // The same response again is fine: it is the cached copy.
    expect(
      await check(
        earlier,
        notBefore: testNow.subtract(const Duration(hours: 5)),
      ),
      isNotNull,
    );
  });

  test('skips malformed notices', () async {
    final status = await check(
      await signed(
        payload(
          notices: [
            {'id': 'x', 'kind': 'update', 'title': 'T', 'body': 'B'},
            {'id': 'y', 'kind': 'party', 'title': 'T', 'body': 'B'},
            infoNotice(),
          ],
        ),
      ),
    );
    expect(status!.notices.map((n) => n.id), ['n-kcb']);
  });

  test('the shipped list verifies nothing until the key is filled in', () {
    final shipped = AppStatusVerifier(appStatusPublicKeys);
    expect(shipped.hasKeys, appStatusProductionPublicKey.isNotEmpty);
    expect(
      AppStatusVerifier(const ['', 'not base64', 'AAAA']).hasKeys,
      isFalse,
    );
  });

  // A real response from the production server, so a pinned key that does not
  // match the server's seed fails here rather than on phones.
  test('the shipped key verifies the production server', () async {
    final status = await AppStatusVerifier(appStatusPublicKeys).verify(
      const {
        'alg': 'Ed25519',
        'payload': 'eyJidWlsZCI6ImZvc3MiLCJmb3JtYXQiOjEsImlzc3VlZF9hdCI6IjIwMjYtMTEtMjBUMTI6MTk6MzJaIiwibGF0ZXN0X3ZlcnNpb24iOm51bGwsIm5vdGljZXMiOltdLCJwbGF0Zm9ybSI6ImFuZHJvaWQiLCJ2ZXJzaW9uIjoiMC41LjIifQ==',
        'signature': '5DPqtZ72SwoT7UjTzVPmGT2bEjMGnQeiRMJXMoAiKfyQ8GrOIniNfOJj3Ker5EViYP3L7XxDUjxT6qb/NypyBA==',
      },
      version: '0.5.2',
      build: 'foss',
      platform: 'android',
      now: DateTime.utc(2026, 11, 20, 12, 20),
    );
    expect(status, isNotNull);
  });

  group('blocking', () {
    final current = AppVersion.tryParse('0.3.0')!;

    AppNotice notice(Map<String, Object?> json) => AppNotice.fromJson(json)!;

    test('blocks only for amounts_wrong below the minimum', () {
      expect(
        notice(updateNotice(min: '0.3.2', reason: amountsWrongReason))
            .blocks(current),
        isTrue,
      );
      expect(notice(updateNotice(min: '0.3.2')).blocks(current), isFalse);
      expect(
        notice(updateNotice(min: '0.3.2', reason: 'looks_old')).blocks(current),
        isFalse,
      );
      expect(
        notice(updateNotice(min: '0.3.0', reason: amountsWrongReason))
            .blocks(current),
        isFalse,
      );
      expect(notice(infoNotice()).blocks(current), isFalse);
    });

    test('a minimum without amounts_wrong shows as the card', () {
      final status = AppStatus(
        issuedAt: testNow,
        current: current,
        notices: [notice(updateNotice(min: '0.3.2', reason: 'other'))],
      );
      expect(status.blocking, isNull);
      expect(status.cards(const {}), hasLength(1));
    });
  });
}
