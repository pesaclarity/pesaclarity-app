import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/review_inbox_repository.dart';
import 'package:pesaclarity/src/data/repositories/statement_imports_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/statements/application/statement_importer.dart';

import '../../helpers/sms_samples.dart';
import '../../helpers/statement_samples.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late FakePdfTextExtractor extractor;
  late StatementImporter importer;

  setUp(() {
    db = openTestDatabase();
    extractor = FakePdfTextExtractor(
      {
        'october': mpesaStatementText(),
        'locked': mpesaStatementText(),
        'missing-row': mpesaStatementText(omit: {'TJA0000004'}),
        'kcb': kcbStatementText,
        'invoice': 'Invoice 001\nTotal due 1,000.00',
      },
      passwords: {'locked': '0000'},
    );
    importer = StatementImporter(
      extractor: extractor,
      accounts: DriftAccountsRepository(db),
      transactions: DriftTransactionsRepository(db),
      imports: DriftStatementImportsRepository(db),
      institutions: institutionCatalogue,
      now: () => DateTime.utc(2026, 11, 2, 9),
    );
  });

  Future<List<TransactionRecord>> transactions() => (db.select(
    db.transactions,
  )..orderBy([(t) => OrderingTerm.asc(t.occurredAt)])).get();

  Future<void> captureSms() => SmsIngestor(
    accounts: DriftAccountsRepository(db),
    transactions: DriftTransactionsRepository(db),
    reviewInbox: DriftReviewInboxRepository(db),
    parse: (packs, messages) async => parseAll(packs, messages),
  ).ingest([mpesaSent(), mpesaTill()], institutionCatalogue);

  test('imports a statement into the M-Pesa account and reconciles', () async {
    final outcome = await importer.importPdf(fakePdf('october'));

    final summary = (outcome as StatementImported).summary;
    expect(summary.institutionName, 'M-Pesa');
    expect(summary.firstDay, CalendarDate(2026, 10, 1));
    expect(summary.lastDay, CalendarDate(2026, 10, 31));
    expect(summary.transactionCount, 4, reason: 'the charge folds in');
    expect(summary.addedCount, 4);
    expect(summary.duplicateCount, 0);
    expect(summary.closingBalanceMinor, octoberClosing);
    expect(summary.gapMinor, 0);
    expect(summary.reconciles, isTrue);

    final rows = await transactions();
    expect(rows.map((r) => r.source).toSet(), {TransactionSource.statement});
    final transfer = rows.singleWhere((r) => r.receiptNo == 'TJA0000001');
    expect(transfer.amountMinor, 150000);
    expect(transfer.feeMinor, 1500);

    final account = await db.select(db.accounts).getSingle();
    expect(account.institutionId, 'mpesa');
    expect(account.openingBalanceMinor, octoberOpening);
    expect(account.openingDate.toUtc(), CalendarDate(2026, 10, 1).startInstant);

    final record = await db.select(db.imports).getSingle();
    expect(record.institutionId, 'mpesa');
    expect(record.transactionCount, 4);
    expect(record.addedCount, 4);
    expect(record.openingBalanceMinor, octoberOpening);
    expect(record.closingBalanceMinor, octoberClosing);
    expect(record.reconciliationGapMinor, 0);
    expect(record.result, StatementImportResult.reconciled);
    expect(record.periodStart.toUtc(), DateTime.utc(2026, 10));
    expect(record.periodEnd.toUtc(), DateTime.utc(2026, 10, 31));
  });

  test('transactions already captured from SMS are counted once', () async {
    await captureSms();
    expect(await transactions(), hasLength(2));

    final outcome = await importer.importPdf(fakePdf('october'));

    final summary = (outcome as StatementImported).summary;
    expect(summary.addedCount, 2);
    expect(summary.duplicateCount, 2);
    expect(summary.gapMinor, 0);
    final rows = await transactions();
    expect(rows, hasLength(4));
    expect(
      rows
          .where((r) => r.source == TransactionSource.sms)
          .map((r) => r.receiptNo),
      unorderedEquals(['TJA0000001', 'TJA0000004']),
    );
  });

  test('the same file imported twice is recognised', () async {
    await importer.importPdf(fakePdf('october'));
    final again = await importer.importPdf(fakePdf('october'));

    final summary = (again as StatementAlreadyImported).summary;
    expect(summary.importedAt.toUtc(), DateTime.utc(2026, 11, 2, 9));
    expect(summary.addedCount, 4);
    expect(summary.institutionName, 'M-Pesa');
    expect(await transactions(), hasLength(4));
    expect(await db.select(db.imports).get(), hasLength(1));
    expect(extractor.attempts, 1, reason: 'a known file is not read again');
  });

  test('asks for the password of an encrypted statement', () async {
    expect(
      await importer.importPdf(fakePdf('locked')),
      isA<StatementNeedsPassword>().having(
        (o) => o.wrongPassword,
        'wrongPassword',
        isFalse,
      ),
    );
    expect(
      await importer.importPdf(fakePdf('locked'), password: '1111'),
      isA<StatementNeedsPassword>().having(
        (o) => o.wrongPassword,
        'wrongPassword',
        isTrue,
      ),
    );
    expect(
      await importer.importPdf(fakePdf('locked'), password: '0000'),
      isA<StatementImported>(),
    );
  });

  test('shows the gap when a row is missing from the text', () async {
    final outcome = await importer.importPdf(fakePdf('missing-row'));

    final summary = (outcome as StatementImported).summary;
    expect(summary.transactionCount, 3);
    expect(summary.unreadCount, 1, reason: 'one balance does not follow');
    expect(summary.gapMinor, -35000);
    expect(
      (await db.select(db.imports).getSingle()).result,
      StatementImportResult.gap,
    );
  });

  test('a bank statement is coming soon and changes nothing', () async {
    final outcome = await importer.importPdf(fakePdf('kcb'));

    expect((outcome as StatementComingSoon).bankName, 'KCB');
    expect(await transactions(), isEmpty);
    expect(await db.select(db.imports).get(), isEmpty);
  });

  test('other files are not read', () async {
    expect(
      await importer.importPdf(fakePdf('invoice')),
      isA<StatementNotRead>().having((o) => o.isPdf, 'isPdf', isTrue),
    );
    expect(
      await importer.importPdf(fakePdf('not-a-pdf')),
      isA<StatementNotRead>().having((o) => o.isPdf, 'isPdf', isFalse),
    );
    expect(await db.select(db.imports).get(), isEmpty);
  });
}
