import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/reminders/reminder_schedule.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

void main() {
  test('the daily nudge lists who is due, today if the time is ahead', () {
    final now = DateTime(2026, 11, 5, 9);
    CalendarDate? asked;
    final r = collectReminder(
      now: now,
      hour: 18,
      minute: 0,
      showAmounts: true,
      due: (day) {
        asked = day;
        return [
          ('Otieno', '1,200'),
          ('Kamau', '700'),
          ('Njeri', '600'),
          ('Ali', '50'),
        ];
      },
    )!;
    expect(asked, CalendarDate(2026, 11, 5));
    expect(r.id, collectReminderId);
    expect(r.kind, ReminderKind.collect);
    expect(r.at, DateTime(2026, 11, 5, 18).toUtc());
    expect(r.title, '4 customers to remind today');
    expect(r.body, 'Otieno 1,200 · Kamau 700 · Njeri 600 · 1 more');
  });

  test('after the time it is tomorrow; amounts hide; nobody due is none', () {
    final now = DateTime(2026, 11, 5, 19);
    final r = collectReminder(
      now: now,
      hour: 18,
      minute: 0,
      showAmounts: false,
      due: (day) => [('Otieno', '1,200')],
    )!;
    expect(r.at, DateTime(2026, 11, 6, 18).toUtc());
    expect(r.title, '1 customer to remind today');
    expect(r.body, 'Otieno');
    expect(
      collectReminder(
        now: now,
        hour: 18,
        minute: 0,
        showAmounts: true,
        due: (_) => const [],
      ),
      isNull,
    );
  });
}
