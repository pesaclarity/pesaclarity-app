import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/income/make_it_last.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

void main() {
  final pin = MakeItLastPin(
    arrivalId: 7,
    dailyMinor: 20000,
    until: CalendarDate(2026, 11, 17),
  );

  test('round-trips through settings', () {
    final back = MakeItLastPin.fromJson(pin.toJson())!;
    expect(back.arrivalId, 7);
    expect(back.dailyMinor, 20000);
    expect(back.until, CalendarDate(2026, 11, 17));
    expect(MakeItLastPin.fromJson(null), isNull);
    expect(MakeItLastPin.fromJson({'arrivalId': 'x'}), isNull);
  });

  test('holds through its last day until newer money arrives', () {
    final day = CalendarDate(2026, 11, 17);
    expect(pin.appliesOn(day, latestArrivalId: 7), isTrue);
    expect(pin.appliesOn(day.addDays(1), latestArrivalId: 7), isFalse);
    expect(pin.appliesOn(day, latestArrivalId: 8), isFalse);
  });
}
