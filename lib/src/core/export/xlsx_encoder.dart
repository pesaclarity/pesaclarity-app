import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../domain/time/calendar.dart';
import '../money/money.dart';
import 'export_table.dart';

/// Writes [workbook] as an Excel workbook (.xlsx), one sheet per table.
///
/// Amounts are real numbers and times real Excel dates, so they sort and add
/// up in any spreadsheet app. The header row is bold and stays in view.
Uint8List encodeXlsx(ExportWorkbook workbook) {
  if (workbook.tables.isEmpty) {
    throw ArgumentError.value(workbook, 'workbook', 'needs a table');
  }
  final names = _sheetNames(workbook.tables.map((t) => t.title));
  final archive = Archive()
    ..add(_xml('[Content_Types].xml', _contentTypes(names.length)))
    ..add(_xml('_rels/.rels', _rootRels))
    ..add(_xml('xl/workbook.xml', _workbookXml(names)))
    ..add(_xml('xl/_rels/workbook.xml.rels', _workbookRels(names.length)))
    ..add(_xml('xl/styles.xml', _styles));
  for (var i = 0; i < workbook.tables.length; i++) {
    archive.add(
      _xml('xl/worksheets/sheet${i + 1}.xml', _sheetXml(workbook.tables[i])),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

ArchiveFile _xml(String name, String content) =>
    ArchiveFile.bytes(name, utf8.encode(content));

/// Excel sheet names: at most 31 characters, none of `[]:*?/\`, unique.
List<String> _sheetNames(Iterable<String> titles) {
  final used = <String>{};
  return [
    for (final title in titles)
      () {
        var base = title.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
        if (base.isEmpty) base = 'Sheet';
        if (base.length > 31) base = base.substring(0, 31);
        var name = base;
        for (var n = 2; used.contains(name.toLowerCase()); n++) {
          final suffix = ' ($n)';
          name =
              '${base.substring(0, base.length.clamp(0, 31 - suffix.length))}'
              '$suffix';
        }
        used.add(name.toLowerCase());
        return name;
      }(),
  ];
}

const _header = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const _mainNs = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _relNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

String _contentTypes(int sheets) {
  final b = StringBuffer(_header)
    ..write(
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
      'content-types">'
      '<Default Extension="rels" ContentType="application/'
      'vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/'
      'vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/'
      'vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>',
    );
  for (var i = 1; i <= sheets; i++) {
    b.write(
      '<Override PartName="/xl/worksheets/sheet$i.xml" '
      'ContentType="application/'
      'vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
    );
  }
  b.write('</Types>');
  return b.toString();
}

const _rootRels =
    '$_header<Relationships xmlns="http://schemas.openxmlformats.org/package/'
    '2006/relationships"><Relationship Id="rId1" Type="$_relNs/'
    'officeDocument" Target="xl/workbook.xml"/></Relationships>';

String _workbookXml(List<String> names) {
  final b = StringBuffer(_header)
    ..write('<workbook xmlns="$_mainNs" xmlns:r="$_relNs"><sheets>');
  for (var i = 0; i < names.length; i++) {
    b.write(
      '<sheet name="${_escape(names[i])}" sheetId="${i + 1}" '
      'r:id="rId${i + 1}"/>',
    );
  }
  b.write('</sheets></workbook>');
  return b.toString();
}

String _workbookRels(int sheets) {
  final b = StringBuffer(_header)
    ..write(
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
      'relationships">',
    );
  for (var i = 1; i <= sheets; i++) {
    b.write(
      '<Relationship Id="rId$i" Type="$_relNs/worksheet" '
      'Target="worksheets/sheet$i.xml"/>',
    );
  }
  b.write(
    '<Relationship Id="rId${sheets + 1}" Type="$_relNs/styles" '
    'Target="styles.xml"/></Relationships>',
  );
  return b.toString();
}

// Cell styles by index: 0 plain, 1 bold header, 2 money with cents, 3 money
// in whole units, 4 date and time.
const _styleHeader = 1;
const _styleMoney = 2;
const _styleWholeMoney = 3;
const _styleDate = 4;

const _styles =
    '$_header<styleSheet xmlns="$_mainNs">'
    '<numFmts count="3">'
    '<numFmt numFmtId="164" formatCode="#,##0.00"/>'
    '<numFmt numFmtId="165" formatCode="#,##0"/>'
    '<numFmt numFmtId="166" formatCode="yyyy-mm-dd hh:mm"/>'
    '</numFmts>'
    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/>'
    '</border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" '
    'borderId="0"/></cellStyleXfs>'
    '<cellXfs count="5">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" '
    'applyFont="1"/>'
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" '
    'applyNumberFormat="1"/>'
    '<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" '
    'applyNumberFormat="1"/>'
    '<xf numFmtId="166" fontId="0" fillId="0" borderId="0" xfId="0" '
    'applyNumberFormat="1"/>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/>'
    '</cellStyles></styleSheet>';

String _sheetXml(ExportTable table) {
  final b = StringBuffer(_header)
    ..write('<worksheet xmlns="$_mainNs" xmlns:r="$_relNs">')
    ..write(
      '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" '
      'topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
      '</sheetView></sheetViews>',
    )
    ..write('<cols>');
  for (var c = 0; c < table.columns.length; c++) {
    b.write(
      '<col min="${c + 1}" max="${c + 1}" '
      'width="${_columnWidth(table, c)}" customWidth="1"/>',
    );
  }
  b
    ..write('</cols><sheetData>')
    ..write('<row r="1">');
  for (var c = 0; c < table.columns.length; c++) {
    b.write(_textCell('${_column(c)}1', table.columns[c], _styleHeader));
  }
  b.write('</row>');
  for (var r = 0; r < table.rows.length; r++) {
    final rowNumber = r + 2;
    b.write('<row r="$rowNumber">');
    final row = table.rows[r];
    for (var c = 0; c < row.length; c++) {
      final ref = '${_column(c)}$rowNumber';
      b.write(switch (row[c]) {
        null => '',
        final String s => _textCell(ref, s, 0),
        final int n => '<c r="$ref"><v>$n</v></c>',
        final Money m =>
          '<c r="$ref" s="${minorUnitDigits(m.currency) == 0 ? _styleWholeMoney : _styleMoney}">'
              '<v>${plainDecimal(m)}</v></c>',
        final DateTime d =>
          '<c r="$ref" s="$_styleDate"><v>${excelSerial(d)}</v></c>',
        final other => throw ArgumentError.value(other, 'cell'),
      });
    }
    b.write('</row>');
  }
  b.write('</sheetData></worksheet>');
  return b.toString();
}

String _textCell(String ref, String text, int style) =>
    '<c r="$ref" t="inlineStr"${style == 0 ? '' : ' s="$style"'}>'
    '<is><t xml:space="preserve">${_escape(text)}</t></is></c>';

int _columnWidth(ExportTable table, int column) {
  var longest = table.columns[column].length;
  for (final row in table.rows.take(200)) {
    final cell = row[column];
    final length = switch (cell) {
      null => 0,
      final String s => s.length,
      final DateTime _ => 16,
      final Money m => plainDecimal(m).length + 3,
      _ => cell.toString().length,
    };
    if (length > longest) longest = length;
  }
  return (longest + 2).clamp(8, 50);
}

/// `A` for 0, `Z` for 25, `AA` for 26.
String _column(int index) {
  var column = '';
  for (var n = index + 1; n > 0; n = (n - 1) ~/ 26) {
    column = String.fromCharCode(65 + (n - 1) % 26) + column;
  }
  return column;
}

/// [instant] in Nairobi time as an Excel date serial (days since 1899-12-30).
String excelSerial(DateTime instant) {
  final local = instant.toUtc().add(nairobiUtcOffset);
  final epoch = DateTime.utc(1899, 12, 30);
  final wall = DateTime.utc(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
    local.second,
  );
  final seconds = wall.difference(epoch).inSeconds;
  final days = seconds / Duration.secondsPerDay;
  return days.toStringAsFixed(6);
}

String _escape(String s) => s
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
