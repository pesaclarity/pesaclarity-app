import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/books/cash_book.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/activity_lines.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

void main() {
  const cash = 101;
  const mpesa = 102;
  const bank = 103;
  const savings = 104;
  final opened = eat(2026, 11, 1, 0);
  final accounts = [
    AccountOpening(
      id: cash,
      type: AccountType.cash,
      openingBalanceMinor: kes(1000),
      openingDate: opened,
    ),
    AccountOpening(
      id: mpesa,
      type: AccountType.mpesa,
      openingBalanceMinor: kes(5000),
      openingDate: opened,
    ),
    AccountOpening(
      id: bank,
      type: AccountType.bank,
      openingBalanceMinor: 0,
      openingDate: opened,
    ),
    AccountOpening(
      id: savings,
      type: AccountType.moneyMarket,
      openingBalanceMinor: 0,
      openingDate: opened,
    ),
  ];
  final to = CalendarDate(2026, 11, 6).startInstant;

  CashBook book(List<LedgerEntry> entries, {CalendarDate? from}) => CashBook.of(
    entries,
    accounts: accounts,
    to: to,
    from: from ?? CalendarDate(2026, 11, 1),
  );

  test('each column holds its accounts, savings left out', () {
    final b = book([
      inflow(at: eat(2026, 11, 4, 9), amount: kes(350), accountId: cash),
      entry(at: eat(2026, 11, 4, 10), amount: kes(200), accountId: mpesa),
    ]);
    expect(b.balances, {
      CashColumn.cash: kes(1350),
      CashColumn.mpesa: kes(4800),
      CashColumn.bank: 0,
    });
    expect(b.balances.keys.toList(), CashColumn.values);
  });

  test('a column without an account is left out', () {
    final b = CashBook.of(
      const [],
      accounts: [accounts.first],
      to: to,
      from: CalendarDate(2026, 11, 1),
    );
    expect(b.balances.keys, [CashColumn.cash]);
    expect(b.days, isEmpty);
  });

  test('days run newest first with money in and out, costs included', () {
    final b = book([
      inflow(at: eat(2026, 11, 4, 9), amount: kes(350), accountId: cash),
      entry(
        at: eat(2026, 11, 4, 10),
        amount: kes(2400),
        accountId: mpesa,
        fee: kes(30),
      ),
      inflow(at: eat(2026, 11, 5, 8), amount: kes(1750), accountId: mpesa),
    ]);
    expect(b.days.map((d) => d.date), [
      CalendarDate(2026, 11, 5),
      CalendarDate(2026, 11, 4),
    ]);
    expect(b.days[0].inMinor, kes(1750));
    expect(b.days[0].outMinor, 0);
    expect(b.days[1].inMinor, kes(350));
    expect(b.days[1].outMinor, kes(2430));
  });

  test('a move inside the book shows once and is neither in nor out', () {
    final b = book([
      entry(
        id: 10,
        at: eat(2026, 11, 4, 9),
        amount: kes(3000),
        accountId: mpesa,
        kind: TransactionKind.sent,
        transferPairId: 11,
        fee: kes(10),
      ),
      inflow(
        id: 11,
        at: eat(2026, 11, 4, 9, 1),
        amount: kes(3000),
        accountId: bank,
      ).copyWith(transferPairId: 10),
    ]);
    final day = b.days.single;
    expect(day.lines.single, isA<OwnTransferLine>());
    expect(day.inMinor, 0);
    expect(day.outMinor, kes(10));
  });

  test('money moved to savings leaves the book', () {
    final b = book([
      entry(
        id: 20,
        at: eat(2026, 11, 4, 9),
        amount: kes(1000),
        accountId: mpesa,
        transferPairId: 21,
      ),
      inflow(
        id: 21,
        at: eat(2026, 11, 4, 9),
        amount: kes(1000),
        accountId: savings,
      ).copyWith(transferPairId: 20),
    ]);
    final day = b.days.single;
    expect(day.outMinor, kes(1000));
    expect(b.balances[CashColumn.mpesa], kes(4000));
  });

  test('days start at from, while balances count everything', () {
    final b = book([
      inflow(at: eat(2026, 11, 2, 9), amount: kes(500), accountId: cash),
      inflow(at: eat(2026, 11, 5, 9), amount: kes(100), accountId: cash),
    ], from: CalendarDate(2026, 11, 4));
    expect(b.days.single.date, CalendarDate(2026, 11, 5));
    expect(b.balances[CashColumn.cash], kes(1600));
  });

  test('cashColumnOf keeps savings out', () {
    expect(cashColumnOf(AccountType.cash), CashColumn.cash);
    expect(cashColumnOf(AccountType.mpesa), CashColumn.mpesa);
    expect(cashColumnOf(AccountType.bank), CashColumn.bank);
    expect(cashColumnOf(AccountType.sacco), isNull);
    expect(cashColumnOf(AccountType.moneyMarket), isNull);
  });
}
