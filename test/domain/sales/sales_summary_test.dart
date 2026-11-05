import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/books/books.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/sales/sales_summary.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

void main() {
  const cash = 11;
  const mpesa = 12;
  const sales = 50;
  const otherIncome = 51;
  final opened = eat(2026, 10, 1, 0);
  final accounts = [
    AccountOpening(
      id: cash,
      type: AccountType.cash,
      openingBalanceMinor: 0,
      openingDate: opened,
    ),
    AccountOpening(
      id: mpesa,
      type: AccountType.mpesa,
      openingBalanceMinor: 0,
      openingDate: opened,
    ),
  ];
  final types = {cash: AccountType.cash, mpesa: AccountType.mpesa};
  const categories = <int, BookCategory>{
    sales: (key: 'sales', type: CategoryType.income),
    otherIncome: (key: 'other_business_income', type: CategoryType.income),
  };
  final today = CalendarDate(2026, 11, 5);

  Books books(
    List<LedgerEntry> history, {
    List<CreditSale> credits = const [],
  }) => Books.of(
    history,
    accounts: accounts,
    categories: categories,
    credits: credits,
  );

  SalesDay day(Books b, [CalendarDate? date]) => salesOn(
    b,
    date ?? today,
    salesCategoryId: sales,
    accountTypes: types,
    currency: 'KES',
  );

  test('sales by how people paid, credit included', () {
    final b = books(
      [
        inflow(
          at: eat(2026, 11, 5, 9),
          amount: kes(800),
          accountId: cash,
          categoryId: sales,
          categoryType: CategoryType.income,
        ),
        inflow(
          at: eat(2026, 11, 5, 11),
          amount: kes(2900),
          accountId: mpesa,
          categoryId: sales,
          categoryType: CategoryType.income,
        ),
        // Other income is not a sale, and yesterday is not today.
        inflow(
          at: eat(2026, 11, 5),
          amount: kes(100),
          accountId: cash,
          categoryId: otherIncome,
          categoryType: CategoryType.income,
        ),
        inflow(
          at: eat(2026, 11, 4),
          amount: kes(500),
          accountId: cash,
          categoryId: sales,
          categoryType: CategoryType.income,
        ),
      ],
      credits: [
        CreditSale(
          paymentId: 1,
          at: eat(2026, 11, 5, 15),
          amountMinor: kes(1150),
          currency: 'KES',
          salesCategoryId: sales,
        ),
      ],
    );
    final d = day(b);
    expect(d.byWay, {
      SalePaymentMethod.cash: kes(800),
      SalePaymentMethod.mpesa: kes(2900),
      SalePaymentMethod.credit: kes(1150),
    });
    expect(d.totalMinor, kes(4850));
    expect(b.unbalanced, isEmpty);
    expect(b.balanceOf(BookAccount.owedToYou, currency: 'KES'), kes(1150));
  });

  test('a usual day is the average of earlier same weekdays with sales', () {
    LedgerEntry sale(int daysBack, int amount) => inflow(
      at: eat(2026, 11, 5 - daysBack, 10),
      amount: kes(amount),
      accountId: cash,
      categoryId: sales,
      categoryType: CategoryType.income,
    );
    final b = books([sale(7, 4000), sale(14, 5000), sale(21, 1)]);
    // 4,000, 5,000 and 1 average to 3,000.33.
    expect(
      usualSalesFor(
        b,
        today,
        salesCategoryId: sales,
        accountTypes: types,
        currency: 'KES',
      ),
      300033,
    );
    expect(
      usualSalesFor(
        books([sale(7, 4000)]),
        today,
        salesCategoryId: sales,
        accountTypes: types,
        currency: 'KES',
      ),
      isNull,
    );
  });
}
