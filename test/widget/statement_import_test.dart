import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/statements/data/pdf_text_extractor.dart';
import 'package:pesaclarity/src/features/statements/data/statement_file_picker.dart';

import '../helpers/statement_samples.dart';
import '../helpers/test_app.dart';

PickedStatement _file(String id) =>
    PickedStatement(name: '$id.pdf', bytes: fakePdf(id));

void main() {
  _withoutEngineTests();

  final extractor = FakePdfTextExtractor(
    {'locked': mpesaStatementPages(), 'kcb': kcbStatementPages()},
    passwords: {'locked': '0000'},
  );

  Future<void> openImport(
    WidgetTester tester,
    List<PickedStatement> files,
  ) async {
    await pumpApp(
      tester,
      db: openTestDatabase(),
      overrides: [
        statementFilePickerProvider.overrideWithValue(
          FakeStatementFilePicker(files),
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
