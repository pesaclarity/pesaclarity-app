import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:pesaclarity/src/features/sms/presentation/connect_messages_screen.dart';
import 'package:pesaclarity/src/features/sms/presentation/paste_messages_screen.dart';
import 'package:pesaclarity/src/features/statements/data/pdf_text_extractor.dart';

import '../helpers/sms_samples.dart';
import '../helpers/test_app.dart';

class _Shortcuts implements ShortcutConnection {
  @override
  Future<DateTime?> lastArrival() async => null;

  @override
  Future<void> openShortcuts() async {}
}

/// The clipboard, holding [text]; counts each read.
class _Clipboard {
  _Clipboard(this.text);

  String? text;
  var reads = 0;

  Future<String?> read() async {
    reads++;
    return text;
  }
}

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
  final pasted =
      '${mpesaSent().body}\n${mpesaTill().body}\n\n${mpesaNotice().body}';
  late AppDatabase db;
  late _Clipboard clipboard;

  setUp(() {
    db = openTestDatabase();
    clipboard = _Clipboard(pasted);
  });

  Future<void> toConnectStep(WidgetTester tester) async {
    await pumpApp(
      tester,
      db: db,
      flavor: AppFlavor.appstore,
      overrides: [
        shortcutConnectionProvider.overrideWithValue(_Shortcuts()),
        statementImportAvailableProvider.overrideWithValue(true),
        clipboardTextProvider.overrideWithValue(clipboard.read),
      ],
    );
    await getStarted(tester);
    await tester.tap(find.text('M-Pesa'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Scan my messages'));
    await tester.tap(find.text('Scan my messages'));
    await tester.pumpAndSettle();
  }

  Future<void> pasteAndRead(WidgetTester tester) async {
    expect(find.text('Nothing pasted yet'), findsOneWidget);
    final read = find.byKey(const Key('paste-read'));
    expect(tester.widget<FilledButton>(read).onPressed, isNull);
    // The clipboard is read only once Paste is tapped.
    final before = clipboard.reads;
    await tester.pumpAndSettle();
    expect(clipboard.reads, before);
    await tester.tap(find.byKey(const Key('paste-button')));
    await tester.pumpAndSettle();
    expect(clipboard.reads, before + 1);
    expect(find.text('3 messages pasted'), findsOneWidget);
    await tester.ensureVisible(read);
    await tester.pumpAndSettle();
    await tester.tap(read);
    await tester.pumpAndSettle();
  }

  testOnIPhone('setup: paste messages, add the new ones, see the money', (
    tester,
  ) async {
    await toConnectStep(tester);
    await scrollTo(tester, find.byKey(const Key('connect-paste')));
    expect(find.text('Past months, or without Shortcuts'), findsOneWidget);
    await tester.tap(find.byKey(const Key('connect-paste')));
    await tester.pumpAndSettle();
    expect(find.byType(PasteMessagesScreen), findsOneWidget);
    expect(find.textContaining('nothing leaves the phone'), findsOneWidget);

    await pasteAndRead(tester);
    expect(find.text('Found 2 payments'), findsOneWidget);
    expect(
      find.text('All 2 are new. 1 message was not a payment and is left out.'),
      findsOneWidget,
    );
    expect(find.text('EXAMPLE GROCERS'), findsOneWidget);
    expect(find.text('JANE DOE'), findsOneWidget);

    await tapText(tester, 'Add 2 payments');
    expect(find.text('2 payments added'), findsOneWidget);
    expect(
      find.text(
        'The text you pasted is cleared from this screen and is not kept.',
      ),
      findsOneWidget,
    );
    final rows = await tester.runAsync(() => db.select(db.transactions).get());
    expect(rows!.map((r) => r.receiptNo).toSet(), {'TJA0000001', 'TJA0000004'});
    // Nothing of the pasted text is kept: not the notice, not the review.
    expect(
      await tester.runAsync(() => db.select(db.reviewItems).get()),
      isEmpty,
    );

    await tapText(tester, 'See your money');
    expect(find.text('From 2 transactions in your messages.'), findsOneWidget);
    expect(find.text('Make it yours'), findsOneWidget);
  });

  testOnIPhone('My accounts: paste what Shortcuts missed; what is in already '
      'is left out', (tester) async {
    await toConnectStep(tester);
    await scrollTo(tester, find.byKey(const Key('connect-paste')));
    await tester.tap(find.byKey(const Key('connect-paste')));
    await tester.pumpAndSettle();
    await pasteAndRead(tester);
    await tapText(tester, 'Add 2 payments');
    await tapText(tester, 'See your money');
    await tapText(tester, 'Go to Home');

    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tapText(tester, 'My accounts');
    await scrollTo(tester, find.byKey(const Key('accounts-paste')));
    expect(find.text('Add M-Pesa messages Shortcuts missed'), findsOneWidget);
    expect(find.byKey(const Key('accounts-import')), findsOneWidget);
    await tester.tap(find.byKey(const Key('accounts-paste')));
    await tester.pumpAndSettle();

    await pasteAndRead(tester);
    expect(clipboard.reads, 2);
    expect(find.text('Found 2 payments'), findsOneWidget);
    expect(
      find.textContaining('All 2 are already in your records.'),
      findsOneWidget,
    );
    expect(find.text('Add 2 payments'), findsNothing);
    await tapText(tester, 'Done');
    final rows = await tester.runAsync(() => db.select(db.transactions).get());
    expect(rows, hasLength(2));
  });

  testWidgets('not on Android: My accounts has no Paste messages', (
    tester,
  ) async {
    await pumpApp(tester, db: db);
    await finishOnboarding(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tapText(tester, 'My accounts');
    expect(find.byKey(const Key('accounts-paste')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
