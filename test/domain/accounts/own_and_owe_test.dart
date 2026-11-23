// "What you own and owe" with SACCOs. Made-up SACCOs and amounts.
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/accounts/own_and_owe.dart';

void main() {
  const sacco = SaccoHolding(
    name: 'Test SACCO',
    currency: 'KES',
    savedMinor: 10400000,
    sharesMinor: 2000000,
    loanName: 'Test SACCO loan',
    loanOwedMinor: 14350000,
  );

  test('a SACCO adds its deposits and shares to Saved', () {
    expect(sacco.depositsMinor, 8400000);
    final totals = OwnAndOwe.of(
      currency: 'KES',
      walletMinor: 500000,
      savedMinor: 100000,
      saccos: const [sacco],
    );
    expect(totals.savedMinor, 10500000);
    expect(totals.ownMinor, 11000000);
  });

  test('its loan goes under Owed with Fuliza', () {
    final totals = OwnAndOwe.of(
      currency: 'KES',
      walletMinor: 500000,
      owedMinor: 20000,
      saccos: const [sacco],
    );
    expect(totals.owedMinor, 14370000);
    expect(totals.afterDebtsMinor, 10900000 - 14370000);
  });

  test('counts with no M-Pesa family at all', () {
    final totals = OwnAndOwe.of(currency: 'KES', saccos: const [sacco]);
    expect(totals.walletMinor, 0);
    expect(totals.savedMinor, 10400000);
    expect(totals.owedMinor, 14350000);
  });

  test('a SACCO with no loan owes nothing; another currency is left out', () {
    const noLoan = SaccoHolding(
      name: 'Test Savings SACCO',
      currency: 'KES',
      savedMinor: 300000,
    );
    const dollars = SaccoHolding(
      name: 'Test USD SACCO',
      currency: 'USD',
      savedMinor: 50000,
      loanName: 'Test USD loan',
      loanOwedMinor: 10000,
    );
    expect(noLoan.hasLoan, isFalse);
    final totals = OwnAndOwe.of(
      currency: 'KES',
      saccos: const [noLoan, dollars],
    );
    expect(totals.savedMinor, 300000);
    expect(totals.owedMinor, 0);
  });
}
