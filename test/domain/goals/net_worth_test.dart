import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/goals/net_worth.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';

import '../fixtures.dart';

void main() {
  final mpesa = AccountOpening(
    id: 1,
    type: AccountType.mpesa,
    openingBalanceMinor: kes(10000),
    openingDate: eat(2026, 9, 1),
  );
  final mmf = AccountOpening(
    id: 2,
    type: AccountType.moneyMarket,
    openingBalanceMinor: kes(50000),
    openingDate: eat(2026, 9, 1),
  );
  final dollars = AccountOpening(
    id: 3,
    type: AccountType.bank,
    currency: 'USD',
    openingBalanceMinor: 100000,
    openingDate: eat(2026, 9, 1),
  );

  test('assets less debts, and the change since the month began', () {
    final entries = [
      inflow(at: eat(2026, 9, 25), amount: kes(80000)),
      // October: salary in, a debt repayment out.
      inflow(at: eat(2026, 10, 25), amount: kes(80000)),
      entry(at: eat(2026, 10, 26, 9), amount: kes(20000)),
    ];
    final worth = NetWorth.at(
      now: eat(2026, 10, 26),
      accounts: [mpesa, mmf, dollars],
      entries: entries,
      debtsOwedMinor: kes(100000),
      debtsRepaidThisMonthMinor: kes(20000),
      lentOutstandingMinor: kes(3000),
      lentOutstandingAtMonthStartMinor: kes(5000),
    );
    // 10,000 + 80,000 + 80,000 - 20,000 + 50,000 + 3,000 lent.
    expect(worth.assetsMinor, kes(203000));
    expect(worth.debtsMinor, kes(100000));
    expect(worth.valueMinor, kes(103000));
    // At 1 Oct: 140,000 in accounts + 5,000 lent - 120,000 owed.
    expect(worth.startOfMonthMinor, kes(25000));
    expect(worth.changeThisMonthMinor, kes(78000));
  });

  test('entries after now are left out', () {
    final worth = NetWorth.at(
      now: eat(2026, 10, 26),
      accounts: [mpesa],
      entries: [inflow(at: eat(2026, 10, 27), amount: kes(1000))],
      debtsOwedMinor: 0,
      debtsRepaidThisMonthMinor: 0,
      lentOutstandingMinor: 0,
      lentOutstandingAtMonthStartMinor: 0,
    );
    expect(worth.valueMinor, kes(10000));
    expect(worth.changeThisMonthMinor, 0);
  });
}
