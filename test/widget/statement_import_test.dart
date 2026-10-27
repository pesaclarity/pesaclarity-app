import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/statements/data/pdf_text_extractor.dart';
import 'package:pesaclarity/src/features/statements/data/statement_file_picker.dart';

import 'package:ujumbe/ujumbe.dart' show StatementPage;

import '../helpers/statement_samples.dart';
import '../helpers/test_app.dart';

PickedStatement _file(String id) =>
    PickedStatement(name: '$id.pdf', bytes: fakePdf(id));

void main() {
  _withoutEngineTests();

  final extractor = FakePdfTextExtractor(
    {
      'locked': mpesaStatementPages(),
      'locked-november': mpesaStatementPages(
        period: '01 Nov 2026 - 30 Nov 2026',
      ),
      'other-password': mpesaStatementPages(
        period: '01 Dec 2026 - 31 Dec 2026',
      ),
      'kcb': kcbStatementPages(),
      'scan': [const StatementPage([])],
    },
    passwords: {
      'locked': '0000',
      'locked-november': '0000',
      'other-password': '9999',
    },
  );

  Future<void> openImport(
    WidgetTester tester,
    List<PickedStatement> files, {
    StatementFilePicker? picker,
  }) async {
    await pumpApp(
      tester,
      db: openTestDatabase(),
      overrides: [
        statementFilePickerProvider.overrideWithValue(
          picker ?? FakeStatementFilePicker(files),
        ),
        pdfTextExtractorProvider.overrideWithValue(extractor),
      ],
    );
    await finishOnboarding(tester);
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Import a statement');
    expect(find.text('Fill gaps from a statement'), findsOneWidget);
  }

  testAppWidgets('imports a password-protected statement from Profile', (
    tester,
  ) async {
    await openImport(tester, [_file('locked'), _file('locked')]);

    await tapText(tester, 'Choose a PDF');
    expect(find.text('This statement has a password'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1111');
    await tapText(tester, 'Open statement');
    expect(
      find.text('That password did not open the file. Try again.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: 'the password is cleared once used',
    );

    await tester.enterText(find.byType(TextField), '0000');
    await tapText(tester, 'Open statement');
    expect(find.text('Statement imported'), findsOneWidget);
    expect(find.text('1 Oct 2026 to 31 Oct 2026'), findsOneWidget);
    expect(
      find.text('Matches the closing balance of KES 5,035'),
      findsOneWidget,
    );

    await tapText(tester, 'Choose another file');
    expect(
      find.textContaining('You imported this statement on'),
      findsOneWidget,
      reason: 'a known file is recognised before its password is asked',
    );
  });

  testAppWidgets('the password screen shows the Safaricom hint', (
    tester,
  ) async {
    await openImport(tester, [_file('locked')]);
    await tapText(tester, 'Choose a PDF');
    expect(
      find.text(
        'Safaricom sends the password by SMS when you request a statement.',
      ),
      findsOneWidget,
    );
  });

  testAppWidgets('three wrong passwords mean a short wait', (tester) async {
    await openImport(tester, [_file('locked')]);
    await tapText(tester, 'Choose a PDF');

    Future<void> tryPassword(String password) async {
      await tester.enterText(find.byType(TextField), password);
      await tapText(tester, 'Open statement');
    }

    await tryPassword('1111');
    await tryPassword('2222');
    expect(find.text('Try again in 30 seconds.'), findsNothing);
    await tryPassword('3333');
    expect(find.text('Try again in 30 seconds.'), findsOneWidget);
    final button = find.widgetWithText(FilledButton, 'Open statement');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Try again in 30 seconds.'), findsNothing);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tryPassword('0000');
    expect(find.text('Statement imported'), findsOneWidget);
  });

  testAppWidgets('a batch asks for a shared password once', (tester) async {
    await openImport(
      tester,
      const [],
      picker: FakeBatchFilePicker([
        [
          _file('locked'),
          _file('locked-november'),
          _file('kcb'),
          _file('other-password'),
          _file('scan'),
        ],
      ]),
    );
    await tapText(tester, 'Choose a PDF');
    expect(find.text('This statement has a password'), findsOneWidget);
    expect(find.text('locked.pdf'), findsOneWidget);
    expect(
      find.text('It is used to open the files you chose, then forgotten.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '0000');
    await tapText(tester, 'Open statement');

    // November opened with the same password; December needs its own.
    expect(find.text('other-password.pdf'), findsOneWidget);
    expect(
      find.text('That password did not open the file. Try again.'),
      findsNothing,
      reason: 'the batch password was tried quietly',
    );
    await tapText(tester, 'Skip this file');

    expect(find.text('Your statements'), findsOneWidget);
    // The results run past the screen; scroll to each in turn.
    final results = [
      find.text('locked.pdf'),
      find.text('locked-november.pdf'),
      find.text('KCB statements are coming soon.'),
      find.text('Skipped.'),
      find.textContaining('This PDF is a scanned picture.'),
    ];
    for (final result in results) {
      await tester.scrollUntilVisible(result, 200);
      expect(result, findsOneWidget);
    }
  });

  testAppWidgets('a scanned statement says how to get a readable one', (
    tester,
  ) async {
    await openImport(tester, [_file('scan')]);
    await tapText(tester, 'Choose a PDF');
    expect(find.text('This PDF is a scanned picture'), findsOneWidget);
  });

  testAppWidgets('a bank statement is coming soon', (tester) async {
    await openImport(tester, [_file('kcb')]);

    await tapText(tester, 'Choose a PDF');
    expect(find.text('KCB statements are coming soon'), findsOneWidget);
  });
}

void _withoutEngineTests() {
  testAppWidgets('Profile hides statement import without a PDF engine', (
    tester,
  ) async {
    await pumpApp(
      tester,
      db: openTestDatabase(),
      overrides: [pdfTextExtractorProvider.overrideWithValue(null)],
    );
    await finishOnboarding(tester);
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Import a statement'), findsNothing);
    expect(find.text('Backup and restore'), findsOneWidget);
  });
}
