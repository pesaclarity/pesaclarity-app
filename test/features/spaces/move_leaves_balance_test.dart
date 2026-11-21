// A payment moved to another space leaves the balance its message reported
// behind (decision 0027, alternative D and the owner's decision 13), so a
// business on a line Personal shares stops showing the owner's whole
// wallet. Personal's side stays as it was. Made-up data only, in the shapes
// of the M-Pesa pack's fixtures.
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/balances_repository.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';
import 'package:pesaclarity/src/data/repositories/message_reads_repository.dart';
import 'package:pesaclarity/src/data/repositories/review_inbox_repository.dart';
import 'package:pesaclarity/src/data/repositories/space_move_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/spaces/line_routing.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/spaces/application/business_setup_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/routing_providers.dart';
import 'package:ujumbe/ujumbe.dart' show SmsMessage;

import '../../helpers/spaces_harness.dart';
import '../../helpers/test_app.dart';

const _shop = 'shop1';

int _kes(int shillings) => shillings * 100;

String _sh(int minor) => (minor / 100).toStringAsFixed(2);

final _mpesa = institutionCatalogue.singleWhere((i) => i.id == 'mpesa');

/// Reads M-Pesa [body], received at [at], into [db].
Future<void> _read(AppDatabase db, String body, DateTime at) => SmsIngestor(
  accounts: DriftAccountsRepository(db),
  transactions: DriftTransactionsRepository(db),
  reviewInbox: DriftReviewInboxRepository(db),
  reads: MessageReadsRepository(db),
  parse: (packs, messages) async => parseAll(packs, messages),
).ingest([SmsMessage(sender: 'MPESA', body: body, receivedAt: at)], [_mpesa]);

/// M-Pesa's message for money received, printing the wallet's balance.
Future<void> _received(
  AppDatabase db,
  String receipt,
  String amount,
  String who,
  String balance,
  DateTime at,
) => _read(
  db,
  '$receipt Confirmed.You have received Ksh$amount from $who on '
  '${at.day}/${at.month}/26 at 10:00 AM  New M-PESA balance is '
  'Ksh$balance.',
  at,
);

/// M-Pesa's message for a payment to a till, printing the wallet's balance.
Future<void> _paid(
  AppDatabase db,
  String receipt,
  String amount,
  String who,
  String balance,
  DateTime at,
) => _read(
  db,
  '$receipt Confirmed. Ksh$amount paid to $who. on ${at.day}/${at.month}/26 '
  'at 10:00 AM.New M-PESA balance is Ksh$balance. Transaction cost, '
  'Ksh0.00. Amount you can transact within the day is 499,000.00.',
  at,
);

/// What [db]'s journal says its accounts are worth (wallets less Fuliza
/// owed), as Home and Balances read it.
Future<int> _held(AppDatabase db) async {
  final accounts = await DriftAccountsRepository(db).openings();
  final journal = await JournalRepository(db).read();
  return journal.totalHeldAt(
    accounts,
    at: DateTime.utc(2100),
    where: (_) => true,
  );
}

/// Fuliza owed across [db]'s accounts, as its journal has it.
Future<int> _fulizaOwed(AppDatabase db) async {
  final accounts = await DriftAccountsRepository(db).openings();
  final journal = await JournalRepository(db).read();
  return accounts.fold<int>(
    0,
    (sum, a) => sum + journal.fulizaOwedAt(a, at: DateTime.utc(2100)),
  );
}

/// The router for an M-Pesa line Personal shares with the shop.
SharedLineRouter _router(
  AppDatabase personal,
  AppDatabase business,
  DateTime Function() now,
) {
  var rules = const RoutingRules(sharedLines: {'mpesa': _shop});
  return SharedLineRouter(
    personal: personal,
    moveFromPersonal: DriftSpaceMoveRepository(
      personal,
      (_) async => (business, false),
    ),
    rules: () async => rules,
    remember: (key, spaceId) async => rules = rules.withPerson(key, spaceId),
    now: now,
  );
}

/// Answers the question about [name]'s payment "Business sale" (or
/// "Business cost"), without "Always do this".
Future<void> _forTheBusiness(SharedLineRouter router, String name) async {
  final question = (await router.pending(_shop))
      .singleWhere((q) => q.name == name);
  await router.answer(
    question,
    businessId: _shop,
    forBusiness: true,
    always: false,
  );
}

Future<AppDatabase> _businessDatabase() async {
  final db = openTestDatabase();
  await db.becomeSpace(SpaceKind.business);
  return db;
}

