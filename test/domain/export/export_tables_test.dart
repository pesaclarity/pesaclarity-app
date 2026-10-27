import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/money.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/export/export_tables.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/tags/tag_totals.dart';

ExportTransaction _tx({
  int id = 1,
  TransactionDirection direction = TransactionDirection.outflow,
  String? payee,
  String? category,
  List<String> tags = const [],
  LeakType leak = LeakType.none,
}) => ExportTransaction(
  id: id,
  occurredAt: DateTime.utc(2026, 10, 3, 6),
  accountName: 'M-Pesa',
  amountMinor: 30000,
  direction: direction,
  kind: TransactionKind.sent,
  source: TransactionSource.sms,
  feeMinor: 700,
  payeeName: payee,
  counterpartyValue: '0700***000',
  categoryName: category,
  leakType: leak,
  tags: tags,
  receiptNo: 'TJ3ABC123',
);

void main() {
  group('transactions sheet', () {
    test('includes tags, splits in and out, and names Uncategorised', () {
      final table = transactionsTable([
        _tx(
          payee: 'John',
          category: 'Friends and social',
          tags: ['reimbursable', 'roadtrip'],
          leak: LeakType.friends,
        ),
        _tx(id: 2, direction: TransactionDirection.inflow),
      ]);
      Object? cell(int row, String column) =>
          table.rows[row][table.columns.indexOf(column)];

      expect(cell(0, 'Payee'), 'John');
      expect(cell(0, 'Category'), 'Friends and social');
      expect(cell(0, 'Tags'), '#reimbursable #roadtrip');
      expect(cell(0, 'Money out'), Money(30000));
      expect(cell(0, 'Money in'), isNull);
      expect(cell(0, 'Fee'), Money(700));
      expect(cell(0, 'Leak type'), 'Friends');
      expect(cell(0, 'Type'), 'Sent');

      expect(cell(1, 'Payee'), '0700***000');
      expect(cell(1, 'Category'), 'Uncategorised');
      expect(cell(1, 'Money in'), Money(30000));
      expect(cell(1, 'Tags'), '');
    });
  });

  test('category spending keeps Uncategorised and adds up', () {
    final table = categorySpendingTable(
      {1: 50000, null: 20000, 2: 70000},
      {1: 'Groceries and household', 2: 'Rent and housing'},
    );
    expect(table.rows.map((r) => r[0]), [
      'Rent and housing',
      'Groceries and household',
      'Uncategorised',
      'Total',
    ]);
    expect(table.rows.last[1], Money(140000));
  });

  test('tag sheets show totals and category split per tag', () {
    const summary = TagSummary(
      tagId: 7,
      entryCount: 3,
      totals: LedgerTotals(spendingMinor: 90000, feesMinor: 1500),
      spendingByCategory: {5: 60000, null: 30000},
    );
    final totals = tagTotalsTable({7: summary}, {7: 'roadtrip'});
    expect(totals.rows.single, [
      '#roadtrip',
      3,
      Money(90000),
      Money(0),
      Money(1500),
    ]);
    final split = tagCategoryTable({7: summary}, {7: 'roadtrip'}, {5: 'Fuel'});
    expect(split.rows, [
      ['#roadtrip', 'Fuel', Money(60000)],
      ['#roadtrip', 'Uncategorised', Money(30000)],
    ]);
  });
}
