import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/features/sms/application/notification_capture.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/sms/data/notification_source.dart';
import 'package:pesaclarity/src/features/sms/presentation/notification_capture_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../helpers/fake_notification_source.dart';
import '../../helpers/sms_samples.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = openTestDatabase();
    await DriftInstitutionsRepository(db).setSelected('mpesa', selected: true);
  });

  ProviderContainer container(FakeNotificationSource source) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        notificationSourceProvider.overrideWithValue(source),
        smsParseBatchProvider.overrideWithValue(
          (packs, messages) async => parseAll(packs, messages),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> settle([bool Function()? until]) async {
    for (var i = 0; i < 50 && !(until?.call() ?? false); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<List<TransactionRecord>> stored() => db.select(db.transactions).get();

  test('reads nothing until turned on, and stops watching', () async {
    final source = FakeNotificationSource();
    addTearDown(source.close);
    final c = container(source);
    final sub = c.listen(liveNotificationCaptureProvider, (_, _) {});
    addTearDown(sub.close);
    await settle(() => source.watchedHistory.isNotEmpty);

    expect(source.watchedHistory.last, isEmpty);
    source.post(mpesaSent());
    await settle();
    expect(await stored(), isEmpty);
  });

  test('once on, adds watched messages as they arrive and drops the '
      'rest', () async {
    final source = FakeNotificationSource();
    addTearDown(source.close);
    final c = container(source);
    await c.read(notificationCaptureEnabledProvider.notifier).setEnabled(true);
    final results = <SmsIngestSummary>[];
    final sub = c.listen(liveNotificationCaptureProvider, (_, next) {
      if (next case AsyncData(:final value)) results.add(value);
    });
    addTearDown(sub.close);
    await settle(() => results.isNotEmpty);
    expect(source.watched, {'MPESA'});

    source
      ..post(mpesaSent())
      ..post(personal())
      ..post(mpesaNotice());
    await settle(() => results.length >= 2);
    await settle();

    expect((await stored()).map((t) => t.receiptNo), ['TJA0000001']);
    // Cut-short or unknown text is not kept for review.
    expect(await db.select(db.reviewItems).get(), isEmpty);
  });

  test('counts a message once when SMS already added it', () async {
    final source = FakeNotificationSource();
    addTearDown(source.close);
    final c = container(source);
    await c.read(smsIngestorProvider).ingest([
      mpesaSent(),
    ], c.read(selectedInstitutionsProvider));
    await c.read(notificationCaptureEnabledProvider.notifier).setEnabled(true);
    final sub = c.listen(liveNotificationCaptureProvider, (_, _) {});
    addTearDown(sub.close);
    await settle(() => source.watched.isNotEmpty);

    source.post(mpesaSent());
    await settle();
    expect(await stored(), hasLength(1));
  });

  test('stays off without notification access', () async {
    final source = FakeNotificationSource(current: NotificationAccess.denied);
    addTearDown(source.close);
    final c = container(source);
    await c.read(notificationCaptureEnabledProvider.notifier).setEnabled(true);
    final sub = c.listen(liveNotificationCaptureProvider, (_, _) {});
    addTearDown(sub.close);
    await settle(() => source.watchedHistory.isNotEmpty);
    expect(source.watchedHistory.last, isEmpty);
  });

  test('joinNames reads naturally', () {
    expect(joinNames(['M-Pesa']), 'M-Pesa');
    expect(joinNames(['M-Pesa', 'KCB']), 'M-Pesa and KCB');
    expect(joinNames(['M-Pesa', 'I&M', 'KCB']), 'M-Pesa, I&M and KCB');
  });

  group('screen', () {
    Future<FakeNotificationSource> pumpScreen(
      WidgetTester tester, {
      NotificationAccess access = NotificationAccess.denied,
    }) async {
      final source = FakeNotificationSource(current: access);
      addTearDown(source.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            notificationSourceProvider.overrideWithValue(source),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const NotificationCaptureScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return source;
    }

    testAppWidgets('turning on without access opens the phone settings', (
      tester,
    ) async {
      final source = await pumpScreen(tester);
      expect(find.text('Off'), findsOneWidget);
      expect(
        find.text('M-Pesa. Everything else is left alone.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Turn on in settings'));
      await tester.pumpAndSettle();
      expect(source.settingsOpened, 1);
      expect(find.text('Allow access in phone settings'), findsOneWidget);
    });

    testAppWidgets('with access, the switch turns reading on and off', (
      tester,
    ) async {
      await pumpScreen(tester, access: NotificationAccess.granted);
      expect(find.text('Turn on in settings'), findsNothing);

      await tester.tap(find.byKey(const Key('notification-capture-switch')));
      await tester.pumpAndSettle();
      expect(find.text('On'), findsOneWidget);

      await tester.tap(find.byKey(const Key('notification-capture-switch')));
      await tester.pumpAndSettle();
      expect(find.text('Off'), findsOneWidget);
    });
  });
}
