import 'dart:convert';

import '../money/money.dart';
import 'export_table.dart';

/// Writes [table] as CSV (RFC 4180): comma separated, CRLF line ends, UTF-8
/// with a byte order mark so Excel reads Swahili and other accents right.
List<int> encodeCsv(ExportTable table) => [
  0xEF,
  0xBB,
  0xBF,
  ...utf8.encode(csvText(table)),
];

/// The CSV text of [table], without the byte order mark.
String csvText(ExportTable table) {
  final buffer = StringBuffer();
  void writeRow(Iterable<String> cells) {
    buffer
      ..writeAll(cells.map(_quote), ',')
      ..write('\r\n');
  }

  writeRow(table.columns.map(_safeText));
  for (final row in table.rows) {
    writeRow(row.map(_cell));
  }
  return buffer.toString();
}

String _cell(Object? cell) => switch (cell) {
  null => '',
  final String s => _safeText(s),
  final int n => n.toString(),
  final Money m => plainDecimal(m),
  final DateTime d => nairobiTimestamp(d),
  _ => throw ArgumentError.value(cell, 'cell'),
};

/// Text from messages (payee names, references) could start like a formula;
/// a leading apostrophe keeps spreadsheet apps from running it.
String _safeText(String s) =>
    s.isNotEmpty && '=+-@\t\r'.contains(s[0]) ? "'$s" : s;

String _quote(String s) =>
    s.contains(RegExp('[",\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
