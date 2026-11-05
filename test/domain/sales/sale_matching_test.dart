import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/sales/sale_matching.dart';

import '../fixtures.dart';

void main() {
  const mpesa = 7;
  const bank = 8;
  const cash = 9;
  const sales = 50;
  final types = {
    mpesa: AccountType.mpesa,
    bank: AccountType.bank,
    cash: AccountType.cash,
  };
  final soldAt = eat(2026, 11, 5, 14, 40);

  WaitingPayment waiting(
    int id, {
    int amount = 18000,
    SalePaymentMethod method = SalePaymentMethod.mpesa,
    DateTime? at,
  }) => WaitingPayment(
    paymentId: id,
    saleId: id,
    method: method,
    amountMinor: amount,
    currency: 'KES',
    soldAt: at ?? soldAt,
  );

  LedgerEntry paid(
    int id, {
    int amount = 18000,
    int accountId = mpesa,
    DateTime? at,
    int? categoryId,
    bool auto = false,
    int? pair,
  }) => LedgerEntry(
    id: id,
    accountId: accountId,
    occurredAt: at ?? soldAt.add(const Duration(minutes: 1)),
    amountMinor: amount,
    direction: TransactionDirection.inflow,
    kind: TransactionKind.received,
    categoryId: categoryId,
    categoryIsAuto: auto,
    transferPairId: pair,
  );

  Map<int, int> match(
    List<WaitingPayment> w,
    List<LedgerEntry> e, {
    Set<int> linked = const {},
  }) => matchWaitingPayments(
    w,
    e,
    accountTypes: types,
    linked: linked,
    salesCategoryId: sales,
  );

  test('a payment of the same amount on M-Pesa matches', () {
    expect(match([waiting(1)], [paid(100)]), {1: 100});
  });

  test('a payment that came just before the sale matches too', () {
    expect(
      match(
        [waiting(1)],
        [paid(100, at: soldAt.subtract(const Duration(minutes: 5)))],
      ),
      {1: 100},
    );
  });

  test('another amount, account type or a time too far away does not', () {
    expect(match([waiting(1)], [paid(100, amount: 20000)]), isEmpty);
    expect(match([waiting(1)], [paid(100, accountId: bank)]), isEmpty);
    expect(
      match([waiting(1)], [paid(100, at: soldAt.add(saleMatchWindow * 2))]),
      isEmpty,
    );
    expect(
      match([waiting(1, method: SalePaymentMethod.bank)], [paid(100)]),
      isEmpty,
    );
  });

  test('a bank part matches a bank payment', () {
    expect(
      match(
        [waiting(1, method: SalePaymentMethod.bank)],
        [paid(100, accountId: bank)],
      ),
      {1: 100},
    );
  });

  test('linked payments, transfers and other categories are left alone', () {
    expect(match([waiting(1)], [paid(100)], linked: {100}), isEmpty);
    expect(match([waiting(1)], [paid(100, pair: 5)]), isEmpty);
    expect(match([waiting(1)], [paid(100, categoryId: 3)]), isEmpty);
    // A guess from the categoriser, or Sales already, is fine.
    expect(match([waiting(1)], [paid(100, categoryId: 3, auto: true)]), {
      1: 100,
    });
    expect(match([waiting(1)], [paid(100, categoryId: sales)]), {1: 100});
  });

  test('each payment pays one sale, the oldest sale first, closest first', () {
    final early = soldAt.subtract(const Duration(minutes: 30));
    expect(
      match(
        [waiting(2), waiting(1, at: early)],
        [
          paid(100, at: soldAt.add(const Duration(minutes: 2))),
          paid(101, at: early.add(const Duration(minutes: 1))),
        ],
      ),
      {1: 101, 2: 100},
    );
    expect(match([waiting(1), waiting(2)], [paid(100)]), {1: 100});
  });

  test('cash and credit never wait for a message', () {
    expect(accountTypesFor(SalePaymentMethod.cash), isEmpty);
    expect(accountTypesFor(SalePaymentMethod.credit), isEmpty);
  });
}
