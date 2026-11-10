import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/budget/until_next_money.dart';
import 'package:pesaclarity/src/domain/income/make_it_last.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/income/application/income_providers.dart';
import 'package:pesaclarity/src/features/income/presentation/make_it_last_sheet.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

class _FakePins extends MakeItLastController {
  final used = <MakeItLastPin>[];

  @override
  Future<MakeItLastPin?> build() async => null;

  @override
  Future<void> use(MakeItLastPin pin) async => used.add(pin);
}

void main() {
  final today = CalendarDate(2026, 11, 4);
  final plan = UntilNextMoney.calculate(
    today: today,
    basis: NextMoneyBasis.rhythm,
    onHandAtStartMinor: 500000,
    billsMinor: 150000,
    bills: [
      BillDue(
        name: 'Rent share',
        due: CalendarDate(2026, 11, 20),
        amountMinor: 150000,
      ),
    ],
    spentTodayMinor: 0,
    paceMinor: 50000,
    usualTodayMinor: 50000,
    historyDays: 60,
    nextMoney: today.addDays(14),
  );

  Future<_FakePins> open(WidgetTester tester) async {
    final pins = _FakePins();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [makeItLastProvider.overrideWith(() => pins)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MakeItLastSheet(
              arrivalId: 9,
              arrivalMinor: 500000,
              from: 'Test Mum',
              plan: plan,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return pins;
  }

  testWidgets('splits the money and uses the plan', (tester) async {
    final pins = await open(tester);

    expect(find.text('Money in · from Test Mum'), findsOneWidget);
    expect(find.text('KES 5,000'), findsOneWidget);
    expect(
      find.text('Next money usually comes in about 14 days. Make it last:'),
      findsOneWidget,
    );
    expect(find.text('Rent share'), findsOneWidget);
    expect(find.text('Due 20 Nov'), findsOneWidget);
    expect(find.text('Kept back'), findsOneWidget);
    expect(find.text('Each day until 17 Nov'), findsOneWidget);
    expect(find.text('214.28'), findsOneWidget);
    expect(
      find.textContaining('At your usual pace it lasts until about'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('make-it-last-use')));
    await tester.pumpAndSettle();
    expect(pins.used.single.arrivalId, 9);
    expect(pins.used.single.dailyMinor, plan.dailyMinor);
    expect(pins.used.single.until, CalendarDate(2026, 11, 17));
  });

  testWidgets('a different daily amount can be chosen', (tester) async {
    final pins = await open(tester);
    await tester.ensureVisible(find.byKey(const Key('make-it-last-change')));
    await tester.tap(find.byKey(const Key('make-it-last-change')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('make-it-last-amount')), '150');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('make-it-last-use')));
    await tester.tap(find.byKey(const Key('make-it-last-use')));
    await tester.pumpAndSettle();
    expect(pins.used.single.dailyMinor, 15000);
  });
}
