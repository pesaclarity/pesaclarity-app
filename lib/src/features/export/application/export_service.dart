import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/export/csv_encoder.dart';
import '../../../core/export/export_table.dart';
import '../../../core/export/pdf_encoder.dart';
import '../../../core/export/xlsx_encoder.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/export_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/export/export_tables.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/tags/tag_totals.dart';
import '../../../domain/time/calendar.dart';

/// File formats an export can take.
enum ExportFormat {
  csv('CSV', 'csv', 'text/csv'),
  xlsx(
    'Excel',
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ),
  pdf('PDF', 'pdf', 'application/pdf');

  const ExportFormat(this.label, this.extension, this.mimeType);

  final String label;
  final String extension;
  final String mimeType;
}

/// What an export covers: the view it was started from.
sealed class ExportScope {
  const ExportScope();

  /// Shown as the file's title, such as "Activity, October 2026".
  String get title;

  /// Short name for the file, such as `activity`.
  String get fileStem;
}

/// A list of transactions, narrowed the way the view on screen is.
class TransactionsExport extends ExportScope {
  const TransactionsExport({
    required this.title,
    this.fileStem = 'transactions',
    this.from,
    this.to,
    this.tagId,
    this.accountId,
    this.payeeId,
  });

  @override
  final String title;
  @override
  final String fileStem;
  final DateTime? from;
  final DateTime? to;
  final int? tagId;
  final int? accountId;
  final int? payeeId;
}

/// Totals per tag for `[from, to)`, as Insights shows them.
class TagTotalsExport extends ExportScope {
  const TagTotalsExport({
    required this.title,
    required this.from,
    required this.to,
  });

  @override
  final String title;
  @override
  String get fileStem => 'tags';
  final DateTime from;
  final DateTime to;
}

/// Named payees with their numbers, category and leak type.
class PayeesExport extends ExportScope {
  const PayeesExport();

  @override
  String get title => 'Payees';
  @override
  String get fileStem => 'payees';
}

/// Every table: transactions, totals, payees, categories, tags and
/// accounts. As CSV it is a zip with one file per table.
class FullWorkbookExport extends ExportScope {
  const FullWorkbookExport();

  @override
  String get title => 'Pesa Clarity workbook';
  @override
  String get fileStem => 'workbook';
}

/// Hands a finished file to the phone's share sheet.
abstract interface class FileSharer {
  Future<void> share(File file, {required String mimeType, String? subject});
}

class SharePlusFileSharer implements FileSharer {
  const SharePlusFileSharer();

  @override
  Future<void> share(
    File file, {
    required String mimeType,
    String? subject,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
      ),
    );
  }
}

/// Builds exports on the phone, writes them to the app's cache and shares
/// them. Nothing is uploaded; where the file goes is up to the person.
class ExportService {
  ExportService({
    required this._exports,
    required this._ledger,
    required this._cacheDirectory,
    required this._sharer,
    required this._clock,
  });

  final ExportRepository _exports;
  final TransactionsRepository _ledger;
  final Future<Directory> Function() _cacheDirectory;
  final FileSharer _sharer;
  final DateTime Function() _clock;

  static final _allTimeFrom = DateTime.utc(1970);
  static final _allTimeTo = DateTime.utc(9999);

  /// The tables [scope] exports, the main one first.
  Future<ExportWorkbook> workbookFor(ExportScope scope) async {
    switch (scope) {
      case TransactionsExport():
        final from = scope.from ?? _allTimeFrom;
        final to = scope.to ?? _allTimeTo;
        final entries =
            (await _ledger.ledgerEntries(
              from: from,
              to: to,
              tagId: scope.tagId,
            )).where(
              (e) =>
                  (scope.accountId == null || e.accountId == scope.accountId) &&
                  (scope.payeeId == null || e.payeeId == scope.payeeId),
            );
        return ExportWorkbook(
          title: scope.title,
          tables: [
            transactionsTable(
              await _exports.transactions(
                from: scope.from,
                to: scope.to,
                tagId: scope.tagId,
                accountId: scope.accountId,
                payeeId: scope.payeeId,
              ),
            ),
            ...await _totals(entries, from: from, to: to),
          ],
        );
      case TagTotalsExport():
        final entries = await _ledger.ledgerEntries(
          from: scope.from,
          to: scope.to,
        );
        final totals = tagTotals(entries, from: scope.from, to: scope.to);
        final tagNames = await _exports.tagNames();
        return ExportWorkbook(
          title: scope.title,
          tables: [
            tagTotalsTable(totals, tagNames),
            tagCategoryTable(totals, tagNames, await _exports.categoryNames()),
          ],
        );
      case PayeesExport():
        return ExportWorkbook(
          title: scope.title,
          tables: [payeesTable(await _exports.payees())],
        );
      case FullWorkbookExport():
        final entries = await _ledger.ledgerEntries(
          from: _allTimeFrom,
          to: _allTimeTo,
        );
        final totals = tagTotals(entries, from: _allTimeFrom, to: _allTimeTo);
        final tagNames = await _exports.tagNames();
        final categoryNames = await _exports.categoryNames();
        return ExportWorkbook(
          title: scope.title,
          tables: [
            transactionsTable(await _exports.transactions()),
            categorySpendingTable(
              spendingByCategory(entries, from: _allTimeFrom, to: _allTimeTo),
              categoryNames,
            ),
            tagTotalsTable(totals, tagNames),
            tagCategoryTable(totals, tagNames, categoryNames),
            payeesTable(await _exports.payees()),
            categoriesTable(await _exports.categories()),
            tagsListTable(await _exports.tags()),
            accountsTable(await _exports.accounts()),
          ],
        );
    }
  }

