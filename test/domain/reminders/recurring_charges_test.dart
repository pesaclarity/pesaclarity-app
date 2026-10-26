import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/reminders/recurring_charges.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

void main() {
  final today = CalendarDate(2026, 10, 26);

  test('expects a monthly charge on the same day next month', () {
    final charges = detectRecurringCharges([
      entry(at: eat(2026, 9, 3), amount: kes(1100), payeeId: 7),
      entry(at: eat(2026, 10, 3), amount: kes(1100), payeeId: 7),
    ], today: today);
    expect(charges, hasLength(1));
    expect(charges.single.payeeId, 7);
    expect(charges.single.amountMinor, kes(1100));
    expect(charges.single.nextDate, CalendarDate(2026, 11, 3));
  });

  test('clamps to the end of a shorter month', () {
    final charges = detectRecurringCharges([
      entry(at: eat(2026, 9, 30), amount: kes(500), payeeId: 7),
      entry(at: eat(2026, 10, 31), amount: kes(500), payeeId: 7),
    ], today: today);
    expect(charges.single.nextDate, CalendarDate(2026, 11, 30));
  });

  test(
    'ignores frequent payees, people, budgets and very different amounts',
    () {
      final charges = detectRecurringCharges([
        // A shop visited often.
        entry(at: eat(2026, 9, 28), amount: kes(400), payeeId: 1),
        entry(at: eat(2026, 10, 2), amount: kes(400), payeeId: 1),
        entry(at: eat(2026, 10, 20), amount: kes(400), payeeId: 1),
        // Money sent to a person.
        entry(
          at: eat(2026, 9, 5),
          amount: kes(2000),
          payeeId: 2,
          kind: TransactionKind.sent,
        ),
        entry(
          at: eat(2026, 10, 5),
          amount: kes(2000),
          payeeId: 2,
          kind: TransactionKind.sent,
        ),
        // Day-to-day spending.
        entry(
          at: eat(2026, 9, 6),
          amount: kes(300),
          payeeId: 3,
          isDailySpending: true,
        ),
        entry(
          at: eat(2026, 10, 6),
          amount: kes(300),
          payeeId: 3,
          isDailySpending: true,
        ),
        // Amount doubled.
        entry(at: eat(2026, 9, 8), amount: kes(1000), payeeId: 4),
        entry(at: eat(2026, 10, 8), amount: kes(2000), payeeId: 4),
      ], today: today);
      expect(charges, isEmpty);
    },
  );

  test('drops charges expected before today', () {
    final charges = detectRecurringCharges([
      entry(at: eat(2026, 8, 3), amount: kes(1100), payeeId: 7),
      entry(at: eat(2026, 9, 3), amount: kes(1100), payeeId: 7),
    ], today: today);
    expect(charges, isEmpty);
  });
}
