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

  group('balances the institution reported', () {
    // Opening balance unknown (0), as for an account found by reading SMS.
    final found = AccountOpening(
      id: 7,
      type: AccountType.mpesa,
      openingBalanceMinor: 0,
      openingDate: eat(2026, 10, 1, 0),
    );
    final reported = [
      entry(
        accountId: 7,
        at: eat(2026, 10, 2),
        amount: kes(500),
        fee: kes(15),
        balanceAfter: kes(9485),
      ),
      entry(accountId: 7, at: eat(2026, 10, 4), amount: kes(200)),
      entry(
        accountId: 7,
        at: eat(2026, 10, 6),
        amount: kes(300),
        balanceAfter: kes(8985),
      ),
      entry(accountId: 7, at: eat(2026, 10, 8), amount: kes(100)),
    ];

    test('the latest reported balance wins, plus what came after', () {
      expect(balanceAt(found, reported, at: eat(2026, 10, 5)), kes(9285));
      expect(balanceAt(found, reported, at: eat(2026, 10, 9)), kes(8885));
    });

    test('before the first report, it walks back from it', () {
      expect(balanceAt(found, reported, at: eat(2026, 10, 1, 6)), kes(10000));
    });

    test('a report taken after an unreported entry still anchors it', () {
      expect(balanceAt(found, reported, at: eat(2026, 10, 7)), kes(8985));
    });
  });
}
