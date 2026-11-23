// Two M-Pesa lines on one phone, through the app's own providers: keyed by
// SIM, split and read again with nothing stored twice, each line read in
// the space it is given, and on iPhone the questions the balance cannot
// answer. Made-up names, numbers and amounts only.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/data/repositories/own_moves.dart';
import 'package:pesaclarity/src/data/repositories/space_leak_repair.dart';
import 'package:pesaclarity/src/domain/accounts/mpesa_lines.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/accounts/application/mpesa_lines_providers.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/balances/application/balances_providers.dart';
import 'package:pesaclarity/src/features/review/application/review_providers.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:pesaclarity/src/features/spaces/application/routing_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../helpers/fake_sms_source.dart';
import '../../helpers/spaces_harness.dart';
import '../../helpers/test_app.dart';

const _shop = Space(
  id: 'shop1',
  name: 'Green Basket Grocers',
  kind: SpaceKind.business,
);

String _ksh(int shillings) {
  final digits = '$shillings';
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return 'Ksh$out.00';
}

/// M-Pesa's message for [shillings] sent at 10:[minute] on 20 November,
/// leaving [balance], as it arrived on [sim] (none: the phone did not say).
SmsMessage _sent(
  String receipt,
  int shillings,
  int balance,
  int minute, {
  String? sim,
}) {
  final mm = '$minute'.padLeft(2, '0');
  final body =
      '$receipt Confirmed. ${_ksh(shillings)} sent to JANE DOE 0700***001 on '
      '20/11/26 at 10:$mm AM. New M-PESA balance is ${_ksh(balance)}. '
      'Transaction cost, Ksh0.00. Amount you can transact within the day is '
      '498,500.00.';
  final at = DateTime.utc(2026, 11, 20, 7, minute, 5);
  return sim == null
      ? SmsMessage(sender: 'MPESA', body: body, receivedAt: at)
      : LineSmsMessage(sender: 'MPESA', body: body, receivedAt: at, line: sim);
}

/// Two lines in use at once: SIM 3 from 12,500 and SIM 5 from 24,330.
List<SmsMessage> _twoLines() => [
  _sent('TKA0000001', 500, 12500, 1, sim: 'sim:3'),
  _sent('TKA0000002', 300, 24330, 2, sim: 'sim:5'),
  _sent('TKA0000003', 200, 12300, 3, sim: 'sim:3'),
  _sent('TKA0000004', 100, 24230, 4, sim: 'sim:5'),
  _sent('TKA0000005', 450, 11850, 5, sim: 'sim:3'),
];

/// The iPhone's Shortcuts queue: no SIM, and no past messages to read again.
class _ShortcutQueue extends FakeSmsSource implements ShortcutConnection {
  _ShortcutQueue({super.inbox});

  @override
  Future<DateTime?> lastArrival() async => null;

  @override
  Future<void> openShortcuts() async {}
}

