// Money lent or borrowed between the person, friends and family, filed
// straight from a transaction ("I lent this", "Paid back a loan", "A loan
// to me", "Paying me back"): each is linked to its loan in Lent and
// borrowed, the journal posts it against what is owed, and it counts as
// neither spending nor income. Synthetic names and numbers only.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/categories_repository.dart';
import 'package:pesaclarity/src/data/repositories/debts_repository.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';
import 'package:pesaclarity/src/data/repositories/lending_repository.dart';
import 'package:pesaclarity/src/data/repositories/loan_links_repository.dart';
import 'package:pesaclarity/src/data/repositories/payees_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/budget/safe_to_spend.dart';
import 'package:pesaclarity/src/domain/categories/default_categories.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_role.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/lending/loan_link.dart';
import 'package:pesaclarity/src/domain/payees/payee_identifier.dart';
import 'package:pesaclarity/src/domain/plan/month_plan.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../domain/fixtures.dart';
import '../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late DriftTransactionsRepository transactions;
  late DriftLoanLinksRepository links;
  late DriftLendingRepository lending;
  late DriftCategoriesRepository categories;
  late JournalRepository journal;
  late int mpesa;
  late int grace;
  final phone = PayeeIdentifier.phone('0700 000 002')!;
  final from = eat(2026, 11, 1, 0);
  final to = eat(2026, 12, 1, 0);

  setUp(() async {
    db = openTestDatabase();
    transactions = DriftTransactionsRepository(db);
    links = DriftLoanLinksRepository(db);
    lending = DriftLendingRepository(db);
    categories = DriftCategoriesRepository(db);
    journal = JournalRepository(db, clock: () => to);
    mpesa = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingBalanceMinor: Value(kes(20000)),
            openingDate: eat(2026, 11, 1, 0),
          ),
        );
    grace = await DriftPayeesRepository(db)
        .name(phone, displayName: 'Test Grace');
  });

  Future<int> money(
    int day,
    int shillings, {
    required TransactionDirection direction,
  }) => transactions.add(
    TransactionsCompanion.insert(
      accountId: mpesa,
      occurredAt: eat(2026, 11, day, 9),
      amountMinor: kes(shillings),
      direction: direction,
      kind: Value(
        direction == TransactionDirection.outflow
            ? TransactionKind.sent
            : TransactionKind.received,
      ),
      source: TransactionSource.sms,
      payeeId: Value(grace),
      counterpartyKind: Value(phone.kind),
      counterpartyValue: Value(phone.value),
      counterpartyName: const Value('TEST GRACE'),
      receiptNo: Value('TLN${day}0$shillings'),
    ),
  );

  Future<int> sent(int day, int shillings) =>
      money(day, shillings, direction: TransactionDirection.outflow);
  Future<int> received(int day, int shillings) =>
      money(day, shillings, direction: TransactionDirection.inflow);

  Future<List<LedgerEntry>> entries() =>
      transactions.ledgerEntries(from: from, to: to);

  Future<LedgerEntry> entryOf(int id) async =>
      (await entries()).singleWhere((e) => e.id == id);

  Future<TransactionRecord> row(int id) =>
      (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();

  Future<int> owedToYou() async {
    await journal.sync();
    return (await journal.read()).balanceOf(
      BookAccount.owedToYou,
      currency: 'KES',
    );
  }

  Future<LedgerTotals> totals() async {
    await journal.sync();
    return LedgerTotals.of(
      await entries(),
      from: from,
      to: to,
      journal: await journal.read(),
    );
  }

  Future<int> lend(int id, {int shillings = 5000}) => links.lend(
    id,
    person: 'Test Grace',
    amountMinor: kes(shillings),
    lentOn: CalendarDate(2026, 11, 3),
  );

  group('I lent this', () {
    test('creates the loan, linked, and leaves it out of spending', () async {
      final id = await sent(3, 5000);
      final loanId = await lend(id);

      final loan = (await lending.lent()).single;
      expect(loan.id, loanId);
      expect(loan.person, 'Test Grace');
      expect(loan.amountMinor, kes(5000));
      expect(loan.lentOn, CalendarDate(2026, 11, 3));
      final record = await row(id);
      expect(record.lentLoanId, loanId);
      expect(
        record.categoryOverrideId,
        (await categories.byKey(moneyLentSeed.key))!.id,
      );

      final entry = await entryOf(id);
      expect(roleOf(entry), LedgerRole.lending);
      expect(isMoneyArrived(entry), isFalse);
      expect(dayToDaySpendOf(entry), 0);

      // The journal posts it against what Grace owes, off M-Pesa.
      expect(await owedToYou(), kes(5000));
      final books = await journal.read();
      expect(
        books.balanceOf(BookAccount.money(mpesa), currency: 'KES'),
        kes(15000),
      );
      final parts = books.partsOf(entry)!;
      expect(parts.spendingMinor, 0);
      expect(parts.incomeMinor, 0);

      final t = await totals();
      expect(t.spendingMinor, 0);
      expect(t.incomeMinor, 0);
      expect(t.moneyInMinor, 0);
      expect(t.debtRepaymentMinor, 0);

      // Plan's actuals leave it out, its category included.
      final category = (await categories.byKey(moneyLentSeed.key))!;
      final review = MonthReview.of(
        MonthPlan(
          month: YearMonth(2026, 11),
          lines: const [],
          categories: const {},
        ),
        await entries(),
        journal: books,
      );
      expect(
        review.categories.where((c) => c.categoryId == category.id),
        isEmpty,
      );
      expect(review.actualMinor, 0);
    });

    test('paying me back lowers it, and is not income', () async {
      final loanId = await lend(await sent(3, 5000));
      final back = await received(10, 2000);
      expect(await links.paidBack(back), isTrue);

      expect((await row(back)).lentLoanId, loanId);
      final loan = (await lending.lent()).single;
      expect(loan.payments.single.amountMinor, kes(2000));
      expect(loan.status(CalendarDate(2026, 11, 20)).remainingMinor, kes(3000));
      expect(await owedToYou(), kes(3000));
      final t = await totals();
      expect(t.incomeMinor, 0);
      expect(t.moneyInMinor, 0);
      expect(roleOf(await entryOf(back)), LedgerRole.lending);
    });

    test('unlinking reverses it: the loan and its link go', () async {
      final lent = await sent(3, 5000);
      await lend(lent);
      final back = await received(10, 2000);
      await links.paidBack(back);

      // Choosing another category takes it out of Lent and borrowed.
      final gifts = (await categories.byKey('friends_social'))!.id;
      await categories.setOverride(lent, gifts);

      expect(await lending.lent(), isEmpty);
      final record = await row(lent);
      expect(record.lentLoanId, isNull);
      expect(record.categoryOverrideId, gifts);
      // What paid it back is left with no loan and no category.
      final repaid = await row(back);
      expect(repaid.lentLoanId, isNull);
      expect(repaid.categoryOverrideId, isNull);
      expect(await owedToYou(), 0);
      expect((await totals()).spendingMinor, kes(5000));
    });

    test('unlinking money in only takes off its payment', () async {
      await lend(await sent(3, 5000));
      final back = await received(10, 2000);
      await links.paidBack(back);
      await categories.setOverride(back, null);

      final loan = (await lending.lent()).single;
      expect(loan.payments, isEmpty);
      expect((await row(back)).lentLoanId, isNull);
      expect(await owedToYou(), kes(5000));
    });

    test('removing the loan in Lent and borrowed unlinks its money', () async {
      final lent = await sent(3, 5000);
      final loanId = await lend(lent);
      await lending.remove(loanId);
      final record = await row(lent);
      expect(record.lentLoanId, isNull);
      expect(record.categoryOverrideId, isNull);
      expect(await owedToYou(), 0);
    });
  });

  group('money borrowed', () {
    test('a loan to me adds it to Debts; unlinking removes it', () async {
      final id = await received(2, 8000);
      await links.borrow(id);
      final debt = await db.select(db.debts).getSingle();
      expect(debt.lender, 'Test Grace');
      expect(debt.isFormal, isFalse);
      expect(debt.startingBalanceMinor, kes(8000));
      expect((await row(id)).debtId, debt.id);
      expect(await links.linkOf(id), (
        link: LoanLink.borrowed,
        person: 'Test Grace',
      ));
      final t = await totals();
      expect(t.incomeMinor, 0);
      expect(t.moneyInMinor, 0);
      expect(t.borrowingMinor, kes(8000));

      await categories.setOverride(id, null);
      expect(await db.select(db.debts).get(), isEmpty);
      expect((await row(id)).debtId, isNull);
    });

    test(
      'paid back a loan lowers the oldest money borrowed from them',
      () async {
        await links.borrow(await received(1, 3000));
        await links.borrow(await received(2, 4000));
        final debts = await (db.select(
          db.debts,
        )..orderBy([(d) => OrderingTerm.asc(d.id)])).get();

        final out = await sent(12, 1000);
        expect(await links.payBack(out), isTrue);
        expect((await row(out)).debtId, debts.first.id);
        expect(await links.linkOf(out), (
          link: LoanLink.repaidBorrowed,
          person: 'Test Grace',
        ));
        final owed = {
          for (final d in await DriftDebtsRepository(
            db,
          ).debts(today: CalendarDate(2026, 11, 20)))
            d.id: d.balanceMinor,
        };
        expect(owed, {debts.first.id: kes(2000), debts.last.id: kes(4000)});
        final t = await totals();
        expect(t.spendingMinor, 0);
        expect(t.debtRepaymentMinor, kes(1000));

        // Unlinking leaves the debt as it was.
        await categories.setOverride(out, null);
        expect((await row(out)).debtId, isNull);
        expect(await db.select(db.debts).get(), hasLength(2));
      },
    );

    test(
      'Plan leaves paying a friend back out; a bank loan still counts',
      () async {
        await links.borrow(await received(1, 3000));
        final family = await sent(12, 1000);
        expect(await links.payBack(family), isTrue);
        final loanCategory = (await categories.byKey(loanCategoryKey))!.id;
        final bank = await DriftDebtsRepository(db).add(
          DebtsCompanion.insert(
            lender: 'Test Bank',
            type: DebtType.bankLoan,
            startingBalanceMinor: kes(50000),
          ),
        );
        final bankPayment = await sent(14, 2500);
        await (db.update(
          db.transactions,
        )..where((t) => t.id.equals(bankPayment))).write(
          TransactionsCompanion(
            debtId: Value(bank),
            categoryOverrideId: Value(loanCategory),
          ),
        );

        expect((await entryOf(family)).repaysFamilyLoan, isTrue);
        expect((await entryOf(bankPayment)).repaysFamilyLoan, isFalse);
        await journal.sync();
        final review = MonthReview.of(
          MonthPlan(
            month: YearMonth(2026, 11),
            lines: const [],
            categories: const {},
          ),
          await entries(),
          journal: await journal.read(),
        );
        expect(
          review.categories
              .singleWhere((c) => c.categoryId == loanCategory)
              .actualMinor,
          kes(2500),
        );
        expect(review.actualMinor, kes(2500));
        // Neither is day-to-day spending, so safe to spend is untouched.
        expect(dayToDaySpendOf(await entryOf(family)), 0);
        expect(dayToDaySpendOf(await entryOf(bankPayment)), 0);
      },
    );

    test(
      'with nothing borrowed from them it is a repayment on its own',
      () async {
        final out = await sent(12, 1000);
        expect(await links.payBack(out), isFalse);
        expect((await row(out)).debtId, isNull);
        expect(
          (await row(out)).categoryOverrideId,
          (await categories.byKey(loanCategoryKey))!.id,
        );
      },
    );
  });

  test('Activity reads every link with the loan\'s name', () async {
    final lent = await sent(3, 5000);
    await lend(lent);
    final borrowed = await received(4, 2000);
    await links.borrow(borrowed);
    expect(await links.watchLinks().first, {
      lent: (link: LoanLink.lent, person: 'Test Grace'),
      borrowed: (link: LoanLink.borrowed, person: 'Test Grace'),
    });
  });
}
