import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/categories_repository.dart';
import 'package:pesaclarity/src/data/repositories/lending_repository.dart';
import 'package:pesaclarity/src/data/repositories/payees_repository.dart';
import 'package:pesaclarity/src/data/repositories/purpose_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/income/money_purpose.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/payees/payee_identifier.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

void main() {
  late AppDatabase db;
  late DriftTransactionsRepository transactions;
  late DriftPayeesRepository payees;
  late DriftCategoriesRepository categories;
  late DriftPurposeRepository purpose;
  late int account;
  late int payee;
  final phone = PayeeIdentifier.phone('0700***001')!;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    transactions = DriftTransactionsRepository(db);
    payees = DriftPayeesRepository(db);
    categories = DriftCategoriesRepository(db);
    purpose = DriftPurposeRepository(db);
    account = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: DateTime.utc(2026),
          ),
        );
    payee = await payees.name(phone, displayName: 'Test Wanjiku');
  });

  tearDown(() => db.close());

  Future<int> received(int day, int amount) => transactions.add(
    TransactionsCompanion.insert(
      accountId: account,
      occurredAt: DateTime.utc(2026, 10, day, 9),
      amountMinor: amount,
      direction: TransactionDirection.inflow,
      kind: const Value(TransactionKind.received),
      source: TransactionSource.sms,
      payeeId: Value(payee),
      counterpartyKind: Value(phone.kind),
      counterpartyValue: Value(phone.value),
    ),
  );

  Future<int> idOf(String key) async => (await categories.byKey(key))!.id;

  Future<LedgerEntry> entryOf(int id) async =>
      (await transactions.ledgerEntries(
        from: DateTime.utc(2026, 10),
        to: DateTime.utc(2026, 11),
      )).singleWhere((e) => e.id == id);

  Future<Payee> payeeRow() =>
      (db.select(db.payees)..where((p) => p.id.equals(payee))).getSingle();

  test(
    'a different purpose from the payee\'s category starts asking',
    () async {
      await payees.update(
        payee,
        defaultCategoryId: Value(await idOf('loan_repayment')),
      );
      final first = await received(1, 300000);
      final support = await idOf('support_received');
      await categories.setOverride(first, support);
      await purpose.noteChoice(first, support);
      expect((await payeeRow()).askPurpose, isTrue);

      final next = await entryOf(await received(5, 200000));
      expect(next.needsPurpose, isTrue);
      expect(next.categoryId, isNull);
      // What was already answered keeps its answer.
      expect((await entryOf(first)).categoryId, support);
    },
  );

  test('the same purpose again does not ask', () async {
    final support = await idOf('support_received');
    for (final day in [1, 8]) {
      final id = await received(day, 300000);
      await categories.setOverride(id, support);
      await purpose.noteChoice(id, support);
    }
    expect((await payeeRow()).askPurpose, isFalse);
  });

  test('two different answers start asking', () async {
    final a = await received(1, 300000);
    await categories.setOverride(a, await idOf('support_received'));
    await purpose.noteChoice(a, await idOf('support_received'));
    final b = await received(8, 50000);
    await categories.setOverride(b, await idOf('gifts_received'));
    await purpose.noteChoice(b, await idOf('gifts_received'));
    expect((await payeeRow()).askPurpose, isTrue);
  });

  test('money out to them still takes their category', () async {
    await payees.update(
      payee,
      defaultCategoryId: Value(await idOf('family_support')),
    );
    await purpose.setAskPurpose(payee, ask: true);
    final sent = await transactions.add(
      TransactionsCompanion.insert(
        accountId: account,
        occurredAt: DateTime.utc(2026, 10, 3, 9),
        amountMinor: 100000,
        direction: TransactionDirection.outflow,
        kind: const Value(TransactionKind.sent),
        source: TransactionSource.sms,
        payeeId: Value(payee),
      ),
    );
    final entry = await entryOf(sent);
    expect(entry.needsPurpose, isFalse);
    expect(entry.categoryId, await idOf('family_support'));
  });

  test(
    'answering files it; always use sets the payee and stops asking',
    () async {
      await purpose.setAskPurpose(payee, ask: true);
      final a = await received(1, 300000);
      await purpose.answer(a, MoneyPurpose.familySupport);
      expect((await entryOf(a)).categoryId, await idOf('support_received'));
      expect((await payeeRow()).askPurpose, isTrue);

      final b = await received(8, 500000);
      await purpose.answer(b, MoneyPurpose.work, alwaysUse: true);
      final row = await payeeRow();
      expect(row.askPurpose, isFalse);
      expect(row.defaultCategoryId, await idOf('business_income'));
      expect((await entryOf(await received(15, 1000))).needsPurpose, isFalse);
    },
  );

  test('a loan to you adds them to Debts once', () async {
    final a = await received(1, 300000);
    await purpose.answer(a, MoneyPurpose.loanToYou);
    await purpose.answer(await received(9, 100000), MoneyPurpose.loanToYou);
    final debts = await db.select(db.debts).get();
    expect(debts, hasLength(1));
    expect(debts.single.lender, 'Test Wanjiku');
    expect(debts.single.type, DebtType.family);
    expect(debts.single.startingBalanceMinor, 300000);
    expect(debts.single.payeeId, payee);
    expect((await entryOf(a)).categoryType, CategoryType.debt);
  });

  test('paying you back lowers what they owe', () async {
    final lending = DriftLendingRepository(db);
    await lending.add(
      person: 'test wanjiku',
      amountMinor: 200000,
      lentOn: CalendarDate(2026, 9, 1),
    );
    await purpose.answer(await received(4, 500000), MoneyPurpose.payingBack);
    final loan = (await lending.lent()).single;
    expect(loan.payments.single.amountMinor, 200000);
    expect(loan.outstandingAt(CalendarDate(2026, 10, 5)), 0);
  });
}