  Future<List<ExportTable>> _totals(
    Iterable<LedgerEntry> entries, {
    required DateTime from,
    required DateTime to,
  }) async {
    final tagNames = await _exports.tagNames();
    return [
      categorySpendingTable(
        spendingByCategory(entries, from: from, to: to),
        await _exports.categoryNames(),
      ),
      tagTotalsTable(tagTotals(entries, from: from, to: to), tagNames),
    ];
  }

  /// Writes [scope] as [format] to the export folder in the app's cache,
  /// replacing earlier exports, and returns the file.
  Future<File> write(ExportScope scope, ExportFormat format) async {
    final workbook = await workbookFor(scope);
    final now = _clock();
    final bytes = switch (format) {
      ExportFormat.csv when scope is FullWorkbookExport => _csvZip(workbook),
      ExportFormat.csv => encodeCsv(workbook.tables.first),
      ExportFormat.xlsx => encodeXlsx(workbook),
      ExportFormat.pdf => await encodePdf(
        workbook,
        createdAt: now,
        subtitle: _subtitle(scope),
      ),
    };
    final extension = format == ExportFormat.csv && scope is FullWorkbookExport
        ? 'zip'
        : format.extension;
    final folder = Directory(p.join((await _cacheDirectory()).path, 'exports'));
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    folder.createSync(recursive: true);
    final file = File(
      p.join(
        folder.path,
        'pesaclarity-${scope.fileStem}-${CalendarDate.nairobi(now)}.$extension',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// [write], then opens the share sheet with the file.
  Future<File> share(ExportScope scope, ExportFormat format) async {
    final file = await write(scope, format);
    final isZip = file.path.endsWith('.zip');
    await _sharer.share(
      file,
      mimeType: isZip ? 'application/zip' : format.mimeType,
      subject: scope.title,
    );
    return file;
  }

  Uint8List _csvZip(ExportWorkbook workbook) {
    final archive = Archive();
    final used = <String>{};
    for (final table in workbook.tables) {
      var name = table.title.toLowerCase().replaceAll(
        RegExp('[^a-z0-9]+'),
        '-',
      );
      while (!used.add(name)) {
        name = '$name-2';
      }
      archive.add(ArchiveFile.bytes('$name.csv', encodeCsv(table)));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  String? _subtitle(ExportScope scope) => switch (scope) {
    TransactionsExport(:final from, :final to)
        when from != null && to != null =>
      periodLabel(from, to),
    TagTotalsExport(:final from, :final to) => periodLabel(from, to),
    TransactionsExport() || FullWorkbookExport() => 'All transactions',
    PayeesExport() => null,
  };
}

/// `[from, to)` as dates, for example `1 Oct 2026 to 31 Oct 2026`.
String periodLabel(DateTime from, DateTime to) {
  final first = CalendarDate.nairobi(from);
  final last = CalendarDate.nairobi(to).addDays(-1);
  return '${dateLabel(first)} to ${dateLabel(last)}';
}

/// A date as the app writes it, for example `3 Oct 2026`.
String dateLabel(CalendarDate date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Where exports are written: the app's cache, cleared by the system as
/// needed and readable by no other app until shared.
final exportCacheDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => getTemporaryDirectory,
);

final fileSharerProvider = Provider<FileSharer>(
  (ref) => const SharePlusFileSharer(),
);

final exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(
    exports: ref.watch(exportRepositoryProvider),
    ledger: ref.watch(transactionsRepositoryProvider),
    cacheDirectory: ref.watch(exportCacheDirectoryProvider),
    sharer: ref.watch(fileSharerProvider),
    clock: ref.watch(clockProvider),
  ),
);
