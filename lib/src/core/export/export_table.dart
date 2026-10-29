import '../../domain/time/calendar.dart';
import '../money/money.dart';

/// One sheet of an export: a title, column headings and rows.
///
/// A cell is a [String], an [int], a [Money], a [DateTime] (an instant, shown
/// in Nairobi time) or null for empty. Each encoder writes these in the form
/// its format handles best, such as real numbers and dates in Excel.
class ExportTable {
  ExportTable({
    required this.title,
    required this.columns,
    required List<List<Object?>> rows,
  }) : rows = List.unmodifiable(rows) {
    for (final row in this.rows) {
      if (row.length != columns.length) {
        throw ArgumentError('Each row needs ${columns.length} cells');
      }
      for (final cell in row) {
        if (cell != null &&
            cell is! String &&
            cell is! int &&
            cell is! Money &&
            cell is! DateTime) {
          throw ArgumentError.value(cell, 'cell', 'unsupported type');
        }
      }
    }
  }

  /// Sheet name and PDF heading, such as "Transactions".
  final String title;
  final List<String> columns;
  final List<List<Object?>> rows;
}

/// Several tables saved together, such as the full workbook.
class ExportWorkbook {
  const ExportWorkbook({required this.title, required this.tables});

  final String title;
  final List<ExportTable> tables;
}

/// [instant] as Nairobi wall-clock time, for example `2026-10-03 09:15`.
String nairobiTimestamp(DateTime instant) =>
    formatTimestamp(instant, offset: nairobiUtcOffset);

/// [money] as a plain decimal with no grouping, for example `-1440.50`.
String plainDecimal(Money money) {
  final digits = minorUnitDigits(money.currency);
  final absolute = money.minorUnits.abs();
  if (digits == 0) return money.minorUnits.toString();
  var divisor = 1;
  for (var i = 0; i < digits; i++) {
    divisor *= 10;
  }
  final sign = money.isNegative ? '-' : '';
  final minor = (absolute % divisor).toString().padLeft(digits, '0');
  return '$sign${absolute ~/ divisor}.$minor';
}
