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
import 'package:pesaclarity/src/features/statements/data/pdf_text_extractor.dart';
import 'package:pesaclarity/src/features/statements/presentation/statement_import_screen.dart';
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
      overrides: [
        shortcutConnectionProvider.overrideWithValue(shortcuts),
        statementImportAvailableProvider.overrideWithValue(true),
      ],
    );

    Future<void> toConnectStep(WidgetTester tester) async {
      await pumpIPhoneApp(tester);
      await getStarted(tester);
      await tester.tap(find.text('M-Pesa'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Scan my messages'));
      await tester.tap(find.text('Scan my messages'));
      await tester.pumpAndSettle();
    }

    testOnIPhone('the theme is the Android design, with swipe-back pages', (
      tester,
    ) async {
      final theme = AppTheme.light;
      expect(theme.platform, TargetPlatform.android);
      expect(theme.textTheme.bodyLarge!.fontSize, 17);
      expect(theme.textTheme.bodyLarge!.fontFamily, 'Inter');
      expect(theme.textTheme.displaySmall!.fontFamily, 'SpaceGrotesk');
      expect(
        theme.pageTransitionsTheme.builders[TargetPlatform.android],
        isA<CupertinoPageTransitionsBuilder>(),
      );
    });

    testOnIPhone('the theme follows iOS: large title, back chevron, rows', (
      tester,
    ) async {
      final theme = AppTheme.light;
      expect(theme.textTheme.headlineLarge!.fontSize, 34);
      expect(theme.textTheme.headlineLarge!.fontWeight, FontWeight.w700);
      expect(theme.appBarTheme.centerTitle, isTrue);
      expect(theme.appBarTheme.titleTextStyle!.fontSize, 17);
      expect(theme.appBarTheme.titleTextStyle!.fontWeight, FontWeight.w600);
      expect(theme.inputDecorationTheme.filled, isTrue);
      expect(
        theme.inputDecorationTheme.enabledBorder!.borderSide,
        BorderSide.none,
      );

      await tester.pumpWidget(
        MaterialApp(theme: theme, home: const SizedBox()),
      );
      final context = tester.element(find.byType(SizedBox));
      final back =
          theme.actionIconTheme!.backButtonIconBuilder!(context) as Icon;
      expect(back.icon, Icons.arrow_back_ios_new);
    });

    testOnIPhone('the tab bar is glass, inset as iOS insets it', (
      tester,
    ) async {
      await toConnectStep(tester);
      await tapText(tester, 'Do this later');

      final bar = find.byType(PillNavigationBar);
      expect(
        find.descendant(of: bar, matching: find.byType(BackdropFilter)),
        findsOneWidget,
      );
      final screen = tester.getRect(find.byType(Scaffold).first);
      final rect = tester.getRect(bar);
      expect(rect.left - screen.left, PillNavigationBar.iPhoneInset);
      expect(screen.bottom - rect.bottom, PillNavigationBar.iPhoneInset);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).extendBody,
        isTrue,
      );
    });

    testOnIPhone('a tab title moves into a small bar once scrolled', (
      tester,
    ) async {
      await toConnectStep(tester);
      await tapText(tester, 'Do this later');

      double opacity() => tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.byKey(const Key('collapsed-tab-title')),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;
      expect(opacity(), 0);

      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      expect(
        find.descendant(
          of: find.byKey(const Key('collapsed-tab-title')),
          matching: find.text('Home'),
        ),
        findsOneWidget,
      );

      await tester.drag(find.byType(ListView).first, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(opacity(), 0);
    });

    testOnIPhone('onboarding connects Shortcuts in place of the SMS scan', (
      tester,
    ) async {
      await toConnectStep(tester);

      expect(find.text('Connect your messages'), findsOneWidget);
      expect(
        find.textContaining('Waiting for your first message.'),
        findsOneWidget,
      );
      expect(find.text('Allow access to messages'), findsNothing);

      await scrollTo(tester, find.byKey(const Key('connect-open-shortcuts')));
      await tester.tap(find.byKey(const Key('connect-open-shortcuts')));
      await tester.pumpAndSettle();
      expect(shortcuts.opened, 1);

      await tapText(tester, 'Do this later');
      expect(find.byType(PillNavigationBar), findsOneWidget);
    });

    testOnIPhone('setup offers a statement for the months before', (
      tester,
    ) async {
      await toConnectStep(tester);
      await scrollTo(tester, find.byKey(const Key('connect-import-past')));
      expect(find.text('Past months'), findsOneWidget);
      await tester.tap(find.byKey(const Key('connect-import-past')));
      await tester.pumpAndSettle();
      expect(find.byType(StatementImportScreen), findsOneWidget);
    });

    testOnIPhone('once a message arrives, onboarding can continue', (
      tester,
    ) async {
      shortcuts.last = DateTime.now().subtract(const Duration(minutes: 2));
      await toConnectStep(tester);

      expect(find.text('Connected. Last message 2 min ago.'), findsOneWidget);
      await tapText(tester, 'Continue');
      expect(find.byType(PillNavigationBar), findsOneWidget);
    });

    testOnIPhone('Profile is the Android list, plus Connect messages', (
      tester,
    ) async {
      await toConnectStep(tester);
      await tapText(tester, 'Do this later');
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('MONEY'), findsNothing);
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

    testOnIPhone('forms use the Android controls and date dialog', (
      tester,
    ) async {
      await pumpSheet(tester);
      expect(
        find.byWidgetPredicate((w) => w is SegmentedButton),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('add-transaction-date')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
    });

    testOnIPhone('dialogs and choices look like Android', (tester) async {
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
      expect(find.bySubtype<AlertDialog>(), findsOneWidget);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsOneWidget);
      await tester.tap(find.text('1 minute'));
      await tester.pumpAndSettle();
      expect(picked, '1m');
    });
  });

  testAppWidgets('Android scans the inbox', (tester) async {
    await pumpApp(tester, db: openTestDatabase());
    await getStarted(tester);
    await tester.tap(find.text('M-Pesa'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Scan my messages'));
    await tester.tap(find.text('Scan my messages'));
    await tester.pumpAndSettle();
    expect(find.text('Allow access to messages'), findsOneWidget);
    expect(find.text('Connect your messages'), findsNothing);
  });
}
