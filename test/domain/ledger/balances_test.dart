import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';

import '../fixtures.dart';

void main() {
  final mpesa = AccountOpening(
    id: 1,
    type: AccountType.mpesa,
    openingBalanceMinor: kes(1000),
    openingDate: eat(2026, 10, 1, 0),
  );
  final sacco = AccountOpening(
    id: 2,
    type: AccountType.sacco,
    openingBalanceMinor: kes(50000),
    openingDate: eat(2026, 10, 1, 0),
  );

  final entries = [
    inflow(at: eat(2026, 9, 30), amount: kes(999)),
    inflow(at: eat(2026, 10, 2), amount: kes(5000)),
    entry(at: eat(2026, 10, 3), amount: kes(2000), fee: kes(30)),
    entry(at: eat(2026, 10, 3), amount: kes(1000), accountId: 2),
    entry(at: eat(2026, 10, 3), amount: 100, currency: 'USD'),
    entry(at: eat(2026, 10, 9), amount: kes(500)),
  ];

  test('adds flows since opening, less fees, up to the instant', () {
    expect(
      balanceAt(mpesa, entries, at: eat(2026, 10, 5)),
      kes(1000 + 5000 - 2000 - 30),
    );
    expect(balanceAt(mpesa, entries, at: eat(2026, 10, 1)), kes(1000));
  });

  test('totals only the accounts asked for', () {
    final at = eat(2026, 10, 5);
    expect(sacco.isSavings, isTrue);
    expect(mpesa.isSavings, isFalse);
    expect(
      totalBalanceAt(
        [mpesa, sacco],
        entries,
        at: at,
        where: (a) => a.isSavings,
      ),
      kes(49000),
    );
    expect(
      totalBalanceAt([mpesa, sacco], entries, at: at, where: (_) => true),
      kes(3970 + 49000),
    );
  });
}