void main() {
  // Audit A, F1: "Business sale" for KES 650 gave the business the owner's
  // whole M-Pesa balance.
  group('a sale answered for the business', () {
    final now = DateTime.utc(2026, 11, 20, 9);
    late AppDatabase personal;
    late AppDatabase business;
    late SharedLineRouter router;

    setUp(() async {
      personal = openTestDatabase();
      business = await _businessDatabase();
      router = _router(personal, business, () => now);
      await _paid(
        personal,
        'TJA0000101',
        '500.00',
        'EXAMPLE GROCERS',
        '37,819.00',
        DateTime.utc(2026, 11, 17, 6),
      );
      // A customer pays the shop KES 650 on the shared line.
      await _received(
        personal,
        'TJA0000102',
        '650.00',
        'GRACE WAMBUI 0700***002',
        '38,469.00',
        DateTime.utc(2026, 11, 18, 7),
      );
      await _read(
        personal,
        'TJA0000103 Confirmed. Ksh1,000.00 sent to JANE DOE 0700***001 on '
        '19/11/26 at 9:15 AM. New M-PESA balance is Ksh37,454.00. '
        'Transaction cost, Ksh15.00. Amount you can transact within the '
        'day is 498,500.00.',
        DateTime.utc(2026, 11, 19, 6, 15),
      );
      expect(await _held(personal), _kes(37454));
    });

    test('gives the business KES 650, not the owner\'s whole M-Pesa '
        'balance', () async {
      await _forTheBusiness(router, 'GRACE WAMBUI');

      final moved = await business.select(business.transactions).getSingle();
      expect(moved.amountMinor, _kes(650));
      expect(moved.balanceAfterMinor, isNull);
      expect(moved.claimedBalanceMinor, isNull);
      final held = await _held(business);
      expect(
        held,
        _kes(650),
        reason:
            'the business was given one KES 650.00 sale; it shows KES '
            '${_sh(held)}',
      );
    });

    test('leaves Personal as it was: it still shows what the wallet '
        'holds', () async {
      await _forTheBusiness(router, 'GRACE WAMBUI');

      expect(await _held(personal), _kes(37454));
    });
  });

  // Audit B, B2: with the wallet's balance carried in, the business's
  // M-Pesa could not be put right.
  group('the business M-Pesa can be put right', () {
    late int suggested;
    late bool saidFromMessage;
    late int afterStart;
    late int afterNextSale;
    late int afterSetBalance;
    late int afterThirdSale;

    setUp(() async {
      final personal = openTestDatabase();
      final business = await _businessDatabase();
      var now = DateTime.utc(2026, 11, 2, 12);
      final router = _router(personal, business, () => now);
      final c = twoSpaces(
        personal: personal,
        other: business,
        clock: () => now,
        active: _shop,
      );

      // 2 November: a customer pays KES 650; the owner's wallet then holds
      // KES 38,469. "Business sale".
      await _received(
        personal,
        'TJB0000101',
        '650.00',
        'GRACE WAMBUI 0700***002',
        '38,469.00',
        DateTime.utc(2026, 11, 2, 7),
      );
      await _forTheBusiness(router, 'GRACE WAMBUI');

      // 3 November: Start your records. The business has KES 3,000 of the
      // wallet; the owner types that over what the app offers.
      now = DateTime.utc(2026, 11, 3, 12);
      final line = (await c.read(openingLinesProvider.future)).single;
      suggested = line.suggestedMinor;
      saidFromMessage = line.fromMessage;
      await c
          .read(businessSetupProvider.notifier)
          .startRecords(cashMinor: 0, accounts: {line.accountId: _kes(3000)});
      afterStart = await _held(business);

      // 4 November: the owner has spent of their own; a customer pays
      // KES 1,200 and the wallet holds KES 30,000. "Business sale".
      now = DateTime.utc(2026, 11, 4, 12);
      await _received(
        personal,
        'TJB0000102',
        '1,200.00',
        'PETER OTIENO 0700***003',
        '30,000.00',
        DateTime.utc(2026, 11, 4, 7),
      );
      await _forTheBusiness(router, 'PETER OTIENO');
      afterNextSale = await _held(business);

      // Balances > M-Pesa > Set balance: KES 4,000.
      await DriftBalancesRepository(business).setBalance(
        line.accountId,
        statedMinor: _kes(4000),
        differenceMinor: _kes(4000) - afterNextSale,
        at: now,
        currency: 'KES',
      );
      afterSetBalance = await _held(business);

      // 5 November: a customer pays KES 500 and the wallet holds
      // KES 20,500. "Business sale".
      now = DateTime.utc(2026, 11, 5, 12);
      await _received(
        personal,
        'TJB0000103',
        '500.00',
        'MARY ACHIENG 0700***004',
        '20,500.00',
        DateTime.utc(2026, 11, 5, 7),
      );
      await _forTheBusiness(router, 'MARY ACHIENG');
      afterThirdSale = await _held(business);
    });

    test('Start your records offers what the business was given, not the '
        'owner\'s wallet', () {
      expect(suggested, _kes(650));
      expect(saidFromMessage, isFalse);
    });

    test('the opening balance the owner typed is kept when the next sale '
        'is answered', () {
      expect(afterStart, _kes(3000));
      expect(
        afterNextSale,
        _kes(4200),
        reason: 'KES 3,000.00 typed, then one KES 1,200.00 sale',
      );
    });

    test('a Set balance correction is kept when the next sale is answered', () {
      expect(afterSetBalance, _kes(4000));
      expect(
        afterThirdSale,
        _kes(4500),
        reason: 'set to KES 4,000.00, then one KES 500.00 sale',
      );
    });
  });

  test('the business owes Fuliza only when Fuliza was used', () async {
    final personal = openTestDatabase();
    final business = await _businessDatabase();
    final now = DateTime.utc(2026, 11, 20, 9);
    final router = _router(personal, business, () => now);
    // A customer pays KES 650 (the wallet then holds KES 700), a friend
    // sends the owner KES 300 (KES 1,000), and the owner pays a supplier
    // KES 1,000 from the line, which empties it. No Fuliza anywhere.
    await _received(
      personal,
      'TJB0000201',
      '650.00',
      'GRACE WAMBUI 0700***002',
      '700.00',
      DateTime.utc(2026, 11, 18, 7),
    );
    await _received(
      personal,
      'TJB0000202',
      '300.00',
      'JOHN KAMAU 0700***005',
      '1,000.00',
      DateTime.utc(2026, 11, 18, 8),
    );
    await _paid(
      personal,
      'TJB0000203',
      '1,000.00',
      'EXAMPLE WHOLESALERS',
      '0.00',
      DateTime.utc(2026, 11, 18, 9),
    );
    expect(await _fulizaOwed(personal), 0);

    await _forTheBusiness(router, 'GRACE WAMBUI');
    await _forTheBusiness(router, 'EXAMPLE WHOLESALERS');

    expect(await _fulizaOwed(business), 0);
    // Until the full model, the business's M-Pesa is what it was given
    // less what it paid: the owner's own KES 350 went into the payment.
    expect(await _held(business), _kes(650) - _kes(1000));
  });

  // Rows moved before this change still carry the wallet's balance. They
  // are left as they are (the full model's repair needs that balance); a
  // Set balance now holds, because nothing moved since carries one.
  test('a Set balance holds over a payment moved before the change', () async {
    final personal = openTestDatabase();
    final business = await _businessDatabase();
    final now = DateTime.utc(2026, 11, 10, 12);
    final router = _router(personal, business, () => now);
    final account = await business
        .into(business.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: DateTime.utc(2026, 11),
            institutionId: const Value('mpesa'),
          ),
        );
    // A sale moved by an earlier version, with the owner's wallet on it.
    await business
        .into(business.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: account,
            occurredAt: DateTime.utc(2026, 11, 2, 7),
            amountMinor: _kes(650),
            direction: TransactionDirection.inflow,
            kind: const Value(TransactionKind.received),
            source: TransactionSource.sms,
            counterpartyName: const Value('GRACE WAMBUI'),
            receiptNo: const Value('TJB0000401'),
            dedupeKey: const Value('TJB0000401|65000|old'),
            balanceAfterMinor: Value(_kes(38469)),
          ),
        );
    expect(await _held(business), _kes(38469));

    await DriftBalancesRepository(business).setBalance(
      account,
      statedMinor: _kes(2000),
      differenceMinor: _kes(2000) - _kes(38469),
      at: DateTime.utc(2026, 11, 9, 12),
      currency: 'KES',
    );
    await _received(
      personal,
      'TJB0000402',
      '500.00',
      'MARY ACHIENG 0700***004',
      '20,500.00',
      DateTime.utc(2026, 11, 10, 7),
    );
    await _forTheBusiness(router, 'MARY ACHIENG');

    expect(await _held(business), _kes(2500));
  });
}
