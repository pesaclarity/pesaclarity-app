import 'dart:typed_data';

import 'package:pesaclarity/src/features/statements/data/pdf_text_extractor.dart';
import 'package:pesaclarity/src/features/statements/data/statement_file_picker.dart';
import 'package:ujumbe/ujumbe.dart'
    show FixtureColumn, StatementPage, typesetPage;

// Synthetic M-Pesa statement text in the shape a PDF text extractor gives:
// fake names, masked fake numbers and made-up receipts.

/// One statement row in East Africa Time. Amounts in cents; [amount] is
/// negative for money out.
typedef StatementRowSample = ({
  String receipt,
  String time,
  String details,
  int amount,
});

/// A day of John's M-Pesa: money in, a transfer with its charge, a till
/// payment and airtime. Overlaps `mpesaSent` and `mpesaTill` SMS samples.
const List<StatementRowSample> octoberRows = [
  (
    receipt: 'TJA0000003',
    time: '2026-10-26 08:02:10',
    details: 'Funds received from 0700***002 - JOHN KAMAU',
    amount: 200000,
  ),
  (
    receipt: 'TJA0000001',
    time: '2026-10-26 09:15:42',
    details: 'Customer Transfer to 0700***001 - JANE DOE',
    amount: -150000,
  ),
  (
    receipt: 'TJA0000001',
    time: '2026-10-26 09:15:42',
    details: 'Customer Transfer of Funds Charge',
    amount: -1500,
  ),
  (
    receipt: 'TJA0000004',
    time: '2026-10-26 13:45:00',
    details: 'Merchant Payment Online to 5000001 - EXAMPLE GROCERS',
    amount: -35000,
  ),
  (
    receipt: 'TJA0000006',
    time: '2026-10-26 19:00:00',
    details: 'Airtime Purchase',
    amount: -10000,
  ),
];

const octoberOpening = 500000;

/// [octoberOpening] plus every row.
const octoberClosing = 503500;

/// Lays out [rows] (oldest first) as statement text, newest first like the
/// real layout. Receipts in [omit] are dropped after balances are worked
/// out, as if lost in extraction.
String mpesaStatementText({
  List<StatementRowSample> rows = octoberRows,
  int opening = octoberOpening,
  String period = '01 Oct 2026 - 31 Oct 2026',
  Set<String> omit = const {},
}) {
  var balance = opening;
  final lines = <String>[];
  for (final row in rows) {
    balance += row.amount;
    if (omit.contains(row.receipt)) continue;
    lines.add(
      '${row.receipt} ${row.time} ${row.details} Completed '
      '${_money(row.amount)} ${_money(balance)}',
    );
  }
  return [
    'M-PESA STATEMENT',
    'Customer Name: JOHN DOE',
    'Mobile Number: 0700 000 000',
    'Statement Period: $period',
    'DETAILED STATEMENT',
    'Receipt No. Completion Time Details Transaction Status Paid In '
        'Withdrawn Balance',
    ...lines.reversed,
    'Disclaimer: synthetic test statement, not a real record.',
    'Page 1 of 1',
  ].join('\n');
}

/// Where the M-Pesa columns sit on the synthetic pages.
const _mpesaColumns = [
  FixtureColumn(30),
  FixtureColumn(90),
  FixtureColumn(195),
  FixtureColumn(375),
  FixtureColumn(545, rightAligned: true),
  FixtureColumn(615, rightAligned: true),
  FixtureColumn(690, rightAligned: true),
];

/// [mpesaStatementText]'s statement as a page of positioned words, the way
/// the PDF extractor reports it.
List<StatementPage> mpesaStatementPages({
  List<StatementRowSample> rows = octoberRows,
  int opening = octoberOpening,
  String period = '01 Oct 2026 - 31 Oct 2026',
  Set<String> omit = const {},
}) {
  var balance = opening;
  final lines = <List<String>>[];
  for (final row in rows) {
    balance += row.amount;
    if (omit.contains(row.receipt)) continue;
    final details = _wrap(row.details, 34);
    lines.add([
      row.receipt,
      row.time,
      details.first,
      'Completed',
      row.amount > 0 ? _money(row.amount) : '',
      row.amount < 0 ? _money(row.amount) : '',
      _money(balance),
    ]);
    for (final more in details.skip(1)) {
      lines.add(['', '', more, '', '', '', '']);
    }
  }
  // Newest first, keeping each row's wrapped lines under it.
  final rowsNewestFirst = <List<List<String>>>[];
  for (final line in lines) {
    if (line.first.isEmpty) {
      rowsNewestFirst.first.add(line);
    } else {
      rowsNewestFirst.insert(0, [line]);
    }
  }
  return [
    typesetPage([
      'M-PESA STATEMENT',
      'Customer Name: JOHN DOE',
      'Statement Period: $period',
      'DETAILED STATEMENT',
      [
        'Receipt No.',
        'Completion Time',
        'Details',
        'Transaction Status',
        'Paid In',
        'Withdrawn',
        'Balance',
      ],
      for (final row in rowsNewestFirst) ...row,
      'Disclaimer: synthetic test statement, not a real record.',
      'Page 1 of 1',
    ], _mpesaColumns),
  ];
}

/// [kcbStatementText] as a page of positioned words.
List<StatementPage> kcbStatementPages() => [
  typesetPage(kcbStatementText.trim().split('\n'), const [FixtureColumn(30)]),
];

List<String> _wrap(String text, int width) {
  final lines = <String>[];
  var line = '';
  for (final word in text.split(' ')) {
    if (line.isNotEmpty && line.length + 1 + word.length > width) {
      lines.add(line);
      line = word;
    } else {
      line = line.isEmpty ? word : '$line $word';
    }
  }
  return lines..add(line);
}

/// The first lines of a synthetic KCB statement.
const kcbStatementText = '''
KCB Bank Kenya Limited
ACCOUNT STATEMENT
Account Name: JOHN DOE
Account Number: 0000000001
Date Narrative Debit Credit Balance
01/10/2026 Opening balance 10,000.00
''';

String _money(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+$)'),
    (_) => ',',
  );
  return '$sign$whole.${(abs % 100).toString().padLeft(2, '0')}';
}

/// Bytes standing in for a PDF; the fake extractor maps them to pages.
Uint8List fakePdf(String id) => Uint8List.fromList('%PDF-fake $id'.codeUnits);

/// Returns [pages] for known fake PDFs, asking for [passwords] where set.
class FakePdfTextExtractor implements PdfTextExtractor {
  FakePdfTextExtractor(this.pages, {this.passwords = const {}});

  final Map<String, List<StatementPage>> pages;
  final Map<String, String> passwords;

  /// Passwords tried, to check none are kept beyond the call.
  int attempts = 0;

  @override
  Future<List<StatementPage>> extractPages(
    Uint8List bytes, {
    String? password,
  }) async {
    attempts++;
    final id = String.fromCharCodes(bytes).replaceFirst('%PDF-fake ', '');
    final result = pages[id];
    if (result == null) throw const PdfUnreadable('unknown');
    final required = passwords[id];
    if (required != null && password != required) {
      throw password == null
          ? const PdfPasswordRequired()
          : const PdfWrongPassword();
    }
    return result;
  }
}

/// Hands out [files] in order, then null as if the person backed out.
class FakeStatementFilePicker implements StatementFilePicker {
  FakeStatementFilePicker(this.files);

  final List<PickedStatement> files;

  @override
  Future<PickedStatement?> pickPdf() async =>
      files.isEmpty ? null : files.removeAt(0);
}
