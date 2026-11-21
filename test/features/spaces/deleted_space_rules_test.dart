// A deleted space takes its "Business or personal" rules with it, and
// nothing moves money into, or makes a file for, a space that is not on
// the list. The app's own providers, on real encrypted files where files
// matter. Made-up data only.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/connection.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/database/space_databases.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/data/repositories/space_move_repository.dart';
import 'package:pesaclarity/src/domain/spaces/kept_data.dart';
import 'package:pesaclarity/src/domain/spaces/line_routing.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/backup/application/backup_providers.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/routing_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/space_manager.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../helpers/fake_sms_source.dart';
import '../../helpers/sms_samples.dart';
import '../../helpers/spaces_harness.dart';
import '../../helpers/test_app.dart';

final _now = DateTime.utc(2026, 11, 20, 9);
final _mpesa = [institutionCatalogue.singleWhere((i) => i.id == 'mpesa')];

/// Grace, a customer, sends money to the M-Pesa line: receipt
/// `TJA000002[n]`, on 1[n] November.
SmsMessage _fromGrace(int n) => mpesaSms(
  'TJA000002$n Confirmed.You have received Ksh${650 + n}.00 from GRACE '
  'WAMBUI 0700***002 on 1$n/11/26 at 10:02 AM  New M-PESA balance is '
  'Ksh38,469.00.',
  DateTime.utc(2026, 11, 10 + n, 7, 2, 5),
);

/// The same from John, another customer.
SmsMessage _fromJohn(int n) => mpesaSms(
  'TJA000003$n Confirmed.You have received Ksh${900 + n}.00 from JOHN '
  'KAMAU 0700***003 on 1$n/11/26 at 11:02 AM  New M-PESA balance is '
  'Ksh39,369.00.',
  DateTime.utc(2026, 11, 10 + n, 8, 2, 5),
);

const _grace = 'phone:0700***002';
const _john = 'phone:0700***003';

extension on ProviderContainer {
  AppDatabase get personal => read(personalDatabaseProvider);

  Future<List<String?>> inPersonal() async => [
    for (final t in await personal.select(personal.transactions).get())
      t.receiptNo,
  ];

  Future<void> open(String spaceId) =>
      read(activeSpaceIdProvider.notifier).switchTo(spaceId);

  /// Adds a business that shares M-Pesa with Personal ("Both" in Business
  /// or personal), and leaves it open.
  Future<String> addShop(String name) async {
    final id = await read(spacesProvider.notifier)
        .add(name, SpaceKind.business);
    await read(routingRulesProvider.notifier).setLine(
      'mpesa',
      LineChoice.both,
      businessId: id,
      business: read(institutionsRepositoryProvider),
      personal: DriftInstitutionsRepository(personal),
    );
    return id;
  }

  /// Personal reads [message] as it arrives, then sorts what it already
  /// knows about, as the live capture does.
  Future<void> personalReads(SmsMessage message) async {
    await open(personalSpaceId);
    final summary = await read(smsIngestorProvider).ingest([message], _mpesa);
    expect(summary.added, 1);
    await read(sharedLineRouterProvider).applyRules();
  }

  /// In [shopId], answers "Business sale" with "Always do this" for every
  /// payment it asks about.
  Future<void> alwaysBusiness(String shopId) async {
    await open(shopId);
    invalidate(sharedLineQuestionsProvider);
    for (final question in await read(sharedLineQuestionsProvider.future)) {
      await read(
        sharedLineRouterProvider,
      ).answer(question, businessId: shopId, forBusiness: true, always: true);
    }
  }

  Future<Space> space(String id) async =>
      (await read(spacesProvider.future)).singleWhere((s) => s.id == id);

  Future<List<String?>> inSpace(String spaceId) async {
    final (db, close) = await read(spaceDatabasesProvider).open(spaceId);
    try {
      return [
        for (final t in await db.select(db.transactions).get()) t.receiptNo,
      ]..sort((a, b) => a!.compareTo(b!));
    } finally {
      if (close) await db.close();
    }
  }
}

