import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/shared/widgets/form_fields.dart';

void main() {
  testWidgets('a date field says the day the way people do', (tester) async {
    Future<void> show(CalendarDate date) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Tuesday 10 November 2026, 09:00 EAT.
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 10, 6)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DateField(
              label: 'Date',
              value: date,
              onChanged: (_) {},
              firstDate: CalendarDate(2020, 1, 1),
              lastDate: CalendarDate(2030, 12, 31),
            ),
          ),
        ),
      ),
    );

    await show(CalendarDate(2026, 11, 10));
    expect(find.text('Today'), findsOneWidget);
    await show(CalendarDate(2026, 11, 9));
    expect(find.text('Yesterday'), findsOneWidget);
    await show(CalendarDate(2026, 11, 2));
    expect(find.text('Mon 2 Nov'), findsOneWidget);
    await show(CalendarDate(2025, 11, 3));
    expect(find.text('Mon 3 Nov 2025'), findsOneWidget);
  });
}
