import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/income/week_by_week.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

void main() {
  // Wednesday; the week started on Monday 2 November.
  final today = CalendarDate(2026, 11, 4);

  /// Eight usual weeks: 4,000 in on Tuesday, 3,000 out on Wednesday.
  List<LedgerEntry> usualWeeks() => [
    for (var w = 1; w <= usualWeeksCount; w++) ...[
      inflow(
        at: eat(2026, 11, 3 - 7 * w, 10),
        amount: kes(4000),
        payeeId: 1,
        categoryType: CategoryType.income,
      ),
      entry(
        at: eat(2026, 11, 4 - 7 * w, 10),
        amount: kes(3000),
        categoryType: CategoryType.expense,
      ),
    ],
  ];

  List<LedgerEntry> thisWeek({required int inKes, required int outKes}) => [
    inflow(
      at: eat(2026, 11, 2, 9),
      amount: kes(inKes),
      payeeId: 1,
      categoryType: CategoryType.income,
    ),
    entry(
      at: eat(2026, 11, 3, 9),
      amount: kes(outKes),
      categoryType: CategoryType.expense,
    ),
  ];

  test('weeks start on Monday', () {
    expect(weekStartOf(today), CalendarDate(2026, 11, 2));
    expect(weekStartOf(CalendarDate(2026, 11, 8)), CalendarDate(2026, 11, 2));
    expect(weekStartOf(CalendarDate(2026, 11, 9)), CalendarDate(2026, 11, 9));
  });

  test('a usual week comes from the weeks before this one', () {
    final plan = WeekByWeek.of([
      ...usualWeeks(),
      ...thisWeek(inKes: 7000, outKes: 1000),
    ], today: today);
    expect(plan.usualInMinor, kes(4000));
    expect(plan.usualOutMinor, kes(3000));
    expect(plan.thisWeek.inMinor, kes(7000));
    expect(plan.thisWeek.outMinor, kes(1000));
    expect(plan.shown, hasLength(weeksShown));
    expect(plan.targetMinor, kes(3000));
  });

  test('a good week suggests half the extra, once, up to the target', () {
    final history = [...usualWeeks(), ...thisWeek(inKes: 7000, outKes: 1000)];
    final plan = WeekByWeek.of(history, today: today);
    expect(plan.extraMinor, kes(3000));
    expect(plan.suggestAddMinor, kes(1500));
    expect(plan.suggestTakeMinor, 0);

    final added = Kibubu([KibubuMove(on: today, amountMinor: kes(1500))]);
    expect(
      WeekByWeek.of(history, today: today, kibubu: added).suggestAddMinor,
      0,
    );

    final nearlyFull = Kibubu([
      KibubuMove(on: CalendarDate(2026, 10, 20), amountMinor: kes(2550)),
    ]);
    // Room for 450, rounded down to whole hundreds.
    expect(
      WeekByWeek.of(history, today: today, kibubu: nearlyFull).suggestAddMinor,
      kes(400),
    );
  });

  test('a lean week can take what it falls short, up to the kibubu', () {
    final history = [...usualWeeks(), ...thisWeek(inKes: 1000, outKes: 2500)];
    final pot = Kibubu([
      KibubuMove(on: CalendarDate(2026, 10, 20), amountMinor: kes(5000)),
    ]);
    final plan = WeekByWeek.of(history, today: today, kibubu: pot);
    expect(plan.suggestAddMinor, 0);
    expect(plan.suggestTakeMinor, kes(2000));

    final small = Kibubu([
      KibubuMove(on: CalendarDate(2026, 10, 20), amountMinor: kes(800)),
    ]);
    expect(
      WeekByWeek.of(history, today: today, kibubu: small).suggestTakeMinor,
      kes(800),
    );
  });

  test('the kibubu keeps its moves and never goes below zero', () {
    final pot = const Kibubu()
        .withMove(KibubuMove(on: today, amountMinor: kes(1000)))
        .withMove(KibubuMove(on: today, amountMinor: -kes(1500)));
    expect(pot.balanceMinor, 0);
    final back = Kibubu.fromJson(pot.toJson());
    expect(back.moves, hasLength(2));
    expect(back.moves.last.amountMinor, -kes(1500));
    expect(Kibubu.fromJson(null).balanceMinor, 0);
  });
}
