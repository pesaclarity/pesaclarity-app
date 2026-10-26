import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/export_repository.dart';
import 'package:pesaclarity/src/data/repositories/tags_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/features/export/application/export_service.dart';

class RecordingSharer implements FileSharer {
  final shared = <(String, String)>[];

  @override
  Future<void> share(
    File file, {
    required String mimeType,
    String? subject,
  }) async => shared.add((file.path, mimeType));
}

void main() {
  late AppDatabase db;
  late Directory cache;
  late RecordingSharer sharer;
  late ExportService service;
  late int trip;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    cache = Directory.systemTemp.createTempSync('export_test');
    sharer = RecordingSharer();
    final ledger = DriftTransactionsRepository(db);
    service = ExportService(
      exports: DriftExportRepository(db),
      ledger: ledger,
      cacheDirectory: () async => cache,
      sharer: sharer,
      clock: () => DateTime.utc(2026, 10, 26, 6),
    );
    final account = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: DateTime.utc(2026),
          ),
        );
    final tags = DriftTagsRepository(db);
    trip = await tags.findOrCreate('roadtrip');
    for (final (day, amount) in [(3, 120000), (5, 45000), (9, 80000)]) {
      final id = await ledger.add(
        TransactionsCompanion.insert(
          accountId: account,
          occurredAt: DateTime.utc(2026, 10, day, 9),
          amountMinor: amount,
          direction: TransactionDirection.outflow,
          kind: const Value(TransactionKind.till),
          source: TransactionSource.sms,
          counterpartyName: const Value('TOTAL NAIVASHA'),
        ),
      );
      if (day != 9) await tags.tag(id, trip);
    }
  });

  tearDown(() async {
    await db.close();
    cache.deleteSync(recursive: true);
  });

  test(
    'a filtered view exports as CSV with tags, Uncategorised counted',
    () async {
      final file = await service.share(
        TransactionsExport(title: 'Activity, #roadtrip', tagId: trip),
        ExportFormat.csv,
      );
      expect(file.path, endsWith('pesaclarity-transactions-2026-10-26.csv'));
      expect(file.parent.path, '${cache.path}/exports');
      expect(sharer.shared.single, (file.path, 'text/csv'));
      final lines = utf8.decode(file.readAsBytesSync().skip(3).toList()).trim();
      final rows = lines.split('\r\n');
      expect(rows, hasLength(3));
      expect(rows[1], contains('#roadtrip'));
      expect(rows[1], contains('Uncategorised'));
      expect(rows[1], contains('1200.00'));
    },
  );

  test('the Excel export adds totals sheets for the same view', () async {
    final workbook = await service.workbookFor(
      TransactionsExport(title: 'Activity', tagId: trip),
    );
    expect(workbook.tables.map((t) => t.title), [
      'Transactions',
      'Spending by category',
      'Tags',
    ]);
    final byCategory = workbook.tables[1];
    expect(byCategory.rows.first[0], 'Uncategorised');
    expect(byCategory.rows.last[1].toString(), contains('165000'));
  });

  test('the full workbook holds every table', () async {
    final workbook = await service.workbookFor(const FullWorkbookExport());
    expect(workbook.tables.map((t) => t.title), [
      'Transactions',
      'Spending by category',
      'Tags',
      'Tag spending by category',
      'Payees',
      'Categories',
      'Tag list',
      'Accounts',
    ]);
    expect(workbook.tables.first.rows, hasLength(3));

    final xlsx = await service.write(
      const FullWorkbookExport(),
      ExportFormat.xlsx,
    );
    final sheets = ZipDecoder()
        .decodeBytes(xlsx.readAsBytesSync())
        .files
        .where((f) => f.name.startsWith('xl/worksheets/'));
    expect(sheets, hasLength(8));

    final zip = await service.share(
      const FullWorkbookExport(),
      ExportFormat.csv,
    );
    expect(zip.path, endsWith('.zip'));
    expect(sharer.shared.last.$2, 'application/zip');
    expect(
      ZipDecoder().decodeBytes(zip.readAsBytesSync()).files.map((f) => f.name),
      contains('tag-spending-by-category.csv'),
    );
    expect(xlsx.existsSync(), isFalse, reason: 'old exports are cleared');
  });

  test('tag totals and PDFs export too', () async {
    final file = await service.share(
      TagTotalsExport(
        title: 'Tags, October 2026',
        from: DateTime.utc(2026, 9, 30, 21),
        to: DateTime.utc(2026, 10, 31, 21),
      ),
      ExportFormat.pdf,
    );
    expect(file.path, endsWith('pesaclarity-tags-2026-10-26.pdf'));
    expect(latin1.decode(file.readAsBytesSync().take(5).toList()), '%PDF-');
    expect(sharer.shared.single.$2, 'application/pdf');
  });

  test('periods read as dates', () {
    expect(
      periodLabel(
        DateTime.utc(2026, 9, 30, 21),
        DateTime.utc(2026, 10, 31, 21),
      ),
      '1 Oct 2026 to 31 Oct 2026',
    );
  });
}
