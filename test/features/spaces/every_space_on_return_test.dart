// Every space's accounts are read on start and each time the app returns to
// the front, whichever space is open: a message for the business's account
// that lands while Personal is open is in the business after the return, in
// that space only, and reading again in either space adds nothing. On
// iPhone, the queue lets go of an M-Pesa message only once every space that
// reads one of its lines has read it. Made-up names, numbers and amounts
// only.
import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/database/space_databases.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/domain/accounts/mpesa_lines.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/accounts/application/mpesa_lines_providers.dart';
import 'package:pesaclarity/src/features/sms/application/read_again.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../helpers/fake_sms_source.dart';
import '../../helpers/sms_samples.dart';
import '../../helpers/spaces_harness.dart';
import '../../helpers/test_app.dart';

const _shop = Space(
  id: 'shop1',
  name: 'Green Basket Grocers',
  kind: SpaceKind.business,
);

SmsMessage _paid(String receipt, int day, int balance) => mpesaSms(
  '$receipt Confirmed. Ksh350.00 paid to EXAMPLE GROCERS. on $day/11/26 at '
  '1:45 PM.New M-PESA balance is Ksh$balance.00. Transaction cost, '
  'Ksh0.00.',
  DateTime.utc(2026, 11, day, 10, 45, 5),
);

/// KCB's message for KES 3,000.00 out on [day] November, received at [at].
SmsMessage _kcbOut(String ref, String balance, int day, DateTime at) => kcbSms(
  'Dear Customer, KES 3,000.00 has been debited from your account ****0001 '
  'on $day/11/2026 at 10:20. Transaction Ref: $ref. Your available '
  'balance is KES $balance.',
  at,
);

/// M-Pesa's message for KES [shillings] sent at 7:[minute] on 20 November,
/// leaving KES [balance]; on iPhone it says no SIM.
SmsMessage _sent(String receipt, int shillings, int balance, int minute) {
  String ksh(int v) =>
      'Ksh${v ~/ 1000 > 0 ? '${v ~/ 1000},${'${v % 1000}'.padLeft(3, '0')}' : '$v'}.00';
  final mm = '$minute'.padLeft(2, '0');
  return mpesaSms(
    '$receipt Confirmed. ${ksh(shillings)} sent to JANE DOE 0700***001 on '
    '20/11/26 at 10:$mm AM. New M-PESA balance is ${ksh(balance)}. '
    'Transaction cost, Ksh0.00. Amount you can transact within the day is '
    '498,500.00.',
    DateTime.utc(2026, 11, 20, 7, minute, 5),
  );
}

/// The iPhone's Shortcuts queue.
class _IphoneQueue extends ShortcutQueue implements ShortcutConnection {
  @override
  Future<DateTime?> lastArrival() async => null;

  @override
  Future<void> openShortcuts() async {}
}

