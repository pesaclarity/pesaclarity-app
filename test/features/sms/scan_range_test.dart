import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/sms/domain/scan_range.dart';

void main() {
  final today = CalendarDate(2026, 5, 31);

  test('every message has no first day', () {
    expect(ScanRange.all.firstDay(today), isNull);
    expect(ScanRange.all.label, 'All messages');
  });

  test('months count back from today, short months clamped', () {
    expect(
      const ScanRange(ScanPeriod.months3).firstDay(today),
      CalendarDate(2026, 2, 28),
    );
    expect(
      const ScanRange(ScanPeriod.months12).firstDay(today),
      CalendarDate(2025, 5, 31),
    );
  });

  test('a chosen date reads from that day', () {
    final range = ScanRange(ScanPeriod.since, since: CalendarDate(2026, 3, 5));
    expect(range.firstDay(today), CalendarDate(2026, 3, 5));
    expect(range.label, 'From 5 Mar 2026');
  });

  test('round-trips through settings; anything unknown is every message', () {
    for (final range in [
      ScanRange.all,
      const ScanRange(ScanPeriod.months6),
      ScanRange(ScanPeriod.since, since: CalendarDate(2026, 3, 5)),
    ]) {
      expect(ScanRange.fromJson(range.toJson()), range);
    }
    expect(ScanRange.fromJson(null), ScanRange.all);
    expect(ScanRange.fromJson(const {'period': 'decade'}), ScanRange.all);
    expect(ScanRange.fromJson(const {'period': 'since'}), ScanRange.all);
  });
}
