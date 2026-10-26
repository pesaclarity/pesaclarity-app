import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/tags/tag_totals.dart';

import '../fixtures.dart';

const roadtrip = 1;
const wedding = 2;
const fuel = 10;

LedgerEntry tagged(LedgerEntry e, Set<int> tags) => LedgerEntry(
  id: e.id,
  accountId: e.accountId,
  occurredAt: e.occurredAt,
  amountMinor: e.amountMinor,
  direction: e.direction,
  kind: e.kind,
  currency: e.currency,
  feeMinor: e.feeMinor,
  payeeId: e.payeeId,
  categoryId: e.categoryId,
  categoryType: e.categoryType,
  tagIds: tags,
);

void main() {
  final from = eat(2026, 10, 1, 0);
  final to = eat(2026, 11, 1, 0);

  final entries = [
    tagged(
      entry(
        at: eat(2026, 10, 3),
        amount: kes(4000),
        categoryId: fuel,
        categoryType: CategoryType.expense,
        fee: kes(10),
      ),
      {roadtrip},
    ),
    tagged(entry(at: eat(2026, 10, 3, 14), amount: kes(1500)), {
      roadtrip,
      wedding,
    }),
    tagged(
      inflow(
        at: eat(2026, 10, 4),
        amount: kes(500),
        payeeId: 1,
        categoryId: fuel,
        categoryType: CategoryType.expense,
      ),
      {roadtrip},
    ),
    tagged(
      inflow(
        at: eat(2026, 10, 6),
        amount: kes(3000),
        payeeId: 2,
        categoryType: CategoryType.income,
        categoryId: 30,
      ),
      {wedding},
    ),
    tagged(entry(at: eat(2026, 11, 2), amount: kes(999)), {roadtrip}),
    entry(at: eat(2026, 10, 5), amount: kes(700)),
  ];

  test('cleanTagName strips the hash and tidies', () {
    expect(cleanTagName('#RoadTrip'), 'roadtrip');
    expect(cleanTagName('  ## Wedding  2026 '), 'wedding 2026');
    expect(cleanTagName('#'), isNull);
    expect(cleanTagName('x' * 41), isNull);
  });

  test('withTag filters by tag', () {
    expect(withTag(entries, wedding), hasLength(2));
    expect(withTag(entries, 99), isEmpty);
  });

  test('spending by category keeps uncategorised under null', () {
    final byCategory = spendingByCategory(entries, from: from, to: to);
    expect(byCategory, {fuel: kes(3500), null: kes(2200)});
    expect(
      byCategory.values.reduce((a, b) => a + b),
      LedgerTotals.of(entries, from: from, to: to).spendingMinor,
    );
  });

  test('totals per tag, uncategorised included', () {
    final totals = tagTotals(entries, from: from, to: to);
    expect(totals.keys, unorderedEquals([roadtrip, wedding]));

    final trip = totals[roadtrip]!;
    expect(trip.entryCount, 3);
    expect(trip.totals.spendingMinor, kes(5000));
    expect(trip.totals.feesMinor, kes(10));
    expect(trip.spendingByCategory, {fuel: kes(3500), null: kes(1500)});

    final wed = totals[wedding]!;
    expect(wed.totals.spendingMinor, kes(1500));
    expect(wed.totals.incomeMinor, kes(3000));
    expect(wed.spendingByCategory, {null: kes(1500)});
  });
}
