import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';

import '../helpers/fake_sms_source.dart';
import '../helpers/sms_samples.dart';
import '../helpers/test_app.dart';

const _home = 'Safe to spend today';

void main() {
  Future<void> scan(WidgetTester tester, FakeSmsSource sms) async {
    await pumpApp(
      tester,
      db: openTestDatabase(),
      sms: sms,
      // Monday 26 October 2026, 18:00 EAT, the day the sample messages came.
      overrides: [
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 26, 15)),
      ],
    );
    await tapText(tester, 'Get started');
    await tapText(tester, 'M-Pesa');
    await tapText(tester, 'Scan my messages');
    await tapText(tester, 'Allow access to messages');
  }

  testAppWidgets('after a scan that finds transactions, shows the first '
      'insight before Home', (tester) async {
    final sms = FakeSmsSource(
      inbox: [mpesaSent(), mpesaTill()],
      current: SmsAccess.granted,
    );
    addTearDown(sms.close);
    await scan(tester, sms);
    expect(find.text('Found 2 transactions'), findsOneWidget);

    await tapText(tester, 'Continue');
    expect(find.text('Your last 90 days'), findsOneWidget);
    expect(find.text('From 2 transactions in your messages.'), findsOneWidget);
    expect(find.text('Money in'), findsOneWidget);
    // 1,500 sent and 350 paid, plus the 15 transaction cost.
    expect(find.text('KES 1,865'), findsOneWidget);
    expect(find.text('Leakages'), findsOneWidget);
    expect(find.text('KES 15'), findsOneWidget);
    await tester.ensureVisible(find.text('Fuliza fees'));
    expect(find.text('Clear of Fuliza'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    await tester.scrollUntilVisible(find.text('Go to Home'), 200);
    await tapText(tester, 'Go to Home');
    expect(find.text(_home), findsOneWidget);
  });

  testAppWidgets('a scan that finds nothing goes straight to Home', (
    tester,
  ) async {
    final sms = FakeSmsSource(current: SmsAccess.granted);
    addTearDown(sms.close);
    await scan(tester, sms);
    expect(find.text('No transactions found yet'), findsOneWidget);

    await tapText(tester, 'Continue');
    expect(find.text(_home), findsOneWidget);
    expect(find.text('Your last 90 days'), findsNothing);
  });
}
