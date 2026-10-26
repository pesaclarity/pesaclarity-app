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

/// Imports statement PDFs: reads them on the phone, adds the transactions
/// SMS missed, and checks the ledger against the closing balance.
class StatementImporter {
  StatementImporter({
    required this._extractor,
    required this._accounts,
    required this._transactions,
    required this._imports,
    required this._institutions,
    required this._now,
  });

  final PdfTextExtractor _extractor;
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
    final String text;
    try {
      text = await _extractor.extractText(bytes, password: password);
    } on PdfPasswordRequired {
      return const StatementNeedsPassword(wrongPassword: false);
    } on PdfWrongPassword {
      return const StatementNeedsPassword(wrongPassword: true);
    } on PdfUnreadable {
      return const StatementNotRead(isPdf: false);
    }
    return importText(text, fileHash: fileHash);
  }

  /// Imports statement [text] extracted from the file with [fileHash].
  Future<StatementImportOutcome> importText(
    String text, {
    required String fileHash,
  }) async {
    switch (detectStatementType(text)) {
      case BankStatementType(:final bankName):
        return StatementComingSoon(bankName);
      case UnknownStatementType():
        return const StatementNotRead(isPdf: true);
      case MpesaStatementType():
        return _importMpesa(const MpesaStatementParser().parse(text), fileHash);
    }
  }

  Future<StatementImportOutcome> _importMpesa(
    MpesaStatement statement,
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

    final institution = _institution('mpesa');
    final accountId = await _accounts.accountForInstitution(
      'mpesa',
      name: institution?.name ?? 'M-Pesa',
      type: institution?.type ?? AccountType.mpesa,
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

    final unread =
        statement.unreadLines.length + statement.balanceBreaks.length;
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
        institutionId: const Value('mpesa'),
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
        institutionName: institution?.name ?? 'M-Pesa',
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
    extractor: ref.watch(pdfTextExtractorProvider),
    accounts: ref.watch(accountsRepositoryProvider),
    transactions: ref.watch(transactionsRepositoryProvider),
    imports: ref.watch(statementImportsRepositoryProvider),
    institutions: ref.watch(institutionCatalogueProvider),
    now: ref.watch(clockProvider),
  ),
);
