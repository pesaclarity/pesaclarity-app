import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/statement_imports_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/statements/reconciliation.dart';
import '../../../domain/statements/statement_dedupe.dart';
import '../../../domain/statements/statement_type.dart';
import '../../../domain/time/calendar.dart';
import '../../accounts/domain/institution.dart';
import '../../sms/application/transaction_mapping.dart';
import '../data/pdf_text_extractor.dart';

/// What an import did, or what an earlier import of the same file did.
@immutable
class StatementImportSummary {
  const StatementImportSummary({
    required this.institutionName,
    required this.firstDay,
    required this.lastDay,
    required this.transactionCount,
    required this.addedCount,
    required this.duplicateCount,
    required this.unreadCount,
    required this.closingBalanceMinor,
    required this.gapMinor,
    required this.importedAt,
  });

  factory StatementImportSummary.fromRecord(
    Import record, {
    required String institutionName,
  }) => StatementImportSummary(
    institutionName: institutionName,
    firstDay: _dayOf(record.periodStart),
    lastDay: _dayOf(record.periodEnd),
    transactionCount: record.transactionCount,
    addedCount: record.addedCount,
    duplicateCount: record.duplicateCount,
    unreadCount: record.unreadCount,
    closingBalanceMinor: record.closingBalanceMinor,
    gapMinor: record.reconciliationGapMinor ?? 0,
    importedAt: record.importedAt,
  );

  final String institutionName;

  /// First and last days of the statement period.
  final CalendarDate firstDay;
  final CalendarDate lastDay;

  /// Transactions read from the statement.
  final int transactionCount;

  /// New to the ledger.
  final int addedCount;

  /// Already captured from SMS.
  final int duplicateCount;

  /// Lines that could not be read, plus balances that did not follow.
  final int unreadCount;
  final int? closingBalanceMinor;

  /// Statement closing balance minus the ledger's; zero when it reconciles.
  final int gapMinor;
  final DateTime importedAt;

  bool get reconciles => gapMinor == 0;
}

/// The result of trying to import a statement file.
sealed class StatementImportOutcome {
  const StatementImportOutcome();
}

/// The statement was read and its transactions added.
final class StatementImported extends StatementImportOutcome {
  const StatementImported(this.summary);

  final StatementImportSummary summary;
}

/// The same file was imported before; nothing was added.
final class StatementAlreadyImported extends StatementImportOutcome {
  const StatementAlreadyImported(this.summary);

  final StatementImportSummary summary;
}

/// The PDF is encrypted; [wrongPassword] when a password was tried.
final class StatementNeedsPassword extends StatementImportOutcome {
  const StatementNeedsPassword({required this.wrongPassword});

  final bool wrongPassword;
}

/// A PDF with no text on any page, such as a scanned or photographed
/// statement.
final class StatementHasNoText extends StatementImportOutcome {
  const StatementHasNoText();
}

/// A bank statement whose reader is not built yet.
final class StatementComingSoon extends StatementImportOutcome {
  const StatementComingSoon(this.bankName);

  final String bankName;
}

/// The file is not a statement the app recognises, or holds no
/// transactions it could read.
final class StatementNotRead extends StatementImportOutcome {
  const StatementNotRead({required this.isPdf});

  /// False when the file could not be opened as a PDF at all.
  final bool isPdf;
}

/// A statement read with its statement pack, as plain values that can
/// cross isolates.
@immutable
class StatementRead {
  const StatementRead({
    required this.institutionId,
    required this.periodStart,
    required this.periodEnd,
    required this.transactions,
    required this.openingBalanceMinor,
    required this.closingBalanceMinor,
    required this.unreadCount,
  });

  /// The institution's id, e.g. `mpesa`.
  final String institutionId;

  /// First and last day of the period, at midnight UTC, if printed.
  final DateTime? periodStart, periodEnd;

  /// Completed rows, oldest first.
  final List<ParsedTransaction> transactions;
  final int? openingBalanceMinor, closingBalanceMinor;

  /// Rows that could not be read, plus balances that did not follow.
  final int unreadCount;
}

/// Finds the statement pack for [pages] and reads them, or returns null
/// when no pack recognises the statement.
typedef StatementReadBatch = Future<StatementRead?> Function(
  List<StatementPage> pages,
);

/// Reads on a background isolate so a long statement never blocks the UI.
Future<StatementRead?> readStatementInBackground(List<StatementPage> pages) =>
    Isolate.run(() => readStatement(pages));