void main() {
  test('after Delete space, money from an "Always business" customer '
      'stays in Personal, and no file is made for the space', () async {
    final phone = PhoneInbox();
    addTearDown(phone.close);
    late Map<String, Object?> facts;

    await guarded(() async {
      final (c, _) = await spacesOnFiles(sms: phone, clock: () => _now);
      final shopId = await c.addShop('Mama Njeri Shop');

      // Personal is open (the app shell listens to the capture) and reads
      // Grace's first payment as it arrives.
      await c.open(personalSpaceId);
      final shell = c.listen(liveSmsCaptureProvider, (_, _) {});
      addTearDown(shell.close);
      await captureIsSteady(phone);
      phone.receive(_fromGrace(1));
      await until(() async => (await c.inPersonal()).length == 1);
      await settle();

      // The shop answers "Business sale", with "Always do this for Grace".
      await c.alwaysBusiness(shopId);
      expect(await c.inPersonal(), isEmpty);
      expect((await c.read(routingRulesProvider.future)).people, {
        _grace: shopId,
      });

      // The owner closes the business: Profile > Spaces > Delete space.
      await c
          .read(spaceManagerProvider)
          .delete(await c.space(shopId), keep: false);
      final shopFile = await databaseFile(shopId);
      expect(c.read(activeSpaceIdProvider), personalSpaceId);
      expect(shopFile.existsSync(), isFalse);
      final rulesLeft = await c.read(routingRulesProvider.future);

      // Grace sends money again. Personal, the only space left, is open
      // and reads it as it arrives.
      await captureIsSteady(phone);
      phone.receive(_fromGrace(2));
      await until(() async => (await c.inPersonal()).isNotEmpty);
      await settle(1500);

      facts = {
        'spaces on the phone': [
          for (final s in await c.read(spacesProvider.future)) s.name,
        ],
        'rules left': rulesLeft.toJson(),
        'in Personal': await c.inPersonal(),
        'the deleted space has a database file again': shopFile.existsSync(),
      };
    });

    expect(facts, {
      'spaces on the phone': ['Personal'],
      'rules left': {
        'sharedLines': <String, String>{},
        'people': <String, String>{},
      },
      'in Personal': ['TJA0000022'],
      'the deleted space has a database file again': false,
    });
  });

  group('deleted and kept for 30 days', () {
    test('its rules wait with the copy; restored, they send money to it '
        'again', () async {
      final (c, _) = await spacesOnFiles(clock: () => _now);
      final shopId = await c.addShop('Mama Njeri Shop');
      await c.personalReads(_fromGrace(1));
      await c.alwaysBusiness(shopId);
      final manager = c.read(spaceManagerProvider);

      await manager.delete(await c.space(shopId), keep: true);

      // Out of use, and kept with the copy.
      expect((await c.read(routingRulesProvider.future)).isEmpty, isTrue);
      final kept = (await c.read(keptDataProvider.future)).single;
      expect(kept.rules!.toJson(), {
        'sharedLines': {'mpesa': shopId},
        'people': {_grace: shopId},
      });
      // While it is deleted, Grace's money stays in Personal.
      await c.personalReads(_fromGrace(2));
      expect(await c.inPersonal(), ['TJA0000022']);
      expect((await databaseFile(shopId)).existsSync(), isFalse);

      await manager.restore(kept);

      expect(c.read(activeSpaceIdProvider), shopId);
      expect((await c.read(routingRulesProvider.future)).toJson(), {
        'sharedLines': {'mpesa': shopId},
        'people': {_grace: shopId},
      });
      // Grace is a customer of the shop again: what she sent meanwhile,
      // and what she sends next, go to it.
      await c.personalReads(_fromGrace(3));
      expect(await c.inPersonal(), isEmpty);
      expect(await c.inSpace(shopId), [
        'TJA0000021',
        'TJA0000022',
        'TJA0000023',
      ]);
      expect(await c.read(keptDataProvider.future), isEmpty);
    });

    test('once the copy goes for good, so do its rules', () async {
      final (c, _) = await spacesOnFiles(clock: () => _now);
      final shopId = await c.addShop('Mama Njeri Shop');
      await c.personalReads(_fromGrace(1));
      await c.alwaysBusiness(shopId);
      final manager = c.read(spaceManagerProvider);
      await manager.delete(await c.space(shopId), keep: true);

      await manager.deleteNow((await c.read(keptDataProvider.future)).single);

      expect(await c.read(keptDataProvider.future), isEmpty);
      expect((await c.read(routingRulesProvider.future)).isEmpty, isTrue);
      final raw = await DriftAppSettingsRepository(c.personal)
          .readJson(KeptDataController.settingsKey);
      expect(raw, {'kept': <Object?>[]});
      // A business added later starts with no rules of its own.
      final next = await c
          .read(spacesProvider.notifier)
          .add('Second shop', SpaceKind.business);
      final rules = await c.read(routingRulesProvider.future);
      expect(rules.sharedWith(next), isEmpty);
      expect(rules.learntFor(next), (business: 0, personal: 0));
    });

    test('what was chosen since stays when it is restored', () async {
      final (c, _) = await spacesOnFiles(clock: () => _now);
      final first = await c.addShop('Mama Njeri Shop');
      await c.personalReads(_fromGrace(1));
      await c.personalReads(_fromJohn(1));
      await c.alwaysBusiness(first);
      final manager = c.read(spaceManagerProvider);
      await manager.delete(await c.space(first), keep: true);

      // Meanwhile another business shares the line, and Grace is its
      // customer now.
      final second = await c.addShop('Second shop');
      await c.personalReads(_fromGrace(2));
      await c.alwaysBusiness(second);

      await manager.restore((await c.read(keptDataProvider.future)).single);

      expect((await c.read(routingRulesProvider.future)).toJson(), {
        'sharedLines': {'mpesa': second},
        'people': {_john: first, _grace: second},
      });
    });
  });

  test('"Always personal" is about Personal, so it outlives the business '
      'it was learnt in', () async {
    final (c, _) = await spacesOnFiles(clock: () => _now);
    final shopId = await c.addShop('Mama Njeri Shop');
    await c.personalReads(_fromGrace(1));
    await c.open(shopId);
    final question = (await c.read(sharedLineQuestionsProvider.future)).single;
    await c
        .read(sharedLineRouterProvider)
        .answer(question, businessId: shopId, forBusiness: false, always: true);

    await c
        .read(spaceManagerProvider)
        .delete(await c.space(shopId), keep: false);

    expect((await c.read(routingRulesProvider.future)).toJson(), {
      'sharedLines': <String, String>{},
      'people': {_grace: personalSpaceId},
    });
    expect(await c.inPersonal(), ['TJA0000021']);
  });

  group('rules left by a space deleted before its rules went with it', () {
    const stale = RoutingRules(
      sharedLines: {'mpesa': 'gone1', 'kcb': 'shop1'},
      people: {_grace: 'gone1', _john: 'shop1', 'name:mum': personalSpaceId},
    );
    late AppDatabase personal;
    late ProviderContainer c;
    late DriftAppSettingsRepository settings;

    setUp(() async {
      personal = openTestDatabase();
      settings = DriftAppSettingsRepository(personal);
      await settings.writeJson(
        SpacesController.settingsKey,
        spacesToJson(const [
          Space.personal,
          Space(id: 'shop1', name: 'Second shop', kind: SpaceKind.business),
        ]),
      );
      await settings.writeJson(
        RoutingRulesController.settingsKey,
        stale.toJson(),
      );
      c = twoSpaces(
        personal: personal,
        other: openTestDatabase(),
        clock: () => _now,
      );
    });

    KeptData kept(String token, KeptKind kind) => KeptData(
      token: token,
      kind: kind,
      space: const Space(
        id: 'gone1',
        name: 'Mama Njeri Shop',
        kind: SpaceKind.business,
      ),
      removedAt: _now.subtract(const Duration(days: 3)),
      keyHex: 'k',
    );

    test('are dropped the next time rules are read', () async {
      final rules = await c.read(routingRulesProvider.future);

      const left = {
        'sharedLines': {'kcb': 'shop1'},
        'people': {_john: 'shop1', 'name:mum': personalSpaceId},
      };
      expect(rules.toJson(), left);
      expect(await settings.readJson(RoutingRulesController.settingsKey), left);
    });

    test('join its kept copy when there is one, so a restore brings them '
        'back', () async {
      await settings.writeJson(
        KeptDataController.settingsKey,
        keptToJson([
          kept('space1', KeptKind.space),
          kept('cleared1', KeptKind.cleared),
        ]),
      );

      final rules = await c.read(routingRulesProvider.future);

      expect(rules.sharedLines, {'kcb': 'shop1'});
      final saved = keptFromJson(
        await settings.readJson(KeptDataController.settingsKey),
      );
      final copy = saved.singleWhere((k) => k.token == 'space1');
      expect(copy.rules!.toJson(), {
        'sharedLines': {'mpesa': 'gone1'},
        'people': {_grace: 'gone1'},
      });
      // Records cleared from a space that stayed carry no rules.
      expect(saved.singleWhere((k) => k.token == 'cleared1').rules, isNull);
    });

    test('rules for spaces on the list are left as they are', () async {
      const fine = RoutingRules(
        sharedLines: {'kcb': 'shop1'},
        people: {_john: 'shop1'},
      );
      await settings.writeJson(
        RoutingRulesController.settingsKey,
        fine.toJson(),
      );
      expect(
        (await c.read(routingRulesProvider.future)).toJson(),
        fine.toJson(),
      );
    });
  });

  group('a space that is not on the list', () {
    Future<bool> hasFile(String spaceId) async =>
        (await databaseFile(spaceId)).existsSync();

    test('is never opened: no file is made for it', () async {
      final (c, _) = await spacesOnFiles(clock: () => _now);
      final shopId = await c.addShop('Mama Njeri Shop');

      await expectLater(
        c.read(spaceDatabasesProvider).open('gone1'),
        throwsA(
          isA<SpaceNotOnPhone>().having((e) => e.spaceId, 'spaceId', 'gone1'),
        ),
      );
      expect(await hasFile('gone1'), isFalse);

      // A space on the list opens, the open one without a second
      // connection.
      final (open, closeOpen) = await c
          .read(spaceDatabasesProvider)
          .open(shopId);
      expect((open, closeOpen), (c.read(appDatabaseProvider), false));
      await c.open(personalSpaceId);
      final (other, close) = await c.read(spaceDatabasesProvider).open(shopId);
      expect(close, isTrue);
      expect(await other.spaceKind(), SpaceKind.business);
      await other.close();
    });

    test('takes no payment moved by hand: it stays where it is', () async {
      final (c, _) = await spacesOnFiles(clock: () => _now);
      await c.personalReads(_fromGrace(1));
      final row = await c.personal.select(c.personal.transactions).getSingle();

      await expectLater(
        c.read(spaceMoveRepositoryProvider).move(row.id, 'gone1'),
        throwsA(isA<SpaceNotOnPhone>()),
      );

      expect(await c.inPersonal(), ['TJA0000021']);
      expect(
        await c.personal.select(c.personal.movedTransactions).get(),
        isEmpty,
      );
      expect(await hasFile('gone1'), isFalse);
    });

    test('takes no payment from a rule that slipped through', () async {
      final (c, _) = await spacesOnFiles(clock: () => _now);
      final shopId = await c.addShop('Mama Njeri Shop');
      await c.personalReads(_fromGrace(1));
      await c.alwaysBusiness(shopId);
      // The space leaves the list behind the rules' back.
      await c.open(personalSpaceId);
      await c.read(spacesProvider.notifier).remove(shopId);
      expect((await c.read(routingRulesProvider.future)).people, {
        _grace: shopId,
      });
      final summary = await c.read(smsIngestorProvider).ingest([
        _fromGrace(2),
      ], _mpesa);
      expect(summary.added, 1);

      await expectLater(
        c.read(sharedLineRouterProvider).applyRules(),
        throwsA(isA<SpaceNotOnPhone>()),
      );

      expect(await c.inPersonal(), ['TJA0000022']);
    });

    test('is not backed up, and no file is made for the copy', () async {
      final (c, dir) = await spacesOnFiles(clock: () => _now);
      final out = await Directory('${dir.path}/out').create();

      await expectLater(
        c.read(localDataStoreProvider).snapshot(out, space: 'gone1'),
        throwsA(isA<SpaceNotOnPhone>()),
      );

      expect(await hasFile('gone1'), isFalse);
      expect(out.listSync(), isEmpty);
    });

    test('is not opened when the app starts: it opens in Personal', () async {
      final store = _Store();
      final (c, _) = await spacesOnFiles(
        clock: () => _now,
        overrides: [
          activeSpaceIdProvider.overrideWith(() => ActiveSpaceId('gone1')),
          openSpaceChoiceProvider.overrideWith(() => OpenSpaceChoice('gone1')),
          activeSpaceStoreProvider.overrideWithValue(store),
        ],
      );

      await c.read(openSpaceCheckProvider.future);

      expect(c.read(activeSpaceIdProvider), personalSpaceId);
      expect(c.read(openSpaceChoiceProvider), openLastSpace);
      expect(store.written, [personalSpaceId, openLastSpace]);
      expect(
        c.read(appDatabaseProvider),
        same(c.read(personalDatabaseProvider)),
      );
      expect(await hasFile('gone1'), isFalse);
    });

    test('a space on the list opens as chosen', () async {
      final store = _Store();
      final (c, _) = await spacesOnFiles(
        clock: () => _now,
        overrides: [activeSpaceStoreProvider.overrideWithValue(store)],
      );
      final shopId = await c.addShop('Mama Njeri Shop');
      await c.read(openSpaceChoiceProvider.notifier).choose(shopId);
      store.written.clear();

      await c.read(openSpaceCheckProvider.future);

      expect(c.read(activeSpaceIdProvider), shopId);
      expect(c.read(openSpaceChoiceProvider), shopId);
      expect(store.written, isEmpty);
    });
  });
}

class _Store implements ActiveSpaceStore {
  final written = <String>[];

  @override
  Future<void> write(String spaceId) async => written.add(spaceId);

  @override
  Future<void> writeOpenChoice(String choice) async => written.add(choice);
}
