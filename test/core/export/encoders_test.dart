import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/export/csv_encoder.dart';
import 'package:pesaclarity/src/core/export/export_table.dart';
import 'package:pesaclarity/src/core/export/pdf_encoder.dart';
import 'package:pesaclarity/src/core/export/xlsx_encoder.dart';
import 'package:pesaclarity/src/core/money/money.dart';

ExportTable _table({String title = 'Transactions', int rows = 2}) =>
    ExportTable(
      title: title,
      columns: const ['Date', 'Payee', 'Amount', 'Count'],
      rows: [
        for (var i = 0; i < rows; i++)
          [
            DateTime.utc(2026, 10, 3, 6, 15),
            i.isEven ? 'John, "JK" Kamau' : '=HYPERLINK("x")',
            Money(-144050),
            i,
          ],
      ],
    );

void main() {
  group('CSV', () {
    test('quotes, escapes and writes Nairobi time and plain amounts', () {
      final text = csvText(_table());
      final lines = text.split('\r\n');
      expect(lines[0], 'Date,Payee,Amount,Count');
      expect(lines[1], '2026-10-03 09:15,"John, ""JK"" Kamau",-1440.50,0');
      expect(lines[2], startsWith("2026-10-03 09:15,\"'=HYPERLINK"));
      expect(text, endsWith('\r\n'));
    });

    test('starts with a UTF-8 byte order mark', () {
      final bytes = encodeCsv(_table());
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(bytes.skip(3).toList()), csvText(_table()));
    });

    test('empty cells stay empty', () {
      final table = ExportTable(
        title: 'T',
        columns: const ['A', 'B'],
        rows: const [
          [null, 'x'],
        ],
      );
      expect(csvText(table), 'A,B\r\n,x\r\n');
    });
  });

  test('a table rejects rows of the wrong width or cell type', () {
    expect(
      () => ExportTable(
        title: 'T',
        columns: const ['A'],
        rows: const [
          ['a', 'b'],
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => ExportTable(
        title: 'T',
        columns: const ['A'],
        rows: const [
          [1.5],
        ],
      ),
      throwsArgumentError,
    );
  });

  group('Excel', () {
    test('writes one sheet per table with numbers and dates', () {
      final bytes = encodeXlsx(
        ExportWorkbook(
          title: 'Workbook',
          tables: [
            _table(),
            _table(title: 'Tags: totals / month'),
            _table(),
          ],
        ),
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      String part(String name) =>
          utf8.decode(archive.findFile(name)!.readBytes()!);

      final workbook = part('xl/workbook.xml');
      expect(workbook, contains('name="Transactions"'));
      expect(workbook, contains('name="Tags  totals   month"'));
      expect(workbook, contains('name="Transactions (2)"'));
      expect(archive.findFile('xl/worksheets/sheet3.xml'), isNotNull);
      expect(part('[Content_Types].xml'), contains('sheet3.xml'));

      final sheet = part('xl/worksheets/sheet1.xml');
      expect(sheet, contains('<t xml:space="preserve">Payee</t>'));
      expect(sheet, contains('John, &quot;JK&quot; Kamau'));
      expect(sheet, contains('<c r="C2" s="2"><v>-1440.50</v></c>'));
      expect(sheet, contains('<c r="D3"><v>1</v></c>'));
      // 3 Oct 2026 09:15 Nairobi.
      expect(sheet, contains('<c r="A2" s="4"><v>46298.385417</v></c>'));
      expect(sheet, contains('state="frozen"'));
    });

    test('needs at least one table', () {
      expect(
        () => encodeXlsx(const ExportWorkbook(title: 'Empty', tables: [])),
        throwsArgumentError,
      );
    });

    test('Excel dates count days from 30 Dec 1899', () {
      expect(excelSerial(DateTime.utc(1899, 12, 29, 21)), '0.000000');
      expect(excelSerial(DateTime.utc(2026, 10, 2, 21)), '46298.000000');
    });
  });

  group('PDF', () {
    test('writes a document that runs over pages for long tables', () async {
      final bytes = await encodePdf(
        ExportWorkbook(
          title: 'Activity',
          tables: [
            _table(rows: 120),
            _table(title: 'Tags', rows: 0),
          ],
        ),
        createdAt: DateTime.utc(2026, 10, 26, 6),
        subtitle: '1 Oct 2026 to 31 Oct 2026',
      );
      final text = latin1.decode(bytes);
      expect(text, startsWith('%PDF-'));
      final pages = RegExp(r'/Type\s*/Page\b').allMatches(text).length;
      expect(pages, greaterThan(2));
    });

    test('handles text outside Latin-1', () async {
      final bytes = await encodePdf(
        ExportWorkbook(
          title: 'Activity',
          tables: [
            ExportTable(
              title: 'Activity',
              columns: const ['Payee'],
              rows: const [
                ['Mama Mboga \u{1F96C}'],
              ],
            ),
          ],
        ),
        createdAt: DateTime.utc(2026, 10, 26),
      );
      expect(bytes, isNotEmpty);
    });
  });
}
