import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_role.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/spaces/space_summary.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../domain/fixtures.dart';

/// A business's summary rows add up with its In and Out. Made-up data.
void main() {
  final today = CalendarDate(2026, 11, 20);
  const categories = <int, SummaryCategory>{
    1: (key: 'sales', name: 'Sales', type: CategoryType.income),
    2: (key: 'stock', name: 'Stock', type: CategoryType.expense),
  };
  final history = [
    inflow(
      at: eat(2026, 11, 3),
      amount: kes(9000),
      payeeId: 1,
      categoryId: 1,
      categoryType: CategoryType.income,
    ),
    entry(
      at: eat(2026, 11, 4),
      amount: kes(4000),
      categoryId: 2,
      categoryType: CategoryType.expense,
      fee: kes(15),
    ),
    // The supplier gave KES 1,000 back.
    inflow(
      at: eat(2026, 11, 5),
      amount: kes(1000),
      kind: TransactionKind.reversal,
      categoryId: 2,
      categoryType: CategoryType.expense,
    ),
    // Stock paid from a USD account: not in shillings, so not in the
    // shilling totals or rows.
    entry(
      at: eat(2026, 11, 6),
      amount: 2000,
      currency: 'USD',
      categoryId: 2,
      categoryType: CategoryType.expense,
    ),
  ];

  test('rows count as the totals do: refunds off, one currency', () {
    final summary = SpaceSummary.of(
      SpaceKind.business,
      history,
      today: today,
      categories: categories,
      balanceMinor: 0,
    );
    expect(summary.inMinor, kes(9000));
    expect(summary.outMinor, kes(3000) + kes(15));
    final rows = {for (final r in summary.rows) r.name: r.amountMinor};
    expect(rows, {'Sales': kes(9000), 'Stock': kes(3000)});
    final totals = LedgerTotals.of(
      history,
      from: today.yearMonth.firstDay.startInstant,
      to: today.addDays(1).startInstant,
    );
    expect(rows['Stock'], totals.spendingMinor);
    expect(
      history
          .where((e) => e.currency == 'KES')
          .map(spendingOf)
          .fold(0, (a, b) => a + b),
      totals.spendingMinor,
    );
  });
}