/// Reads [pages] with the bundled statement packs, on the calling isolate.
StatementRead? readStatement(List<StatementPage> pages) {
  final pack = detectStatementPack(pages, loadBundledStatementPacks());
  if (pack == null) return null;
  final read = StatementReader(pack).read(pages);
  return StatementRead(
    institutionId: pack.institution,
    periodStart: read.periodStart,
    periodEnd: read.periodEnd,
    transactions: read.transactions,
    openingBalanceMinor: read.openingBalanceMinor,
    closingBalanceMinor: read.closingBalanceMinor,
    unreadCount: read.unreadLines.length + read.balanceBreaks.length,
  );
}

/// Imports statement PDFs: reads them on the phone, adds the transactions
/// SMS missed, and checks the ledger against the closing balance.
class StatementImporter {
  StatementImporter({
    required this._extractor,
    required this._read,
    required this._accounts,
    required this._transactions,
    required this._imports,
    required this._institutions,
    required this._now,
  });

  final PdfTextExtractor _extractor;
  final StatementReadBatch _read;
  final AccountsRepository _accounts;
  final TransactionsRepository _transactions;
  final StatementImportsRepository _imports;
  final List<Institution> _institutions;
  final DateTime Function() _now;

  /// SHA-256 of [bytes], which identifies a statement file.
  static String hashOf(Uint8List bytes) => sha256.convert(bytes).toString();

  /// Imports the PDF [bytes]. [password], for an encrypted PDF, goes
  /// straight to the PDF engine and is not kept.
  Future<StatementImportOutcome> importPdf(
    Uint8List bytes, {
    String? password,
  }) async {
    final fileHash = hashOf(bytes);
    final earlier = await _imports.findByHash(fileHash);
    if (earlier != null) {
      return StatementAlreadyImported(_summaryOf(earlier));
    }
    final List<StatementPage> pages;
    try {
      pages = await _extractor.extractPages(bytes, password: password);
    } on PdfPasswordRequired {
      return const StatementNeedsPassword(wrongPassword: false);
    } on PdfWrongPassword {
      return const StatementNeedsPassword(wrongPassword: true);
    } on PdfUnreadable {
      return const StatementNotRead(isPdf: false);
    }
    if (pages.every((page) => page.words.isEmpty)) {
      return const StatementHasNoText();
    }
    return importPages(pages, fileHash: fileHash);
  }

  /// Imports the statement [pages] extracted from the file with [fileHash].
  Future<StatementImportOutcome> importPages(
    List<StatementPage> pages, {
    required String fileHash,
  }) async {
    final read = await _read(pages);
    if (read != null) return _importRead(read, fileHash);
    // No statement pack reads it yet: name the bank if the header does.
    final firstPage = pages.isEmpty ? '' : pages.first.text;
    return switch (detectStatementType(firstPage)) {
      BankStatementType(:final bankName) => StatementComingSoon(bankName),
      _ => const StatementNotRead(isPdf: true),
    };
  }

