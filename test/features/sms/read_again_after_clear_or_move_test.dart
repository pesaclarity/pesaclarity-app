// Records a space cleared, moved away or removed stay gone when its
// messages are read again, also when two messages (or more) were kept as
// one transaction. Synthetic messages only.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/balances_repository.dart';
import 'package:pesaclarity/src/data/repositories/message_reads_repository.dart';
import 'package:pesaclarity/src/data/repositories/space_move_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/spaces/application/space_manager.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../helpers/sms_samples.dart';
import '../../helpers/spaces_harness.dart';
import '../../helpers/test_app.dart';

Institution _institution(String id) =>
    institutionCatalogue.singleWhere((i) => i.id == id);

/// M-Pesa's own message for a payment to KCB's paybill.
SmsMessage _mpesaPaybill({String tail = ''}) => mpesaSms(
  'TJA0000020 Confirmed. Ksh12,000.00 sent to KCB Money Transfer for '
  'account 1234567890 on 5/11/26 at 7:45 PM New M-PESA balance is '
  'Ksh3,000.00. Transaction cost, Ksh50.00.$tail',
  DateTime.utc(2026, 11, 5, 16, 45, 10),
);

/// KCB confirming that payment, with M-Pesa's reference.
SmsMessage _kcbPaybill() => kcbSms(
  'Ksh 12000.00 sent to KCB Pay Bill 522522 for account 123***7890 JANE '
  'AKINYI DOE has been received on 05/11/2026 at 07:45 PM. M-PESA ref '
  'TJA0000020. To reverse this transaction, SMS this message to 16120',
  DateTime.utc(2026, 11, 5, 16, 45, 20),
);

/// Money from a KCB account into M-Pesa, as KCB tells it and as M-Pesa
/// does: each with its own reference.
SmsMessage _kcbIntoMpesa() => kcbSms(
  'KCB0000000000031 Confirmed.  KES 2,500.00 received from MARY WAMBUI DOE '
  '- 987****654 on 2026-11-07 03:15:20 PM via KCB.',
  DateTime.utc(2026, 11, 7, 12, 16),
);

SmsMessage _mpesaFromKcb() => mpesaSms(
  'TJB0000031 Confirmed.You have received Ksh2,500.00 from KCB 1 522522 on '
  '7/11/26 at 3:15 PM New M-PESA balance is Ksh9,500.00.',
  DateTime.utc(2026, 11, 7, 12, 15, 30),
);

