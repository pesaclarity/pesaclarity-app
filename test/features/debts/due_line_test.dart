import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/debts/next_due.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/debts/presentation/due_line.dart';

void main() {
  final due = CalendarDate(2026, 12, 5);
  final unpaid = NextDue(date: due);
  final paid = NextDue(date: due, paidSince: true);

  String? say(
    NextDue next,
    int month,
    int day, {
    String? amount = 'KES 2,500',
  }) =>
      dueLineText(next, today: CalendarDate(2026, month, day), amount: amount);

  test('says the date while there is time', () {
    expect(say(unpaid, 11, 21), 'Next KES 2,500 due 5 Dec');
    expect(say(unpaid, 12, 1), 'Next KES 2,500 due 5 Dec');
  });

  test('counts the days when close', () {
    expect(say(unpaid, 12, 2), 'Next KES 2,500 due in 3 days, 5 Dec');
    expect(say(unpaid, 12, 3), 'Next KES 2,500 due in 2 days, 5 Dec');
    expect(say(unpaid, 12, 4), 'Next KES 2,500 due tomorrow, 5 Dec');
    expect(say(unpaid, 12, 5), 'Next KES 2,500 due today');
  });

  test('says how late', () {
    expect(say(unpaid, 12, 6), 'KES 2,500 was due 5 Dec · 1 day late');
    expect(say(unpaid, 12, 8), 'KES 2,500 was due 5 Dec · 3 days late');
  });

  test('says nothing once paid', () {
    expect(say(paid, 12, 8), isNull);
  });

  test('reads without an amount', () {
    expect(say(unpaid, 11, 21, amount: null), 'Next payment due 5 Dec');
    expect(
      say(unpaid, 12, 8, amount: null),
      'A payment was due 5 Dec · 3 days late',
    );
  });

  test('adds the year when it is not this year', () {
    final next = NextDue(date: CalendarDate(2027, 1, 15));
    expect(say(next, 11, 21), 'Next KES 2,500 due 15 Jan 2027');
  });
}
