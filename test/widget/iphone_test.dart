import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/features/activity/presentation/add_transaction_sheet.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:pesaclarity/src/features/sms/presentation/connect_messages_screen.dart';
import 'package:pesaclarity/src/routing/app_shell.dart';
import 'package:pesaclarity/src/shared/adaptive/adaptive.dart';
import 'package:pesaclarity/src/shared/widgets/selector_field.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/test_app.dart';

class _FakeShortcuts implements ShortcutConnection {
  DateTime? last;
  int opened = 0;

  @override
  Future<DateTime?> lastArrival() async => last;

  @override
  Future<void> openShortcuts() async => opened++;
}

/// Like [testAppWidgets], on an iPhone.
void testOnIPhone(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}

void main() {
  test('arrival labels read naturally', () {
    // Noon in Nairobi, the zone tests run in.
    final now = DateTime.utc(2026, 10, 29, 9);
    expect(arrivalLabel(now, now), 'just now');
    expect(
      arrivalLabel(now.subtract(const Duration(minutes: 2)), now),
      '2 min ago',
    );
    expect(
      arrivalLabel(now.subtract(const Duration(hours: 3)), now),
      'today, 09:00',
    );
    expect(
      arrivalLabel(now.subtract(const Duration(hours: 20)), now),
      'yesterday, 16:00',
    );
    expect(
      arrivalLabel(now.subtract(const Duration(days: 6)), now),
      'Fri 23 Oct',
    );
  });

  group('on iPhone', () {
    late AppDatabase db;
    late _FakeShortcuts shortcuts;
    setUp(() {
      db = openTestDatabase();
      shortcuts = _FakeShortcuts();
    });

    Future<void> pumpIPhoneApp(WidgetTester tester) => pumpApp(
      tester,
      db: db,
      flavor: AppFlavor.appstore,
      overrides: [shortcutConnectionProvider.overrideWithValue(shortcuts)],
    );

    Future<void> toConnectStep(WidgetTester tester) async {
      await pumpIPhoneApp(tester);
      await getStarted(tester);
      await tester.tap(find.text('M-Pesa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan my messages'));
      await tester.pumpAndSettle();
    }

    testOnIPhone('the theme uses the system font at iOS sizes', (tester) async {
      final theme = AppTheme.light;
      expect(theme.platform, TargetPlatform.iOS);
      expect(theme.textTheme.bodyLarge!.fontSize, 17);
      expect(theme.textTheme.bodyLarge!.fontFamily, isNot('Inter'));
      // Figures keep the brand face.
      expect(theme.textTheme.displaySmall!.fontFamily, 'SpaceGrotesk');
    });

    testOnIPhone('onboarding connects Shortcuts in place of the SMS scan', (
      tester,
    ) async {
      await toConnectStep(tester);

      expect(find.text('Connect your messages'), findsOneWidget);
      expect(find.text('Waiting for your first message'), findsOneWidget);
      expect(find.text('Allow access to messages'), findsNothing);

      await tester.tap(find.byKey(const Key('connect-open-shortcuts')));
      await tester.pumpAndSettle();
      expect(shortcuts.opened, 1);

      await tapText(tester, 'Do this later');
      expect(find.byType(CupertinoStyleTabBar), findsOneWidget);
      expect(find.byType(PillNavigationBar), findsNothing);
    });

    testOnIPhone('once a message arrives, onboarding can continue', (
      tester,
    ) async {
      shortcuts.last = DateTime.now().subtract(const Duration(minutes: 2));
      await toConnectStep(tester);

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Last message 2 min ago'), findsOneWidget);
      await tapText(tester, 'Continue');
      expect(find.byType(CupertinoStyleTabBar), findsOneWidget);
    });

    testOnIPhone('Profile groups its rows and links to Connect messages', (
      tester,
    ) async {
      await toConnectStep(tester);
      await tapText(tester, 'Do this later');
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('MONEY'), findsOneWidget);
      await tapText(tester, 'Connect messages');
      expect(find.text('Connect your messages'), findsOneWidget);
    });

    Future<void> pumpSheet(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: AddTransactionSheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testOnIPhone('forms use the sliding control and the date wheel', (
      tester,
    ) async {
      await pumpSheet(tester);
      expect(
        find.byWidgetPredicate((w) => w is CupertinoSlidingSegmentedControl),
        findsOneWidget,
      );
      expect(find.byWidgetPredicate((w) => w is SegmentedButton), findsNothing);

      await tapText(tester, 'Tap to change the day');
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsNothing);
    });

    testOnIPhone('dialogs and choices look like iOS', (tester) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => showAdaptiveDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog.adaptive(
                      title: const Text('Delete it?'),
                      actions: [
                        DialogAction(
                          destructive: true,
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Ask'),
                ),
                TextButton(
                  onPressed: () async => picked = await pickOne<String>(
                    context,
                    title: 'Lock after',
                    options: const [
                      ('now', 'Straight away'),
                      ('1m', '1 minute'),
                    ],
                    selected: 'now',
                  ),
                  child: const Text('Choose'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsNothing);
      expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
      await tester.tap(find.text('1 minute'));
      await tester.pumpAndSettle();
      expect(picked, '1m');
    });
  });

  testAppWidgets('Android keeps its own look', (tester) async {
    await pumpApp(tester, db: openTestDatabase());
    await getStarted(tester);
    await tester.tap(find.text('M-Pesa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan my messages'));
    await tester.pumpAndSettle();
    expect(find.text('Allow access to messages'), findsOneWidget);
    expect(find.text('Connect your messages'), findsNothing);
  });
}
