import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';

import '../helpers/fake_sms_source.dart';
import '../helpers/sms_samples.dart';
import '../helpers/test_app.dart';

const _home = 'Safe to spend today';

void main() {
  Future<void> toScan(WidgetTester tester) async {
    await tapText(tester, 'Get started');
    await tapText(tester, 'M-Pesa');
    await tapText(tester, 'Scan my messages');
  }

  testAppWidgets('explains SMS access, then scans and shows what it found', (
    tester,
  ) async {
    final db = openTestDatabase();
    final sms = FakeSmsSource(
      inbox: [mpesaSent(), mpesaTill(), mpesaNotice(), personal(), kcbDebit()],
      current: SmsAccess.denied,
    );
    addTearDown(sms.close);
    await pumpApp(tester, db: db, sms: sms);
    await toScan(tester);

    expect(
      find.text('Let Pesa Clarity read your account messages'),
      findsOneWidget,
    );
    expect(find.textContaining('message text is then thrown'), findsOneWidget);
    expect(sms.permissionRequests, 0, reason: 'explain before asking');
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    await tapText(tester, 'Allow access to messages');
    expect(sms.permissionRequests, 1);
    expect(sms.reads.single.senders, {'MPESA'});
    expect(find.text('Found 2 transactions'), findsOneWidget);
    expect(find.textContaining('1 message could not be read'), findsOneWidget);

    final stored = await tester.runAsync(
      () => db.select(db.transactions).get(),
    );
    expect(stored, hasLength(2));
    final review = await tester.runAsync(() => db.select(db.reviewItems).get());
    expect(review!.single.body, mpesaNotice().body);

    await tapText(tester, 'Continue');
    expect(find.text('Your last 90 days'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Go to Home'), 200);
    await tapText(tester, 'Go to Home');
    expect(find.text(_home), findsOneWidget);
  });

  testAppWidgets('going on without SMS access finishes onboarding', (
    tester,
  ) async {
    final sms = FakeSmsSource(
      inbox: [mpesaSent()],
      dialogAnswer: SmsAccess.denied,
    );
    addTearDown(sms.close);
    await pumpApp(tester, db: openTestDatabase(), sms: sms);
    await toScan(tester);

    await tapText(tester, 'Allow access to messages');
    expect(find.text('Messages not shared'), findsOneWidget);

    await tapText(tester, 'Continue without messages');
    expect(find.text(_home), findsOneWidget);
    expect(sms.reads, isEmpty);
    expect(sms.listenedSenders, isEmpty);
  });

  testAppWidgets('when Android stops asking, points to settings', (
    tester,
  ) async {
    final sms = FakeSmsSource(
      inbox: [mpesaSent()],
      dialogAnswer: SmsAccess.blocked,
    );
    addTearDown(sms.close);
    await pumpApp(tester, db: openTestDatabase(), sms: sms);
    await toScan(tester);

    await tapText(tester, 'Allow access to messages');
    expect(find.text('Messages are switched off'), findsOneWidget);
    await tapText(tester, 'Open settings');
    expect(sms.settingsOpened, 1);

    sms.current = SmsAccess.granted;
    await tapText(tester, 'I have allowed it');
    expect(find.text('Found 1 transaction'), findsOneWidget);
  });

  testAppWidgets('Not now skips the scan', (tester) async {
    final sms = FakeSmsSource(current: SmsAccess.denied);
    addTearDown(sms.close);
    await pumpApp(tester, db: openTestDatabase(), sms: sms);
    await toScan(tester);

    await tapText(tester, 'Not now');
    expect(find.text(_home), findsOneWidget);
    expect(sms.permissionRequests, 0);
  });
}
