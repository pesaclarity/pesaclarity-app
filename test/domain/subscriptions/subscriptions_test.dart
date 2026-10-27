import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/subscriptions/subscriptions.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

void main() {
  final today = CalendarDate(2026, 10, 27);

  test('steps keep the day of the month where it exists', () {
    expect(
      stepDate(CalendarDate(2026, 1, 31), RecurrenceFrequency.monthly),
      CalendarDate(2026, 2, 28),
    );
    expect(
      stepDate(CalendarDate(2026, 10, 27), RecurrenceFrequency.weekly),
      CalendarDate(2026, 11, 3),
    );
    expect(
      stepDate(CalendarDate(2026, 11, 30), RecurrenceFrequency.quarterly),
      CalendarDate(2027, 2, 28),
    );
    expect(
      stepDate(CalendarDate(2024, 2, 29), RecurrenceFrequency.yearly),
      CalendarDate(2025, 2, 28),
    );
  });

  test('monthly cost of each frequency', () {
    expect(monthlyMinor(kes(1200), RecurrenceFrequency.yearly), kes(100));
    expect(monthlyMinor(kes(300), RecurrenceFrequency.quarterly), kes(100));
    expect(monthlyMinor(kes(120), RecurrenceFrequency.weekly), kes(520));
  });

  Subscription saved({
    int id = 1,
    String name = 'Streaming',
    int? payeeId,
    int amount = 300,
    RecurrenceFrequency frequency = RecurrenceFrequency.monthly,
    CalendarDate? next,
    SubscriptionStatus status = SubscriptionStatus.tracking,
  }) => Subscription(
    id: id,
    name: name,
    payeeId: payeeId,
    amountMinor: kes(amount),
    frequency: frequency,
    nextDate: next ?? CalendarDate(2026, 11, 2),
    status: status,
  );

  test('follows the latest charge, and shows a price change', () {
    final overview = SubscriptionsOverview.of(
      saved: [saved(payeeId: 7, amount: 250)],
      entries: [
        entry(at: eat(2026, 9, 2), amount: kes(250), payeeId: 7),
        entry(at: eat(2026, 10, 2), amount: kes(300), payeeId: 7),
      ],
      today: today,
    );
    final line = overview.lines.single;
    expect(line.amountMinor, kes(300));
    expect(line.previousAmountMinor, kes(250));
    expect(line.lastChargedOn, CalendarDate(2026, 10, 2));
    expect(line.nextDate, CalendarDate(2026, 11, 2));
    expect(overview.monthlyTotalMinor, kes(300));
    expect(overview.yearlyTotalMinor, kes(3600));
  });

  test('a subscription added by hand rolls its date forward to today', () {
    final overview = SubscriptionsOverview.of(
      saved: [
        saved(
          amount: 1200,
          frequency: RecurrenceFrequency.yearly,
          next: CalendarDate(2025, 3, 1),
        ),
        saved(
          id: 2,
          name: 'Gym',
          amount: 3000,
          next: CalendarDate(2026, 10, 8),
        ),
      ],
      entries: const [],
      today: today,
    );
    expect(overview.lines.map((l) => l.nextDate), [
      CalendarDate(2026, 11, 8),
      CalendarDate(2027, 3, 1),
    ]);
    expect(overview.next!.subscription.name, 'Gym');
    expect(overview.monthlyTotalMinor, kes(3000 + 100));
  });

  test('suggests repeat charges not yet tracked or turned down', () {
    final entries = [
      for (final payee in [7, 8, 9]) ...[
        entry(
          at: eat(2026, 9, 12),
          amount: kes(649),
          kind: TransactionKind.paybill,
          payeeId: payee,
        ),
        entry(
          at: eat(2026, 10, 12),
          amount: kes(649),
          kind: TransactionKind.paybill,
          payeeId: payee,
        ),
      ],
    ];
    final overview = SubscriptionsOverview.of(
      saved: [
        saved(payeeId: 7),
        saved(id: 2, payeeId: 8, status: SubscriptionStatus.dismissed),
      ],
      entries: entries,
      today: today,
    );
    expect(overview.suggestions.map((c) => c.payeeId), [9]);
    // A dismissed one is neither a line nor counted.
    expect(overview.lines, hasLength(1));
  });
}
