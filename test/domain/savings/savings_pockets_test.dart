import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/savings/savings_pockets.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

PocketFlow _in(DateTime at, int shillings) => PocketFlow(at, kes(shillings));

PocketFlow _out(DateTime at, int shillings) => PocketFlow(at, -kes(shillings));

PocketReading _typed(DateTime at, int shillings, {bool interest = true}) =>
    PocketReading(
      at: at,
      balanceMinor: kes(shillings),
      gapIsInterest: interest,
    );

void main() {
  group('a pocket with no typed balance', () {
    test('holds what was paid in less what was taken out', () {
      final pocket = settlePocket(
        flows: [
          _in(eat(2026, 9, 1), 2000),
          _out(eat(2026, 10, 10), 500),
          _in(eat(2026, 11, 1), 1000),
        ],
        readings: const [],
      );
      expect(pocket.balanceMinor, kes(2500));
      expect(pocket.paidInMinor, kes(3000));
      expect(pocket.takenOutMinor, kes(500));
      expect(pocket.interestMinor, 0);
      expect(pocket.outcomes, isEmpty);
      expect(pocket.lastSetAt, isNull);
    });

    test('with nothing in it holds nothing', () {
      expect(settlePocket(flows: const [], readings: const []).balanceMinor, 0);
      expect(PocketSettlement.empty.balanceMinor, 0);
    });
  });

  group('interest and corrections', () {
    final flows = [
      _in(eat(2026, 8, 5), 2000),
      _in(eat(2026, 9, 5), 2000),
      _out(eat(2026, 10, 10), 1000),
    ];

    test('a balance above the records shows interest', () {
      final pocket = settlePocket(
        flows: flows,
        readings: [_typed(eat(2026, 11, 21), 3085)],
      );
      final [first] = pocket.outcomes;
      expect(first.expectedMinor, kes(3000));
      expect(first.gapMinor, kes(85));
      expect(first.interestMinor, kes(85));
      expect(first.correctionMinor, 0);
      expect(pocket.interestMinor, kes(85));
      expect(pocket.balanceMinor, kes(3085));
      expect(pocket.lastSetAt, eat(2026, 11, 21));
    });

    test('later money in and out adds to the last typed balance', () {
      final pocket = settlePocket(
        flows: [
          ...flows,
          _in(eat(2026, 11, 25), 500),
          _out(eat(2026, 11, 28), 200),
        ],
        readings: [_typed(eat(2026, 11, 21), 3085)],
      );
      expect(pocket.balanceMinor, kes(3385));
      expect(pocket.interestMinor, kes(85));
    });

    test('each later balance shows the interest since the one before', () {
      final pocket = settlePocket(
        flows: [...flows, _in(eat(2026, 12, 1), 1000)],
        readings: [
          _typed(eat(2026, 11, 21), 3085),
          _typed(eat(2026, 12, 21), 4120),
        ],
      );
      final [first, second] = pocket.outcomes;
      expect(first.interestMinor, kes(85));
      expect(second.isFirst, isFalse);
      expect(second.expectedMinor, kes(4085));
      expect(second.interestMinor, kes(35));
      expect(pocket.interestMinor, kes(120));
      expect(pocket.balanceMinor, kes(4120));
    });

    test('a balance below the records is a correction, never interest', () {
      final pocket = settlePocket(
        flows: flows,
        readings: [_typed(eat(2026, 11, 21), 2900)],
      );
      final [only] = pocket.outcomes;
      expect(only.interestMinor, 0);
      expect(only.correctionMinor, -kes(100));
      expect(only.wasThereBeforeMinor, 0);
      expect(only.otherChangeMinor, -kes(100));
      expect(pocket.otherChangesMinor, -kes(100));
      expect(pocket.balanceMinor, kes(2900));
    });

    test('a later gap the person says is not interest is another change', () {
      final pocket = settlePocket(
        flows: flows,
        readings: [
          _typed(eat(2026, 11, 21), 3085),
          _typed(eat(2026, 12, 21), 5085, interest: false),
        ],
      );
      final second = pocket.outcomes.last;
      expect(second.interestMinor, 0);
      expect(second.correctionMinor, kes(2000));
      expect(second.wasThereBeforeMinor, 0);
      expect(second.otherChangeMinor, kes(2000));
      expect(pocket.interestMinor, kes(85));
      expect(pocket.balanceMinor, kes(5085));
    });

    test('a balance typed the second money moved counts that money', () {
      final at = eat(2026, 11, 21, 9, 41);
      final pocket = settlePocket(
        flows: [_in(eat(2026, 10, 1), 1000), _in(at, 50)],
        readings: [_typed(at, 1050)],
      );
      expect(pocket.outcomes.single.gapMinor, 0);
      expect(pocket.balanceMinor, kes(1050));
    });

    test('the lines always add up to the balance', () {
      final pocket = settlePocket(
        flows: [
          _in(eat(2026, 6, 1), 700),
          _in(eat(2026, 9, 5), 2000),
          _out(eat(2026, 10, 10), 300),
          _in(eat(2026, 12, 2), 150),
        ],
        readings: [
          _typed(eat(2026, 7, 1), 6000),
          _typed(eat(2026, 11, 21), 7800),
          _typed(eat(2026, 12, 1), 7700),
        ],
      );
      expect(
        pocket.paidInMinor -
            pocket.takenOutMinor +
            pocket.interestMinor +
            pocket.wasThereBeforeMinor +
            pocket.otherChangesMinor,
        pocket.balanceMinor,
      );
      expect(pocket.wasThereBeforeMinor, kes(5300));
      expect(pocket.interestMinor, kes(100));
      expect(pocket.otherChangesMinor, -kes(100));
    });
  });

  group('the first typed balance', () {
    test('a small gap is interest: up to 2% of what was paid in a month', () {
      // Paid in over three and a half months: four months' allowance.
      final first = eat(2026, 8, 5);
      final at = eat(2026, 11, 21);
      bool interest(int gap) => setupGapIsInterest(
        gapMinor: gap,
        netPaidInMinor: kes(3000),
        firstPaymentAt: first,
        at: at,
      );
      expect(interest(kes(85)), isTrue);
      expect(interest(kes(240)), isTrue);
      expect(interest(kes(240) + 1), isFalse);
      expect(interest(kes(1700)), isFalse);
    });

    test('part of a month counts as a month', () {
      bool interest(DateTime at, int gap) => setupGapIsInterest(
        gapMinor: gap,
        netPaidInMinor: kes(1000),
        firstPaymentAt: eat(2026, 11, 1),
        at: at,
      );
      // The day it was paid in: one month's allowance, 20.
      expect(interest(eat(2026, 11, 1), kes(20)), isTrue);
      expect(interest(eat(2026, 11, 1), kes(21)), isFalse);
      expect(interest(eat(2026, 11, 30), kes(21)), isFalse);
      // Thirty days on: two months' allowance, 40.
      expect(interest(eat(2026, 12, 1), kes(40)), isTrue);
      expect(interest(eat(2026, 12, 1), kes(41)), isFalse);
    });

    test('nothing is interest with nothing paid in, or no gap', () {
      expect(
        setupGapIsInterest(
          gapMinor: kes(10),
          netPaidInMinor: 0,
          firstPaymentAt: eat(2026, 1, 1),
          at: eat(2026, 11, 21),
        ),
        isFalse,
      );
      expect(
        setupGapIsInterest(
          gapMinor: kes(10),
          netPaidInMinor: kes(5000),
          firstPaymentAt: null,
          at: eat(2026, 11, 21),
        ),
        isFalse,
      );
      expect(
        setupGapIsInterest(
          gapMinor: 0,
          netPaidInMinor: kes(5000),
          firstPaymentAt: eat(2026, 1, 1),
          at: eat(2026, 11, 21),
        ),
        isFalse,
      );
      expect(
        setupGapIsInterest(
          gapMinor: kes(10),
          netPaidInMinor: -kes(500),
          firstPaymentAt: eat(2026, 1, 1),
          at: eat(2026, 11, 21),
        ),
        isFalse,
      );
    });

    test('a large gap was there before, and is never interest', () {
      // Only the last payment was found; the pocket already held 4,650.
      final pocket = settlePocket(
        flows: [_in(eat(2026, 11, 21, 9), 50)],
        readings: [_typed(eat(2026, 11, 21, 10), 4700)],
      );
      final [only] = pocket.outcomes;
      expect(only.isFirst, isTrue);
      expect(only.interestMinor, 0);
      expect(only.correctionMinor, kes(4650));
      expect(only.wasThereBeforeMinor, kes(4650));
      expect(only.otherChangeMinor, 0);
      expect(pocket.wasThereBeforeMinor, kes(4650));
      expect(pocket.balanceMinor, kes(4700));
    });

    test('a balance typed before any payment was there before', () {
      final pocket = settlePocket(
        flows: [_in(eat(2026, 12, 1), 500)],
        readings: [_typed(eat(2026, 11, 21), 4700)],
      );
      expect(pocket.wasThereBeforeMinor, kes(4700));
      expect(pocket.interestMinor, 0);
      expect(pocket.balanceMinor, kes(5200));
    });

    test('the person can say a small first gap is not interest', () {
      final pocket = settlePocket(
        flows: [_in(eat(2026, 8, 5), 3000)],
        readings: [_typed(eat(2026, 11, 21), 3085, interest: false)],
      );
      expect(pocket.interestMinor, 0);
      expect(pocket.wasThereBeforeMinor, kes(85));
    });

    test('only the first balance is held to the rule', () {
      final pocket = settlePocket(
        flows: [_in(eat(2026, 11, 21, 9), 50)],
        readings: [
          _typed(eat(2026, 11, 21, 10), 4700),
          _typed(eat(2026, 12, 21), 4760),
        ],
      );
      expect(pocket.wasThereBeforeMinor, kes(4650));
      expect(pocket.interestMinor, kes(60));
    });
  });

  group('an older payment that turns up later', () {
    final typed = [_typed(eat(2026, 11, 21), 3085)];

    test('shrinks the interest of the balance that already held it', () {
      final before = settlePocket(
        flows: [_in(eat(2026, 9, 5), 2000), _in(eat(2026, 10, 5), 1000)],
        readings: typed,
      );
      expect(before.interestMinor, kes(85));

      final after = settlePocket(
        flows: [
          _in(eat(2026, 7, 1), 60),
          _in(eat(2026, 9, 5), 2000),
          _in(eat(2026, 10, 5), 1000),
        ],
        readings: typed,
      );
      expect(after.interestMinor, kes(25));
      expect(after.paidInMinor, kes(3060));
      // What the pocket holds is still what was typed.
      expect(after.balanceMinor, kes(3085));
    });

    test('turns money that was there before into money paid in', () {
      // Three months of messages: the gap is too large to be interest.
      final before = settlePocket(
        flows: [_in(eat(2026, 9, 5), 1000)],
        readings: typed,
      );
      expect(before.wasThereBeforeMinor, kes(2085));
      expect(before.interestMinor, 0);

      // A year of messages: what is left of the gap is interest after all.
      final after = settlePocket(
        flows: [
          _in(eat(2026, 2, 5), 1000),
          _in(eat(2026, 5, 5), 1000),
          _in(eat(2026, 9, 5), 1000),
        ],
        readings: typed,
      );
      expect(after.wasThereBeforeMinor, 0);
      expect(after.interestMinor, kes(85));
      expect(after.balanceMinor, kes(3085));
    });

    test('leaves balances typed before it alone', () {
      final pocket = settlePocket(
        flows: [
          _in(eat(2026, 9, 5), 3000),
          // Found later, dated between the two balances.
          _in(eat(2026, 12, 1), 400),
        ],
        readings: [
          _typed(eat(2026, 11, 21), 3085),
          _typed(eat(2026, 12, 21), 3520),
        ],
      );
      final [first, second] = pocket.outcomes;
      expect(first.interestMinor, kes(85));
      expect(second.interestMinor, kes(35));
    });
  });

  group('an account of several pockets', () {
    test('adds up what the balances typed at one time showed', () {
      final at = eat(2026, 11, 21);
      final settled = settleAccount(
        flows: {
          1: [_in(eat(2026, 8, 5), 3000), _in(eat(2026, 11, 21, 9), 50)],
          2: [_in(eat(2026, 11, 2), 500)],
          3: [_in(eat(2026, 9, 1), 900)],
        },
        readings: {
          1: [_typed(at, 3130)],
          2: [_typed(at, 1500)],
          3: [_typed(eat(2026, 11, 30), 850)],
        },
      );
      expect(settled.pockets[1]!.interestMinor, kes(80));
      expect(settled.pockets[2]!.wasThereBeforeMinor, kes(1000));
      expect(settled.pockets[3]!.otherChangesMinor, -kes(50));

      final [first, second] = settled.updates;
      expect(first.at, at);
      expect(first.pocketIds, [1, 2]);
      expect(first.balanceMinor, kes(4630));
      expect(first.interestMinor, kes(80));
      expect(first.wasThereBeforeMinor, kes(1000));
      expect(first.otherChangesMinor, 0);
      expect(first.correctionMinor, kes(1000));
      expect(first.changeMinor, kes(1080));
      expect(second.pocketIds, [3]);
      expect(second.interestMinor, 0);
      expect(second.correctionMinor, -kes(50));
    });

    test('a pocket with flows and no typed balance has no update', () {
      final settled = settleAccount(
        flows: {
          1: [_in(eat(2026, 8, 5), 3000)],
        },
        readings: const {},
      );
      expect(settled.updates, isEmpty);
      expect(settled.pockets[1]!.balanceMinor, kes(3000));
    });
  });

  group('money taken out', () {
    final december15 = CalendarDate(2026, 12, 15);
    const open = (id: 2, lockedUntil: null);
    final locked = (id: 1, lockedUntil: december15);

    test('comes from the only pocket, locked or not', () {
      expect(pocketForMoneyBack([locked], CalendarDate(2026, 11, 10)), 1);
      expect(pocketForMoneyBack([open], CalendarDate(2026, 11, 10)), 2);
    });

    test('comes from the only pocket open that day', () {
      expect(pocketForMoneyBack([locked, open], CalendarDate(2026, 11, 10)), 2);
      expect(pocketForMoneyBack([open, locked], CalendarDate(2026, 12, 14)), 2);
    });

    test('is in no pocket when more than one was open', () {
      // A pocket locked until a day is open from that day.
      expect(pocketForMoneyBack([locked, open], december15), isNull);
      expect(
        pocketForMoneyBack([locked, open], CalendarDate(2027, 1, 5)),
        isNull,
      );
      expect(
        pocketForMoneyBack([
          open,
          (id: 3, lockedUntil: null),
        ], CalendarDate(2026, 11, 10)),
        isNull,
      );
    });

    test('is in no pocket when every pocket was locked, or there is none', () {
      expect(
        pocketForMoneyBack([
          locked,
          (id: 3, lockedUntil: CalendarDate(2027, 1, 1)),
        ], CalendarDate(2026, 11, 10)),
        isNull,
      );
      expect(pocketForMoneyBack(const [], CalendarDate(2026, 11, 10)), isNull);
    });
  });
}