void main() {
  late AppDatabase personal;
  late AppDatabase shop;
  late ProviderContainer container;
  late SmsIngestor ingestor;
  final kcb = [_institution('kcb')];
  final kcbAndMpesa = [_institution('kcb'), _institution('mpesa')];
  final alert = kcbPesalinkAlert();
  final done = kcbPesalinkDone();

  setUp(() async {
    personal = openTestDatabase();
    shop = openTestDatabase();
    await shop.becomeSpace(SpaceKind.business);
    container = twoSpaces(
      personal: personal,
      other: shop,
      clock: () => DateTime.utc(2026, 11, 20),
    );
    ingestor = container.read(smsIngestorProvider);
  });

  Future<List<TransactionRecord>> rows(AppDatabase db) =>
      db.select(db.transactions).get();

  Future<Set<String>> setAside(AppDatabase db) async => {
    for (final m in await db.select(db.setAsideMessages).get()) m.messageHash,
  };

  SpaceMoveRepository mover(AppDatabase from, AppDatabase to) =>
      DriftSpaceMoveRepository(from, (id) async => (to, false));

  /// What "Read messages again", and the read after an update, do.
  Future<SmsIngestSummary> readAgain(
    List<SmsMessage> messages, [
    List<Institution>? selected,
  ]) => ingestor.ingest(messages, selected ?? kcb, again: true);

  group('two messages kept as one transaction', () {
    test('cleared with Clear data, it stays cleared', () async {
      await ingestor.ingest([alert, done], kcb);
      final one = (await rows(personal)).single;
      expect(one.messageHash, hashMessageBody(alert.body));
      expect(one.twinMessageHash, hashMessageBody(done.body));

      await container
          .read(spaceManagerProvider)
          .clear(Space.personal, keep: false);
      expect(await rows(personal), isEmpty);
      expect(await setAside(personal), {
        hashMessageBody(alert.body),
        hashMessageBody(done.body),
      });

      final summary = await readAgain([alert, done]);
      expect(summary.added, 0);
      expect(await rows(personal), isEmpty);
    });

    test('cleared with a date range, it stays cleared', () async {
      await ingestor.ingest([alert, done], kcb);
      await container
          .read(spaceManagerProvider)
          .clear(
            Space.personal,
            keep: false,
            from: DateTime.utc(2026, 11, 6),
            to: DateTime.utc(2026, 11, 7),
          );
      expect(await rows(personal), isEmpty);

      expect((await readAgain([alert, done])).added, 0);
      expect(await rows(personal), isEmpty);
    });

    for (final (order, first, second) in [
      ('the alert read first', alert, done),
      ('the confirmation read first', done, alert),
    ]) {
      test('moved to another space ($order), it is not back in the space '
          'it left', () async {
        await ingestor.ingest([first], kcb);
        await ingestor.ingest([second], kcb);
        final one = (await rows(personal)).single;
        expect(one.twinMessageHash, hashMessageBody(second.body));

        await mover(personal, shop).move(one.id, 'shop1');
        expect(await rows(personal), isEmpty);

        expect((await readAgain([alert, done])).added, 0);
        expect(await rows(personal), isEmpty);
        expect([for (final t in await rows(shop)) t.amountMinor], [800000]);
      });
    }

    test('moved back, it is one transaction there again and nothing of it '
        'is still set aside', () async {
      await ingestor.ingest([alert, done], kcb);
      final one = (await rows(personal)).single;
      await mover(personal, shop).move(one.id, 'shop1');
      expect(await setAside(personal), hasLength(2));

      final there = (await rows(shop)).single;
      await mover(shop, personal).move(there.id, personalSpaceId);
      expect(await rows(shop), isEmpty);
      expect(await setAside(personal), isEmpty);
      expect(await personal.select(personal.movedTransactions).get(), isEmpty);

      // Read again, both messages are still that one transaction.
      expect((await readAgain([alert, done])).added, 0);
      final back = (await rows(personal)).single;
      expect(back.amountMinor, 800000);
      expect(back.twinMessageHash, isNotNull);
    });

    test('removed as a copy, it stays removed', () async {
      await ingestor.ingest([alert, done], kcb);
      final copy = (await rows(personal)).single;
      final kept = await personal
          .into(personal.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: copy.accountId,
              occurredAt: copy.occurredAt,
              amountMinor: copy.amountMinor,
              direction: copy.direction,
              source: TransactionSource.manual,
            ),
          );
      await DriftBalancesRepository(personal).removeCopy(copy.id, keptId: kept);

      expect((await readAgain([alert, done])).added, 0);
      expect([for (final t in await rows(personal)) t.id], [kept]);
    });

    test('left where it is, reading again keeps it one transaction and '
        'sets nothing aside', () async {
      await ingestor.ingest([alert, done], kcb);
      expect((await readAgain([alert, done])).added, 0);
      expect(await rows(personal), hasLength(1));
      expect(await setAside(personal), isEmpty);
    });

    test('told by a bank and by M-Pesa with their own references, it '
        'stays cleared', () async {
      final messages = [_mpesaFromKcb(), _kcbIntoMpesa()];
      await ingestor.ingest(messages, kcbAndMpesa);
      final one = (await rows(personal)).single;
      expect(one.twinMessageHash, isNotNull);

      await container
          .read(spaceManagerProvider)
          .clear(Space.personal, keep: false);
      expect((await readAgain(messages, kcbAndMpesa)).added, 0);
      expect(await rows(personal), isEmpty);
    });
  });

  group('a third message with the same receipt', () {
    final messages = [
      _mpesaPaybill(),
      _kcbPaybill(),
      // The same receipt sent again, worded a little differently.
      _mpesaPaybill(
        tail: ' Amount you can transact within the day is 488,000.00.',
      ),
    ];

    test('is part of the one transaction while it is there', () async {
      for (final m in messages) {
        await ingestor.ingest([m], kcbAndMpesa);
      }
      expect(await rows(personal), hasLength(1));
      expect((await readAgain(messages, kcbAndMpesa)).added, 0);
      expect(await rows(personal), hasLength(1));
    });

    test('stays out once the transaction is cleared', () async {
      for (final m in messages) {
        await ingestor.ingest([m], kcbAndMpesa);
      }
      await container
          .read(spaceManagerProvider)
          .clear(Space.personal, keep: false);

      expect((await readAgain(messages, kcbAndMpesa)).added, 0);
      expect(await rows(personal), isEmpty);
    });

    test('stays out once the transaction is moved to another space', () async {
      for (final m in messages) {
        await ingestor.ingest([m], kcbAndMpesa);
      }
      final one = (await rows(personal)).single;
      await mover(personal, shop).move(one.id, 'shop1');

      expect((await readAgain(messages, kcbAndMpesa)).added, 0);
      expect(await rows(personal), isEmpty);
      expect(await rows(shop), hasLength(1));
    });
  });

  test('one message, one transaction: only its own message is set '
      'aside', () async {
    await ingestor.ingest([done], kcb);
    final one = (await rows(personal)).single;
    expect(one.twinMessageHash, isNull);
    await setAsideMessagesOf(personal, [one.id]);
    expect(await setAside(personal), {hashMessageBody(done.body)});
  });

  test('a transaction typed by hand has no message to set aside', () async {
    final account = await personal
        .into(personal.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'Cash',
            type: AccountType.cash,
            openingDate: DateTime.utc(2026, 11),
          ),
        );
    final id = await personal
        .into(personal.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: account,
            occurredAt: DateTime.utc(2026, 11, 6),
            amountMinor: 5000,
            direction: TransactionDirection.outflow,
            source: TransactionSource.manual,
          ),
        );
    await setAsideMessagesOf(personal, [id]);
    expect(await setAside(personal), isEmpty);
  });
}
