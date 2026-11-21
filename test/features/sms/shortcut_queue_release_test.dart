// iPhone: messages wait in one queue for the whole app until a scan reads
// them. A scan lets go of only what it read, so the messages of accounts
// another space reads wait for that space. Made-up data only.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/data/repositories/review_inbox_repository.dart';
import 'package:pesaclarity/src/data/repositories/sms_scan_marks_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/sms/application/sms_scan_service.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../helpers/fake_sms_source.dart';
import '../../helpers/sms_samples.dart';
import '../../helpers/spaces_harness.dart';
import '../../helpers/test_app.dart';

Institution _institution(String id) =>
    institutionCatalogue.singleWhere((i) => i.id == id);

/// KES 5,000 into M-Pesa, received at [at].
SmsMessage _mpesaIn(DateTime at, {String receipt = 'TJA0000501'}) => mpesaSms(
  '$receipt Confirmed.You have received Ksh5,000.00 from TEST SENDER '
  '0700***002 on 20/11/26 at 10:02 AM  New M-PESA balance is Ksh9,035.00.',
  at,
);

/// KES 3,000 out of a KCB account, received at [at].
SmsMessage _kcbOut(DateTime at) => kcbSms(
  'Dear Customer, KES 3,000.00 has been debited from your account ****0001 '
  'on 20/11/2026 at 10:20. Transaction Ref: KCB0000000501. Your available '
  'balance is KES 7,000.00.',
  at,
);

void main() {
  test('a message for an account only Personal reads is still read after '
      'the app opened in the business first', () async {
    final queue = ShortcutQueue();
    addTearDown(queue.close);
    final personal = openTestDatabase();
    final shop = openTestDatabase();
    await shop.becomeSpace(SpaceKind.business);
    await DriftAppSettingsRepository(personal).writeJson(
      SpacesController.settingsKey,
      spacesToJson(const [
        Space.personal,
        Space(id: 'shop1', name: 'Test Shop', kind: SpaceKind.business),
      ]),
    );
    await DriftInstitutionsRepository(personal)
        .setSelected('mpesa', selected: true);
    await DriftInstitutionsRepository(shop).setSelected('kcb', selected: true);
    final earlier = DateTime.now().toUtc().subtract(
      const Duration(minutes: 10),
    );
    queue
      ..append(_mpesaIn(earlier))
      ..append(_kcbOut(earlier.add(const Duration(minutes: 1))));

    final c = twoSpaces(
      personal: personal,
      other: shop,
      sms: queue,
      clock: DateTime.now,
      active: 'shop1',
    );
    Future<List<String?>> receipts(AppDatabase db) async => [
      for (final t in await db.select(db.transactions).get()) t.receiptNo,
    ];
    final shell = c.listen(liveSmsCaptureProvider, (_, _) {});
    addTearDown(shell.close);
    await until(() async => (await receipts(shop)).isNotEmpty);
    await settle();
    expect(await receipts(shop), ['KCB0000000501']);
    // The shop let go of its own KCB message only.
    expect(queue.released, ['KCB']);
    expect([for (final m in queue.queue) m.sender], ['MPESA']);

    await c.read(activeSpaceIdProvider.notifier).switchTo(personalSpaceId);
    await until(() async => (await receipts(personal)).isNotEmpty);
    expect(await receipts(personal), ['TJA0000501']);
    await settle();
    expect(queue.queue, isEmpty);
  });

  group('a scan lets go of', () {
    late AppDatabase db;
    late ShortcutQueue queue;
    final start = DateTime.utc(2026, 11, 20, 9);

    setUp(() {
      db = openTestDatabase();
      queue = ShortcutQueue();
    });

    SmsScanService scans({DateTime? at}) => SmsScanService(
      source: queue,
      ingestor: SmsIngestor(
        accounts: DriftAccountsRepository(db),
        transactions: DriftTransactionsRepository(db),
        reviewInbox: DriftReviewInboxRepository(db),
        parse: (packs, messages) async => parseAll(packs, messages),
      ),
      marks: DriftSmsScanMarksRepository(db),
      clock: () => at ?? start,
    );

    test('what it read, and nothing that came after it began', () async {
      queue
        ..append(_mpesaIn(start.subtract(const Duration(hours: 1))))
        ..append(
          _mpesaIn(
            start.add(const Duration(minutes: 1)),
            receipt: 'TJA0000502',
          ),
        );

      await scans().scan([_institution('mpesa')]);

      // The later one was read too, but stays for the next scan, which
      // starts from this one's start.
      expect(
        [for (final m in queue.queue) m.receivedAt],
        [start.add(const Duration(minutes: 1))],
      );
      await scans(at: start.add(const Duration(hours: 1)))
          .scan([_institution('mpesa')]);
      expect(queue.queue, isEmpty);
    });

    test('nothing from before the start it was told to read from', () async {
      final old = start.subtract(const Duration(days: 20));
      queue
        ..append(_mpesaIn(old))
        ..append(
          _mpesaIn(
            start.subtract(const Duration(days: 1)),
            receipt: 'TJA0000502',
          ),
        );

      await scans().scan([
        _institution('mpesa'),
      ], from: start.subtract(const Duration(days: 7)));

      expect([for (final m in queue.queue) m.receivedAt], [old]);
    });

    test('nothing of an account it does not read', () async {
      queue
        ..append(_kcbOut(start.subtract(const Duration(hours: 2))))
        ..append(_mpesaIn(start.subtract(const Duration(hours: 1))));

      await scans().scan([_institution('mpesa')]);

      expect([for (final m in queue.queue) m.sender], ['KCB']);
    });
  });

  test('the iPhone channel is told the senders and the time read', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('com.pesaclarity.app/sms');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final since = DateTime.utc(2026, 11);
    final before = DateTime.utc(2026, 11, 20, 9);

    await const ShortcutSmsSource().release(
      senders: {'MPESA'},
      since: since,
      before: before,
    );
    await const ShortcutSmsSource().release(
      senders: const {},
      since: since,
      before: before,
    );

    expect(calls, hasLength(1));
    expect(calls.single.method, 'release');
    expect(calls.single.arguments, {
      'senders': ['MPESA'],
      'sinceMillis': since.millisecondsSinceEpoch,
      'beforeMillis': before.millisecondsSinceEpoch,
    });
  });
}
