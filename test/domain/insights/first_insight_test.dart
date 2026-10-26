import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/insights/first_insight.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

const _spendKinds = [
  TransactionKind.sent,
  TransactionKind.paybill,
  TransactionKind.till,
  TransactionKind.withdrawal,
];

/// A synthetic 90-day ledger with its expected figures worked out as it is
/// built, independently of the ledger rules.
class _Synthetic {
  _Synthetic(this.start, {required int perDay, int seed = 7}) {
    final random = Random(seed);
    for (var day = 0; day < 90; day++) {
      final date = start.addDays(day);
      DateTime at(int hour, int minute) =>
          eat(date.year, date.month, date.day, hour, minute);

      if (date.day == 25) {
        final salary = kes(80000 + random.nextInt(20000));
        entries.add(
          inflow(
            at: at(8, 0),
            amount: salary,
            id: _id++,
            categoryType: CategoryType.income,
          ),
        );
        income += salary;
      }
      for (var i = 0; i < perDay; i++) {
        final amount = kes(50 + random.nextInt(3000));
        final fee = random.nextBool() ? kes(random.nextInt(40)) : 0;
        final leakType =
            LeakType.values[random.nextInt(LeakType.values.length)];
        entries.add(
          entry(
            at: at(9 + i % 12, i % 60),
            amount: amount,
            id: _id++,
            kind: _spendKinds[random.nextInt(_spendKinds.length)],
            categoryType: CategoryType.expense,
            payeeId: 1 + random.nextInt(50),
            leakType: leakType,
            fee: fee,
          ),
        );
        spending += amount + fee;
        if (leakType != LeakType.none) leakage += amount;
        leakage += fee;
      }
      // Fuliza on about one day in six, repaid two days later with a fee.
      if (day % 6 == 1 && day < 85) {
        final draw = kes(500 + random.nextInt(2000));
        final fee = kes(10 + random.nextInt(90));
        entries
          ..add(
            inflow(
              at: at(20, 0),
              amount: draw,
              id: _id++,
              kind: TransactionKind.fulizaDraw,
            ),
          )
          ..add(
            entry(
              at: eat(date.year, date.month, date.day + 2, 7),
              amount: draw + fee,
              id: _id++,
              kind: TransactionKind.fulizaRepayment,
            ),
          );
        fulizaFees += fee;
        spending += fee;
        leakage += fee;
        fulizaDays++;
      }
      // Own transfers count nowhere.
      entries.add(
        entry(
          at: at(21, 0),
          amount: kes(1000),
          id: _id++,
          kind: TransactionKind.roundUp,
        ),
      );
    }
    entries.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  }

  final CalendarDate start;
  final entries = <LedgerEntry>[];
  var _id = 1;
  var income = 0;
  var spending = 0;
  var leakage = 0;
  var fulizaFees = 0;
  var fulizaDays = 0;

  DateTime get from => start.startInstant;
  DateTime get to => start.addDays(90).startInstant;
}

void main() {
  test('adds up income, spending, leakages and Fuliza fees', () {
    final from = eat(2026, 8, 1, 0);
    final to = eat(2026, 10, 30, 0);
    final insight = FirstInsight.of(
      [
        inflow(
          at: eat(2026, 9, 25),
          amount: kes(90000),
          categoryType: CategoryType.income,
        ),
        entry(
          at: eat(2026, 9, 26),
          amount: kes(3000),
          categoryType: CategoryType.expense,
          payeeId: 2,
          leakType: LeakType.friends,
          fee: kes(30),
        ),
        entry(
          at: eat(2026, 9, 27),
          amount: kes(20000),
          categoryType: CategoryType.expense,
        ),
        inflow(
          at: eat(2026, 10, 1),
          amount: kes(1000),
          kind: TransactionKind.fulizaDraw,
        ),
        inflow(
          at: eat(2026, 10, 1, 18),
          amount: kes(500),
          kind: TransactionKind.fulizaDraw,
        ),
        entry(
          at: eat(2026, 10, 3),
          amount: kes(1580),
          kind: TransactionKind.fulizaRepayment,
        ),
        // Before the period.
        entry(at: eat(2026, 7, 30), amount: kes(999)),
      ],
      from: from,
      to: to,
    );
    expect(insight.transactionCount, 6);
    expect(insight.incomeMinor, kes(90000));
    expect(insight.spendingMinor, kes(3000 + 30 + 20000 + 80));
    expect(insight.leakageMinor, kes(3000 + 30 + 80));
    expect(insight.fulizaFeesMinor, kes(80));
    expect(insight.fulizaDays, 1);
    expect(insight.leakageShareBasisPoints, 345);
  });

  test('is zero for an empty ledger', () {
    final insight = FirstInsight.of(
      const [],
      from: eat(2026, 8, 1),
      to: eat(2026, 10, 30),
    );
    expect(insight.transactionCount, 0);
    expect(insight.leakageMinor, 0);
    expect(insight.leakageShareBasisPoints, isNull);
  });

  test('a 90-day ledger of a few thousand transactions adds up quickly', () {
    final data = _Synthetic(CalendarDate(2026, 7, 28), perDay: 40);
    expect(data.entries.length, greaterThan(3500));

    // Warm up once so the timing measures the work, not the first JIT pass.
    FirstInsight.of(data.entries, from: data.from, to: data.to);
    final watch = Stopwatch()..start();
    final insight = FirstInsight.of(data.entries, from: data.from, to: data.to);
    watch.stop();

    expect(insight.transactionCount, data.entries.length);
    expect(insight.incomeMinor, data.income);
    expect(insight.spendingMinor, data.spending);
    expect(insight.leakageMinor, data.leakage);
    expect(insight.fulizaFeesMinor, data.fulizaFees);
    expect(insight.fulizaDays, data.fulizaDays);
    // Typically a few milliseconds; the bound is loose so slow CI does not
    // flake, while still catching an accidental quadratic pass.
    expect(watch.elapsedMilliseconds, lessThan(1500));
  });
}