void main() {
  late AppDatabase personal;
  late AppDatabase shop;

  Future<List<String?>> receipts(AppDatabase db) async => [
    for (final t in await (db.select(
      db.transactions,
    )..orderBy([(t) => OrderingTerm.asc(t.occurredAt)])).get())
      t.receiptNo,
  ];

  setUp(() async {
    personal = openTestDatabase();
    shop = openTestDatabase();
    await shop.becomeSpace(_shop.kind);
    await DriftAppSettingsRepository(personal).writeJson(
      SpacesController.settingsKey,
      spacesToJson([Space.personal, _shop]),
    );
  });

  test("a message for the business's account that lands while Personal is "
      'open is in the business after the return, once', () async {
    await DriftInstitutionsRepository(personal)
        .setSelected(mpesaInstitutionId, selected: true);
    await DriftInstitutionsRepository(shop).setSelected('kcb', selected: true);
    final phone = PhoneInbox();
    addTearDown(phone.close);
    phone
      ..receive(_paid('TJA0000701', 10, 29650))
      ..receive(
        _kcbOut('KCB0000000701', '7,000.00', 11, DateTime.utc(2026, 11, 11, 7)),
      );
    final resumed = StreamController<void>.broadcast();
    addTearDown(resumed.close);
    final c = twoSpaces(
      personal: personal,
      other: shop,
      sms: phone,
      clock: () => DateTime.utc(2026, 11, 20, 9),
      resumed: resumed.stream,
    );
    final shell = c.listen(liveSmsCaptureProvider, (_, _) {});
    addTearDown(shell.close);

    // On start: each space's own, Personal open.
    await until(() async => (await receipts(shop)).isNotEmpty);
    await captureIsSteady(phone);
    expect(await receipts(personal), ['TJA0000701']);
    expect(await receipts(shop), ['KCB0000000701']);

    // While Personal is open the phone passes on only Personal's senders: a
    // KCB message lands and waits in the inbox. Scans mark the phone's own
    // time, so it lands now.
    phone.receive(
      _kcbOut('KCB0000000702', '4,000.00', 20, DateTime.now().toUtc()),
    );
    await settle();
    expect(await receipts(shop), ['KCB0000000701']);

    // Back at the front: the business has it, with its balance.
    resumed.add(null);
    await until(() async => (await receipts(shop)).length == 2);
    await settle();
    expect(await receipts(shop), ['KCB0000000701', 'KCB0000000702']);
    final latest = await (shop.select(
      shop.transactions,
    )..where((t) => t.receiptNo.equals('KCB0000000702'))).getSingle();
    expect(latest.balanceAfterMinor, 400000);
    expect(await receipts(personal), ['TJA0000701'], reason: 'its own only');

    // Another return, and Read messages again in either space, add nothing.
    resumed.add(null);
    await settle();
    await c.read(readAgainControllerProvider.notifier).readAgain();
    await settle();
    await c.read(activeSpaceIdProvider.notifier).switchTo(_shop.id);
    await captureIsSteady(phone);
    await c.read(readAgainControllerProvider.notifier).readAgain();
    resumed.add(null);
    await settle();
    expect(await receipts(personal), ['TJA0000701']);
    expect(await receipts(shop), ['KCB0000000701', 'KCB0000000702']);
  });

  test('a message another space already holds is not stored again in the '
      'space that reads its account', () async {
    // Personal read this payment before the shop was given M-Pesa.
    await DriftInstitutionsRepository(personal)
        .setSelected(mpesaInstitutionId, selected: true);
    final phone = PhoneInbox();
    addTearDown(phone.close);
    phone.receive(_paid('TJA0000711', 10, 29650));
    final c = twoSpaces(
      personal: personal,
      other: shop,
      sms: phone,
      clock: () => DateTime.utc(2026, 11, 20, 9),
    );
    var shell = c.listen(liveSmsCaptureProvider, (_, _) {});
    await until(() async => (await receipts(personal)).isNotEmpty);
    await captureIsSteady(phone);
    shell.close();

    // Only the shop reads M-Pesa from now on, with Personal still open: the
    // shop is read on start, and Personal keeps what it read.
    await DriftInstitutionsRepository(personal)
        .setSelected(mpesaInstitutionId, selected: false);
    await DriftInstitutionsRepository(shop)
        .setSelected(mpesaInstitutionId, selected: true);
    phone.receive(_paid('TJA0000712', 12, 29300));
    c.invalidate(liveSmsCaptureProvider);
    shell = c.listen(liveSmsCaptureProvider, (_, _) {});
    addTearDown(shell.close);
    await until(() async => (await receipts(shop)).isNotEmpty);
    await settle();
    expect(await receipts(shop), ['TJA0000712']);
    expect(await receipts(personal), ['TJA0000711']);
  });

  group('iPhone, two lines', () {
    late _IphoneQueue queue;

    Future<ProviderContainer> app({bool shopTracked = true}) async {
      // Split: My line in Personal (last at KES 12,500), Shop line in the
      // shop (last at KES 24,330).
      await DriftAppSettingsRepository(personal).writeJson(
        mpesaLinesKey,
        MpesaLines(
          split: true,
          surveyed: true,
          lines: [
            MpesaLine(
              id: '1',
              name: 'My line',
              balanceMinor: 1250000,
              balanceAt: DateTime.utc(2026, 11, 19),
            ),
            MpesaLine(
              id: '2',
              name: 'Shop line',
              spaceId: _shop.id,
              balanceMinor: 2433000,
              balanceAt: DateTime.utc(2026, 11, 19),
              tracked: shopTracked,
            ),
          ],
        ).toJson(),
      );
      final personalReads = DriftInstitutionsRepository(personal);
      await personalReads.setSelected(mpesaInstitutionId, selected: true);
      await personalReads.setSelected(lineSelectionId('1'), selected: true);
      await DriftInstitutionsRepository(shop)
          .setSelected(lineSelectionId('2'), selected: true);
      queue = _IphoneQueue();
      addTearDown(queue.close);
      queue
        ..append(_sent('TKA0000721', 500, 12000, 1))
        ..append(_sent('TKA0000722', 300, 24030, 2));
      return twoSpaces(
        personal: personal,
        other: shop,
        sms: queue,
        clock: () => DateTime.utc(2026, 11, 20, 9),
      );
    }

    test('each line is read in its space on start, and the queue lets go '
        'once both have read', () async {
      final c = await app();
      final shell = c.listen(liveSmsCaptureProvider, (_, _) {});
      addTearDown(shell.close);
      await until(() async => (await receipts(shop)).isNotEmpty);
      await settle();
      expect(await receipts(personal), ['TKA0000721']);
      expect(await receipts(shop), ['TKA0000722']);
      expect(queue.queue, isEmpty);
    });

    test('a line not tracked is skipped by every space on return, and the '
        'first skip leaves the quiet note due', () async {
      final c = await app(shopTracked: false);
      final shell = c.listen(liveSmsCaptureProvider, (_, _) {});
      addTearDown(shell.close);
      await until(() async => (await receipts(personal)).isNotEmpty);
      await settle();
      expect(await receipts(personal), ['TKA0000721']);
      expect(await receipts(shop), isEmpty);
      final lines = await c.read(mpesaLinesProvider.notifier).saved();
      expect(lines.skipNote, SkipNote.due);
      expect(lines.skippedLineId, '2');
    });

    test(
      'while the shop cannot be read, the queue keeps its messages',
      () async {
        final c = await app();
        final spaces = c.read(spaceDatabasesProvider) as TwoSpaceDatabases;
        spaces.unreadable.add(_shop.id);
        final shell = c.listen(liveSmsCaptureProvider, (_, _) {});
        addTearDown(shell.close);
        await until(() async => (await receipts(personal)).isNotEmpty);
        await settle();
        expect(await receipts(personal), ['TKA0000721']);
        expect(await receipts(shop), isEmpty);
        expect(queue.queue, hasLength(2), reason: 'the shop has read nothing');
      },
    );
  });
}