void main() {
  _leakRepairByLine();
  late AppDatabase personal;
  late AppDatabase shop;

  Future<ProviderContainer> app({
    required SmsSource sms,
    String open = personalSpaceId,
  }) async {
    await shop.becomeSpace(_shop.kind);
    await DriftAppSettingsRepository(personal).writeJson(
      SpacesController.settingsKey,
      spacesToJson([Space.personal, _shop]),
    );
    return twoSpaces(
      personal: personal,
      other: shop,
      sms: sms,
      clock: () => DateTime.utc(2026, 11, 20, 7),
      active: open,
    );
  }

  /// Reads every message again, as this space reads them (the scan marks
  /// go by the real time, after these made-up messages): what is stored
  /// already is skipped.
  Future<void> scan(ProviderContainer c, AppDatabase db) async {
    final selected = institutionsReadWith(
      institutionCatalogue,
      await DriftInstitutionsRepository(db).selectedIds(),
    );
    await c
        .read(smsScanServiceProvider)
        .scan(selected, from: DateTime.utc(2026, 11), again: true);
  }

  /// Receipts on each M-Pesa account of [db], by the account's reference.
  Future<Map<String?, Set<String?>>> byAccount(AppDatabase db) async {
    final out = <String?, Set<String?>>{};
    final accounts = await db.select(db.accounts).get();
    for (final a in accounts) {
      out[a.reference] = {
        for (final t in await (db.select(
          db.transactions,
        )..where((t) => t.accountId.equals(a.id))).get())
          t.receiptNo,
      };
    }
    return out;
  }

  Future<int> count(AppDatabase db) async =>
      (await db.select(db.transactions).get()).length;

  setUp(() async {
    personal = openTestDatabase();
    shop = openTestDatabase();
    await DriftInstitutionsRepository(personal)
        .setSelected(mpesaInstitutionId, selected: true);
  });

  test('a SIM from the platform channel is an opaque line key', () {
    final withSim = PlatformSmsSource.fromChannel({
      'sender': 'MPESA',
      'body': 'x',
      'receivedAtMillis': 0,
      'subscriptionId': 3,
    });
    expect(lineOf(withSim), 'sim:3');
    final without = PlatformSmsSource.fromChannel({
      'sender': 'MPESA',
      'body': 'x',
      'receivedAtMillis': 0,
    });
    expect(lineOf(without), isNull);
    expect(
      lineOf(
        PlatformSmsSource.fromChannel({
          'sender': 'MPESA',
          'body': 'x',
          'receivedAtMillis': 0,
          'subscriptionId': -1,
        }),
      ),
      isNull,
    );
  });

  test('two lines are read as one until split; the split reads them again '
      'onto their own lines with nothing stored twice', () async {
    final c = await app(sms: FakeSmsSource(inbox: _twoLines()));
    await scan(c, personal);

    // Read as one account, as before; the lines are counted.
    expect(await byAccount(personal), {
      null: {
        'TKA0000001',
        'TKA0000002',
        'TKA0000003',
        'TKA0000004',
        'TKA0000005',
      },
    });
    final legacy = (await personal.select(personal.accounts).getSingle()).id;
    var lines = await c.read(mpesaLinesProvider.future);
    expect(lines.offersSplit, isTrue);
    expect(lines.line('1')!.messages, 3);
    expect(lines.line('2')!.balanceMinor, 2423000);

    await c.read(lineSplitControllerProvider.notifier).split({
      '1': const LineSetting(spaceId: personalSpaceId, name: 'My line'),
      '2': const LineSetting(spaceId: personalSpaceId, name: 'Shop line'),
    });
    expect(c.read(lineSplitControllerProvider).stage, LineSplitStage.finished);
    expect(await byAccount(personal), {
      'line:1': {'TKA0000001', 'TKA0000003', 'TKA0000005'},
      'line:2': {'TKA0000002', 'TKA0000004'},
    });
    // The busier line keeps the account they were read into, with what the
    // person set on it.
    final kept = await (personal.select(
      personal.accounts,
    )..where((a) => a.id.equals(legacy))).getSingle();
    expect(kept.reference, 'line:1');
    lines = await c.read(mpesaLinesProvider.future);
    expect(lines.split, isTrue);
    expect(lines.line('2')!.label, 'Shop line');

    // Read again: the same.
    await scan(c, personal);
    await scan(c, personal);
    expect(await count(personal), 5);
    expect((await byAccount(personal))['line:2'], hasLength(2));
  });

  test('a line given to a business is read there, with its payments and '
      'balance, and not in Personal', () async {
    final phone = FakeSmsSource(inbox: _twoLines());
    final c = await app(sms: phone);
    await scan(c, personal);
    await c.read(lineSplitControllerProvider.notifier).split({
      '1': const LineSetting(spaceId: personalSpaceId, name: 'My line'),
      '2': LineSetting(spaceId: _shop.id, name: 'Shop line'),
    });

    expect(await byAccount(personal), {
      'line:1': {'TKA0000001', 'TKA0000003', 'TKA0000005'},
      // Left empty, and not shown.
      'line:2': <String?>{},
    });
    expect(await byAccount(shop), {
      'line:2': {'TKA0000002', 'TKA0000004'},
    });
    final moved = await shop.select(shop.transactions).get();
    // The business reads the line: the balance its messages printed came
    // along.
    expect(
      moved.map((t) => t.balanceAfterMinor),
      containsAll([2433000, 2423000]),
    );
    expect(await DriftInstitutionsRepository(shop).selectedIds(), {
      lineSelectionId('2'),
    });
    expect(
      await DriftInstitutionsRepository(personal).selectedIds(),
      containsAll([mpesaInstitutionId, lineSelectionId('1')]),
    );

    // A new payment on each line: Personal reads only My line.
    phone.inbox
      ..add(_sent('TKA0000006', 1000, 10850, 20, sim: 'sim:3'))
      ..add(_sent('TKA0000007', 230, 24000, 21, sim: 'sim:5'));
    await scan(c, personal);
    expect((await byAccount(personal))['line:1'], contains('TKA0000006'));
    expect(await count(personal), 4);

    // The business reads the Shop line when it opens.
    await c.read(activeSpaceIdProvider.notifier).switchTo(_shop.id);
    await scan(c, shop);
    expect((await byAccount(shop))['line:2'], {
      'TKA0000002',
      'TKA0000004',
      'TKA0000007',
    });
    expect(await count(shop), 3);

    // And back to Personal: moving the line brings it all back.
    await c.read(activeSpaceIdProvider.notifier).switchTo(personalSpaceId);
    await c
        .read(mpesaLineRoutingProvider)
        .choose('2', const LineSetting(spaceId: personalSpaceId));
    expect(await count(shop), 0);
    expect((await byAccount(personal))['line:2'], {
      'TKA0000002',
      'TKA0000004',
      'TKA0000007',
    });
  });

  test('Both: Personal reads the line and the business asks about its '
      'payments only', () async {
    final c = await app(sms: FakeSmsSource(inbox: _twoLines()));
    await scan(c, personal);
    await c.read(lineSplitControllerProvider.notifier).split({
      '1': const LineSetting(spaceId: personalSpaceId, name: 'My line'),
      '2': LineSetting(
        spaceId: personalSpaceId,
        sharedWith: _shop.id,
        name: 'Shop line',
      ),
    });
    expect(await count(personal), 5);
    expect(await count(shop), 0);
    final rules = await c.read(routingRulesProvider.future);
    expect(rules.sharedLines, {lineSelectionId('2'): _shop.id});
    final asked = await c.read(sharedLineRouterProvider).pending(_shop.id);
    expect(asked.map((q) => q.amountMinor).toSet(), {30000, 10000});
  });

  test('a SIM not seen before waits for "Is this the same line?", then is '
      'read on the line chosen', () async {
    final phone = FakeSmsSource(inbox: _twoLines());
    final c = await app(sms: phone);
    await scan(c, personal);
    await c.read(lineSplitControllerProvider.notifier).split({
      '1': const LineSetting(spaceId: personalSpaceId, name: 'My line'),
      '2': const LineSetting(spaceId: personalSpaceId, name: 'Shop line'),
    });

    // A new phone: My line's SIM has a new key, and a message was missed.
    phone.inbox.add(_sent('TKA0000010', 150, 9000, 40, sim: 'sim:9'));
    await scan(c, personal);
    expect(await count(personal), 5);
    final lines = await c.read(mpesaLinesProvider.future);
    final (question, line) = lines.nextSimQuestion!;
    expect(question.sim, 'sim:9');
    expect(question.firstBalanceMinor, 900000);
    expect(line.label, 'My line');

    await c.read(mpesaLineRoutingProvider).answerSim('sim:9', '1', same: true);
    expect((await byAccount(personal))['line:1'], contains('TKA0000010'));
    expect(await count(personal), 6);
    expect((await c.read(mpesaLinesProvider.future)).newSims, isEmpty);
  });

  group('iPhone', () {
    /// Two split lines kept by balance, with an account each.
    Future<ProviderContainer> splitOnIphone(_ShortcutQueue queue) async {
      final c = await app(sms: queue);
      await scan(c, personal);
      await c.read(lineSplitControllerProvider.notifier).split({
        '1': const LineSetting(spaceId: personalSpaceId, name: 'My line'),
        '2': const LineSetting(spaceId: personalSpaceId, name: 'Shop line'),
      });
      return c;
    }

    List<SmsMessage> noSims() => [
      for (final m in _twoLines())
        SmsMessage(sender: m.sender, body: m.body, receivedAt: m.receivedAt),
    ];

    test('lines are told apart by balance and the stored history is sorted '
        'onto them', () async {
      final c = await splitOnIphone(_ShortcutQueue(inbox: noSims()));
      expect(await byAccount(personal), {
        'line:1': {'TKA0000001', 'TKA0000003', 'TKA0000005'},
        'line:2': {'TKA0000002', 'TKA0000004'},
      });
      expect(
        (await c.read(mpesaLinesProvider.future)).line('1')!.slot,
        'Line 1',
      );
    });

    test('"Which line was this?" when the balance cannot say, and Not yet '
        'sorted once asked not to ask', () async {
      final queue = _ShortcutQueue(inbox: noSims());
      final c = await splitOnIphone(queue);
      // Fits neither line's balance.
      queue.inbox.add(_sent('TKA0000020', 300, 5000, 30));
      await scan(c, personal);
      expect(await count(personal), 5);

      final waiting = await personal.select(personal.reviewItems).get();
      expect(waiting.single.reason, whichLineReason);
      final sub = c.listen(pendingReviewProvider, (_, _) {});
      addTearDown(sub.close);
      final which = c.listen(whichLineItemsProvider, (_, _) {});
      addTearDown(which.close);
      expect(await c.read(pendingReviewProvider.future), isEmpty);
      final asked = await c.read(whichLineItemsProvider.future);
      expect(asked, hasLength(1));

      await c.read(mpesaLineRoutingProvider).answerWhichLine(asked.single, '2');
      expect((await byAccount(personal))['line:2'], contains('TKA0000020'));
      final lines = await c.read(mpesaLinesProvider.future);
      expect(lines.line('2')!.balanceMinor, 500000);

      // Don't ask me again: the next unsure one waits in Not yet sorted.
      await c.read(askWhichLineProvider.notifier).set(false);
      queue.inbox.add(_sent('TKA0000021', 10, 777, 31));
      await scan(c, personal);
      await until(
        () async => (await c.read(pendingReviewProvider.future)).isNotEmpty,
      );
      expect(
        (await c.read(pendingReviewProvider.future)).single.reason,
        whichLineReason,
      );
      expect(await c.read(whichLineItemsProvider.future), isEmpty);
    });
  });

  group('many lines', () {
    Future<ProviderContainer> splitTwo(SmsSource sms) async {
      final c = await app(sms: sms);
      await scan(c, personal);
      await c.read(lineSplitControllerProvider.notifier).split({
        '1': const LineSetting(spaceId: personalSpaceId, name: 'My line'),
        '2': const LineSetting(spaceId: personalSpaceId, name: 'Old line'),
      });
      return c;
    }

    Future<Account> lineAccount(String id) => (personal.select(
      personal.accounts,
    )..where((a) => a.reference.equals(lineReference(id)))).getSingle();

    Future<void> live(ProviderContainer c, SmsMessage message) => c
        .read(smsIngestorProvider)
        .ingest(
          [message],
          [institutionCatalogue.singleWhere((i) => i.id == mpesaInstitutionId)],
        );

    test("Don't track, keeping its past records: they stay, its balance "
        'leaves the totals, and its new messages are skipped live and when '
        'read again', () async {
      final phone = FakeSmsSource(inbox: _twoLines());
      final c = await splitTwo(phone);
      await c.read(mpesaLineRoutingProvider).untrack('2', deleteRecords: false);

      expect((await byAccount(personal))['line:2'], {
        'TKA0000002',
        'TKA0000004',
      });
      expect((await lineAccount('2')).countsOnHand, isFalse);
      final skipped = _sent('TKA0000030', 100, 24130, 30, sim: 'sim:5');
      await live(c, skipped);
      phone.inbox
        ..add(skipped)
        ..add(_sent('TKA0000031', 100, 11750, 31, sim: 'sim:3'));
      await scan(c, personal);
      await scan(c, personal);
      final after = await byAccount(personal);
      expect(after['line:2'], {'TKA0000002', 'TKA0000004'});
      expect(after['line:1'], contains('TKA0000031'));
      final lines = await c.read(mpesaLinesProvider.future);
      expect(lines.skipNote, SkipNote.due);
      expect(lines.skippedLineId, '2');

      // A role tracks it again, and its balance counts.
      await c.read(mpesaLineRoutingProvider).setRole('2', LineRole.second);
      expect((await lineAccount('2')).countsOnHand, isNull);
      expect(
        (await c.read(mpesaLinesProvider.future)).line('2')!.tracked,
        isTrue,
      );
    });

    test("Don't track, deleting its records: they go, their messages set "
        'aside, and reading again never brings them back', () async {
      final phone = FakeSmsSource(inbox: _twoLines());
      final c = await splitTwo(phone);
      expect(await c.read(mpesaLineRoutingProvider).recordCount('2'), 2);
      await c.read(mpesaLineRoutingProvider).untrack('2', deleteRecords: true);
      expect((await byAccount(personal))['line:2'], isEmpty);
      expect(
        await personal.select(personal.setAsideMessages).get(),
        hasLength(2),
      );
      expect(await count(personal), 3);

      phone.inbox.add(_sent('TKA0000032', 100, 24130, 32, sim: 'sim:5'));
      await scan(c, personal);
      await scan(c, personal);
      expect((await byAccount(personal))['line:2'], isEmpty);
      expect(await count(personal), 3);
    });

    test('Same line as: the older line joins the kept one, with its records '
        'and SIM', () async {
      final phone = FakeSmsSource(inbox: _twoLines());
      final c = await splitTwo(phone);
      await c.read(mpesaLineRoutingProvider).merge('2', '1');
      final accounts = await byAccount(personal);
      expect(accounts.containsKey('line:2'), isFalse);
      expect(accounts['line:1'], {
        'TKA0000001',
        'TKA0000002',
        'TKA0000003',
        'TKA0000004',
        'TKA0000005',
      });
      expect(
        await DriftInstitutionsRepository(personal).selectedIds(),
        isNot(contains(lineSelectionId('2'))),
      );
      final lines = await c.read(mpesaLinesProvider.future);
      expect(lines.line('2'), isNull);
      expect(lines.line('1')!.sims, {'sim:3', 'sim:5'});
      expect(lines.line('1')!.messages, 5);
      // Its SIM now reads onto the kept line.
      phone.inbox.add(_sent('TKA0000033', 100, 24130, 33, sim: 'sim:5'));
      await scan(c, personal);
      expect((await byAccount(personal))['line:1'], contains('TKA0000033'));
    });

    test('the quick setup splits the lines, keeps the two most recent and '
        'skips the rest from then on', () async {
      final phone = FakeSmsSource(
        inbox: [
          _sent('TKA0000040', 50, 950, 0, sim: 'sim:7'),
          ..._twoLines(),
        ],
      );
      final c = await app(sms: phone);
      await scan(c, personal);
      var lines = await c.read(mpesaLinesProvider.future);
      expect(lines.lines, hasLength(3));
      expect(lines.split, isFalse);
      expect(lines.offersQuickSetup, isTrue);

      await c.read(mpesaLineRoutingProvider).keepTwoMostRecent();
      lines = await c.read(mpesaLinesProvider.future);
      expect(lines.split, isTrue);
      expect(lines.offersQuickSetup, isFalse);
      final seven = lines.lines.singleWhere((l) => l.sims.contains('sim:7'));
      expect(seven.tracked, isFalse);
      expect(lines.mainId, lines.line('1')!.sims.contains('sim:3') ? '1' : '2');
      // Its past record stays; new ones are skipped.
      expect((await byAccount(personal))[lineReference(seven.id)], {
        'TKA0000040',
      });
      phone.inbox.add(_sent('TKA0000041', 50, 900, 41, sim: 'sim:7'));
      await scan(c, personal);
      expect((await byAccount(personal))[lineReference(seven.id)], {
        'TKA0000040',
      });
    });

    test('the main line shows first in Balances, Money and On hand', () async {
      final c = await splitTwo(FakeSmsSource(inbox: _twoLines()));
      await c.read(mpesaLineRoutingProvider).setRole('2', LineRole.main);
      final sub = c.listen(balancesOverviewProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(mpesaLinesProvider.future);
      final overview = await c.read(balancesOverviewProvider.future);
      expect(
        [
          for (final a in overview.accounts)
            if (lineOfReference(a.account.reference) != null)
              a.account.reference,
        ],
        ['line:2', 'line:1'],
      );
      // On hand lists accounts in the same line order.
      final accounts = await personal.select(personal.accounts).get();
      final lines = await c.read(mpesaLinesProvider.future);
      final ordered = [...accounts]
        ..sort(byLineOrder(lines, [for (final a in accounts) a.id]));
      expect(ordered.first.reference, 'line:2');
    });

    test("a line's typed number reaches every space, and a send to it from "
        'the other line is a move between own accounts', () async {
      final c = await splitTwo(FakeSmsSource(inbox: _twoLines()));
      final one = (await lineAccount('1')).id;
      final two = (await lineAccount('2')).id;
      Future<int> add(int account, TransactionDirection d, String? phone) =>
          personal
              .into(personal.transactions)
              .insert(
                TransactionsCompanion.insert(
                  accountId: account,
                  amountMinor: 70000,
                  direction: d,
                  occurredAt: DateTime.utc(2026, 11, 20, 8),
                  source: TransactionSource.sms,
                  kind: Value(
                    d == TransactionDirection.outflow
                        ? TransactionKind.sent
                        : TransactionKind.received,
                  ),
                  counterpartyKind: Value(
                    phone == null ? null : PayeeIdentifierKind.phone,
                  ),
                  counterpartyValue: Value(phone),
                ),
              );
      final sent = await add(one, TransactionDirection.outflow, '0712***678');
      await add(two, TransactionDirection.inflow, null);

      await c.read(mpesaLineRoutingProvider).setNumber('2', '0712 345 678');
      expect(
        (await c.read(mpesaLinesProvider.future)).line('2')!.maskedNumber,
        '0712 ••• 678',
      );
      for (final db in [personal, shop]) {
        expect(await readLinePhones(db), {'2': '0712345678'});
      }
      final own = ownAccountsOf(
        await personal.select(personal.accounts).get(),
        linePhones: await readLinePhones(personal),
      );
      expect(own.phoneOf(two), '0712345678');
      final row = await (personal.select(
        personal.transactions,
      )..where((t) => t.id.equals(sent))).getSingle();
      expect(row.transferPairId, isNotNull);
    });

    test(
      'iPhone: a line told apart by balance alone can stop being tracked',
      () async {
        final queue = _ShortcutQueue(
          inbox: [
            for (final m in _twoLines())
              SmsMessage(
                sender: m.sender,
                body: m.body,
                receivedAt: m.receivedAt,
              ),
          ],
        );
        final c = await splitTwo(queue);
        await c
            .read(mpesaLineRoutingProvider)
            .untrack('2', deleteRecords: false);
        queue.inbox
          ..add(_sent('TKA0000050', 100, 24130, 50))
          ..add(_sent('TKA0000051', 100, 11750, 51));
        await scan(c, personal);
        final after = await byAccount(personal);
        expect(after['line:2'], {'TKA0000002', 'TKA0000004'});
        expect(after['line:1'], contains('TKA0000051'));
        expect(await personal.select(personal.reviewItems).get(), isEmpty);
      },
    );
  });

  test('the inbox is counted once, so two lines read as one are offered '
      'the split at once', () async {
    final c = await app(sms: FakeSmsSource(inbox: _twoLines()));
    await countLines(c.read(_refProvider), from: DateTime.utc(2026, 11));
    final lines = await c.read(mpesaLinesProvider.future);
    expect(lines.surveyed, isTrue);
    expect(lines.offersSplit, isTrue);
    expect(lines.line('1')!.messages, 3);
    expect(lines.line('2')!.messages, 2);
    // Nothing was stored: counting reads, it does not record.
    expect(await count(personal), 0);
  });
}

void _leakRepairByLine() {
  test('the repair of copies across spaces finds who reads a line by the '
      'line, so a line a business reads is never taken for a copy', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    Future<Account> mpesa(String? reference) async {
      final id = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'M-Pesa',
              type: AccountType.mpesa,
              openingDate: DateTime.utc(2026),
              institutionId: const Value(mpesaInstitutionId),
              reference: Value(reference),
            ),
          );
      return (db.select(
        db.accounts,
      )..where((a) => a.id.equals(id))).getSingle();
    }

    final readers = {
      mpesaInstitutionId: personalSpaceId,
      lineSelectionId('sim:3'): _shop.id,
    };
    expect(
      readerOfAccount(readers, await mpesa(lineReference('sim:3'))),
      _shop.id,
    );
    // A line no space has switched on, and the account from before lines
    // were told apart, are read where M-Pesa is.
    expect(
      readerOfAccount(readers, await mpesa(lineReference('sim:4'))),
      personalSpaceId,
    );
    expect(readerOfAccount(readers, await mpesa(null)), personalSpaceId);
  });
}

/// The container's own [Ref], for functions that take one.
final _refProvider = Provider<Ref>((ref) => ref);