  Future<StatementImportOutcome> _importRead(
    StatementRead statement,
    String fileHash,
  ) async {
    final parsed = statement.transactions;
    final opening = statement.openingBalanceMinor;
    final closing = statement.closingBalanceMinor;
    if (parsed.isEmpty || opening == null || closing == null) {
      return const StatementNotRead(isPdf: true);
    }

    final firstDay = _earlier(
      statement.periodStart,
      CalendarDate.nairobi(parsed.first.time),
    );
    final lastDay = _later(
      statement.periodEnd,
      CalendarDate.nairobi(parsed.last.time),
    );
    final from = firstDay.startInstant;
    final to = lastDay.addDays(1).startInstant;

    final institutionId = statement.institutionId;
    final institution = _institution(institutionId);
    if (institution == null) return const StatementNotRead(isPdf: true);
    final accountId = await _accounts.accountForInstitution(
      institutionId,
      name: institution.name,
      type: institution.type,
      openingDate: from,
    );

    final nearby = await _imports.transactionsBetween(
      accountId,
      from: from.subtract(defaultDedupeWindow),
      to: to.add(defaultDedupeWindow),
    );
    final matches = matchStatementLines(
      [for (final p in parsed) _fieldsOfParsed(p)],
      [for (final t in nearby) LedgerCandidate(t.id, _fieldsOfRecord(t))],
    );
    final added = await _transactions.addNew([
      for (var i = 0; i < parsed.length; i++)
        if (matches[i] == null)
          transactionFromParsed(
            parsed[i],
            accountId: accountId,
          ).copyWith(source: const Value(TransactionSource.statement)),
    ]);
    await _imports.openEarlier(accountId, balanceMinor: opening, at: from);

    final inPeriod = await _imports.transactionsBetween(
      accountId,
      from: from,
      to: to,
    );
    final reconciliation = Reconciliation.of(
      openingBalanceMinor: opening,
      closingBalanceMinor: closing,
      moves: [
        for (final t in inPeriod)
          BalanceMove(
            amountMinor: t.amountMinor,
            direction: t.direction,
            feeMinor: t.feeMinor,
          ),
      ],
    );

    final unread = statement.unreadCount;
    final now = _now();
    await _imports.record(
      ImportsCompanion.insert(
        accountId: accountId,
        fileHash: fileHash,
        periodStart: _utcMidnight(firstDay),
        periodEnd: _utcMidnight(lastDay),
        importedAt: now,
        closingBalanceMinor: Value(closing),
        reconciliationGapMinor: Value(reconciliation.gapMinor),
        institutionId: Value(institutionId),
        openingBalanceMinor: Value(opening),
        transactionCount: Value(parsed.length),
        addedCount: Value(added),
        duplicateCount: Value(parsed.length - added),
        unreadCount: Value(unread),
        result: Value(reconciliation.result),
      ),
    );
    return StatementImported(
      StatementImportSummary(
        institutionName: institution.name,
        firstDay: firstDay,
        lastDay: lastDay,
        transactionCount: parsed.length,
        addedCount: added,
        duplicateCount: parsed.length - added,
        unreadCount: unread,
        closingBalanceMinor: closing,
        gapMinor: reconciliation.gapMinor,
        importedAt: now,
      ),
    );
  }

  StatementImportSummary _summaryOf(Import record) {
    final id = record.institutionId;
    return StatementImportSummary.fromRecord(
      record,
      institutionName:
          (id == null ? null : _institution(id)?.name) ?? 'the statement',
    );
  }

  Institution? _institution(String id) {
    for (final i in _institutions) {
      if (i.id == id) return i;
    }
    return null;
  }
}

/// [date] (a UTC midnight, as ujumbe gives statement dates) as a calendar
/// date, or [fallback] when it is later or missing.
CalendarDate _earlier(DateTime? date, CalendarDate fallback) {
  if (date == null) return fallback;
  final day = CalendarDate(date.year, date.month, date.day);
  return day.isBefore(fallback) ? day : fallback;
}

CalendarDate _later(DateTime? date, CalendarDate fallback) {
  if (date == null) return fallback;
  final day = CalendarDate(date.year, date.month, date.day);
  return day.isAfter(fallback) ? day : fallback;
}

DateTime _utcMidnight(CalendarDate day) =>
    DateTime.utc(day.year, day.month, day.day);

CalendarDate _dayOf(DateTime utcMidnight) =>
    CalendarDate(utcMidnight.year, utcMidnight.month, utcMidnight.day);

DedupeFields _fieldsOfParsed(ParsedTransaction p) => DedupeFields(
  amountMinor: p.amountMinor,
  direction: transactionDirectionFor(p.direction),
  occurredAt: p.time,
  receipt: p.receipt,
  counterparty: p.counterparty,
  dedupeKey: p.dedupeKey,
);

DedupeFields _fieldsOfRecord(TransactionRecord t) => DedupeFields(
  amountMinor: t.amountMinor,
  direction: t.direction,
  occurredAt: t.occurredAt,
  receipt: t.receiptNo,
  counterparty: t.counterpartyName,
  dedupeKey: t.dedupeKey,
);

final statementImporterProvider = Provider<StatementImporter>(
  (ref) => StatementImporter(
    // Unreachable in a build without a PDF engine: import is hidden there.
    extractor:
        ref.watch(pdfTextExtractorProvider) ??
        (throw StateError('This build has no PDF engine')),
    read: ref.watch(statementReadBatchProvider),
    accounts: ref.watch(accountsRepositoryProvider),
    transactions: ref.watch(transactionsRepositoryProvider),
    imports: ref.watch(statementImportsRepositoryProvider),
    institutions: ref.watch(institutionCatalogueProvider),
    now: ref.watch(clockProvider),
  ),
);

/// How statements are read. Tests swap in [readStatement], since a
/// background isolate does not run inside widget tests.
final statementReadBatchProvider = Provider<StatementReadBatch>(
  (ref) => readStatementInBackground,
);
