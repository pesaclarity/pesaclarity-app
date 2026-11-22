import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/time/calendar.dart';
import '../database/app_database.dart';

// A SACCO is one account (decision: SACCOs as one account with both sides):
// its deposits and shares are the account's balance, and its loan is a debt
// linked from its details. A payment to its paybill stays on the account it
// was paid from and gets a mirror deposit on the SACCO, paired as an own
// transfer; when the loan is repaid by paybill, the loan's part of the
// payment leaves the SACCO again as a loan repayment. A check-off loan is
// taken off by itself each payday, as a payment recorded by hand, since no
// message shows it.

/// The dedupe key of the mirror deposit for payment [paymentId].
String saccoDepositKey(int paymentId) => 'sacco-in:$paymentId';

/// The dedupe key of the loan's part of payment [paymentId].
String saccoLoanKey(int paymentId) => 'sacco-loan:$paymentId';

/// [name] as SACCO names are compared: lower case, letters and digits only,
/// without "sacco", "ltd" or "loan".
String saccoNameKey(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .split(RegExp(r'\s+'))
    .where(
      (w) =>
          w.isNotEmpty &&
          !const {'sacco', 'ltd', 'limited', 'loan', 'society'}.contains(w),
    )
    .join(' ');

/// The paybill [raw] as kept: its digits.
String? saccoPaybill(String? raw) {
  final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  return digits.isEmpty ? null : digits;
}

/// How payment [paymentMinor] to a SACCO splits: the deposit up to the
/// monthly [contributionMinor] first, then the loan up to its
/// [instalmentMinor], and anything more to deposits.
({int depositMinor, int loanMinor}) splitSaccoPayment(
  int paymentMinor, {
  int? contributionMinor,
  int? instalmentMinor,
}) {
  final instalment = instalmentMinor ?? 0;
  if (instalment <= 0) return (depositMinor: paymentMinor, loanMinor: 0);
  final afterDeposit = paymentMinor - (contributionMinor ?? 0);
  final loan = afterDeposit <= 0
      ? 0
      : (afterDeposit > instalment ? instalment : afterDeposit);
  return (depositMinor: paymentMinor - loan, loanMinor: loan);
}

/// Today's SACCO savings accounts and "Sacco loan" debts, kept apart until
/// now, become SACCO accounts holding both: every SACCO account gets its
/// details, and every SACCO loan joins the SACCO account of the same name,
/// or a new one named after its lender when none or more than one fits.
/// Only reads and writes what is still unlinked, so running it again
/// changes nothing.
Future<void> mergeSaccos(AppDatabase db, DateTime now) async {
  await db.customStatement(
    'INSERT INTO sacco_details (account_id, shares_minor, check_off) '
    "SELECT id, 0, 0 FROM accounts WHERE type = 'sacco' AND product IS NULL "
    'AND id NOT IN (SELECT account_id FROM sacco_details)',
  );
  final loans = await db
      .customSelect(
        'SELECT id, lender, currency FROM debts '
        "WHERE type = 'saccoLoan' AND id NOT IN (SELECT loan_debt_id FROM "
        'sacco_details WHERE loan_debt_id IS NOT NULL) ORDER BY id',
      )
      .get();
  for (final loan in loans) {
    final id = loan.read<int>('id');
    final lender = loan.read<String>('lender');
    final currency = loan.read<String>('currency');
    final free = await db
        .customSelect(
          'SELECT a.id, a.name FROM accounts a INNER JOIN sacco_details s '
          'ON s.account_id = a.id WHERE s.loan_debt_id IS NULL '
          'AND a.currency = ?',
          variables: [Variable.withString(currency)],
        )
        .get();
    final key = saccoNameKey(lender);
    final fits = [
      for (final a in free)
        if (key.isNotEmpty && saccoNameKey(a.read<String>('name')) == key)
          a.read<int>('id'),
    ];
    var accountId = fits.length == 1 ? fits.single : null;
    if (accountId == null) {
      final name = lender.replaceFirst(
        RegExp(r'\s+loan$', caseSensitive: false),
        '',
      );
      accountId = await db.customInsert(
        'INSERT INTO accounts (name, type, currency, opening_balance_minor, '
        'opening_date, hidden) VALUES (?, ?, ?, 0, ?, 0)',
        variables: [
          Variable.withString(name.isEmpty ? lender : name),
          Variable.withString(AccountType.sacco.name),
          Variable.withString(currency),
          Variable.withDateTime(now),
        ],
      );
      await db.customStatement(
        'INSERT INTO sacco_details (account_id, shares_minor, check_off) '
        'VALUES (?, 0, 0)',
        [accountId],
      );
    }
    await db.customStatement(
      'UPDATE sacco_details SET loan_debt_id = ? WHERE account_id = ?',
      [id, accountId],
    );
  }
}

/// The settings key of the payments the person said are not moves to
/// SACCO [accountId].
String saccoNotMovesKey(int accountId) => 'sacco.notMoves.$accountId';

/// What the SACCO details of [accountId] are; null for any other account.
Future<SaccoDetailsRow?> saccoDetailsOf(AppDatabase db, int accountId) =>
    (db.select(
      db.saccoDetails,
    )..where((s) => s.accountId.equals(accountId))).getSingleOrNull();

Future<Set<int>> _notMoves(AppDatabase db, int accountId) async {
  final row = await (db.select(
    db.appSettings,
  )..where((s) => s.key.equals(saccoNotMovesKey(accountId)))).getSingleOrNull();
  if (row == null) return {};
  try {
    return {...(jsonDecode(row.value) as List).cast<int>()};
  } on FormatException {
    return {};
  }
}

Future<void> _saveNotMoves(AppDatabase db, int accountId, Set<int> ids) => db
    .into(db.appSettings)
    .insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        key: saccoNotMovesKey(accountId),
        value: jsonEncode(ids.toList()..sort()),
      ),
    );

/// Whether [row], on another account, pays SACCO [account] with
/// [paybill]: money out to its paybill, or to a business with its name.
bool paysSacco(TransactionRecord row, Account account, String? paybill) {
  if (row.accountId == account.id) return false;
  if (row.direction != TransactionDirection.outflow) return false;
  if (row.kind != TransactionKind.paybill && row.kind != TransactionKind.sent) {
    return false;
  }
  if (row.currency != account.currency) return false;
  final value = row.counterpartyValue;
  final business = row.counterpartyKind == PayeeIdentifierKind.paybill
      ? value?.split('#').first
      : null;
  final names = [?business, ?row.counterpartyName];
  for (final n in names) {
    if (paybill != null && saccoPaybill(n) == paybill && n.trim().isNotEmpty) {
      if (RegExp(r'^[\d\s]+$').hasMatch(n)) return true;
    }
    final key = saccoNameKey(n);
    if (key.isNotEmpty && key == saccoNameKey(account.name)) return true;
  }
  return false;
}

/// Brings every SACCO in step with the payments, or only those concerning
/// [transactionIds]. Safe to run at any time: run again, it changes
/// nothing. Returns the ids of payments newly counted as moves.
Future<Set<int>> syncSaccos(AppDatabase db, {Iterable<int>? transactionIds}) =>
    db.transaction(() async {
      final saccos = await db.select(db.accounts).join([
        innerJoin(
          db.saccoDetails,
          db.saccoDetails.accountId.equalsExp(db.accounts.id),
        ),
      ]).get();
      if (saccos.isEmpty) return <int>{};
      final linked = <int>{};
      for (final row in saccos) {
        linked.addAll(
          await _syncOne(
            db,
            row.readTable(db.accounts),
            row.readTable(db.saccoDetails),
            only: transactionIds?.toSet(),
          ),
        );
      }
      return linked;
    });

Future<Set<int>> _syncOne(
  AppDatabase db,
  Account account,
  SaccoDetailsRow details, {
  Set<int>? only,
}) async {
  final t = db.transactions;
  final paybill = saccoPaybill(details.paybill);
  final notMoves = await _notMoves(db, account.id);
  final loan = details.loanDebtId == null || details.checkOff
      ? null
      : await (db.select(
          db.debts,
        )..where((d) => d.id.equals(details.loanDebtId!))).getSingleOrNull();

  // What the app wrote on the SACCO, by the payment it follows.
  final mirrors = <int, TransactionRecord>{};
  final loanParts = <int, TransactionRecord>{};
  for (final r
      in await (db.select(t)..where(
            (t) =>
                t.accountId.equals(account.id) &
                (t.dedupeKey.like('sacco-in:%') |
                    t.dedupeKey.like('sacco-loan:%')),
          ))
          .get()) {
    final key = r.dedupeKey!;
    final id = int.parse(key.substring(key.indexOf(':') + 1));
    (key.startsWith('sacco-in:') ? mirrors : loanParts)[id] = r;
  }

  final candidates =
      await (db.select(t)..where(
            (t) =>
                t.accountId.equals(account.id).not() &
                t.direction.equalsValue(TransactionDirection.outflow) &
                t.occurredAt.isBiggerOrEqualValue(account.openingDate) &
                (only == null
                    ? const Constant(true)
                    : t.id.isIn(only) |
                          t.id.isIn(mirrors.keys) |
                          t.transferPairId.isIn(only)),
          ))
          .get();
  final payments = {for (final r in candidates) r.id: r};
  // Payments whose mirror is gone, or that stopped being this SACCO's.
  final wanted = <int>{};
  final linked = <int>{};
  for (final row in payments.values) {
    final mirror = mirrors[row.id];
    if (notMoves.contains(row.id)) continue;
    if (mirror == null) {
      if (!paysSacco(row, account, paybill)) continue;
      if (row.transferPairId != null ||
          (row.transferAccountId != null &&
              row.transferAccountId != account.id) ||
          row.debtId != null ||
          row.lentLoanId != null ||
          row.linkedSpaceId != null) {
        continue;
      }
    } else if (row.transferPairId != mirror.id) {
      // The person unmatched it: it stays as it is from now on.
      notMoves.add(row.id);
      await _saveNotMoves(db, account.id, notMoves);
      continue;
    }
    wanted.add(row.id);
    final split = splitSaccoPayment(
      row.amountMinor,
      contributionMinor: details.contributionMinor,
      instalmentMinor: loan?.minimumPaymentMinor,
    );
    if (mirror == null) {
      final mirrorId = await db
          .into(t)
          .insert(
            TransactionsCompanion.insert(
              accountId: account.id,
              occurredAt: row.occurredAt,
              amountMinor: row.amountMinor,
              direction: TransactionDirection.inflow,
              currency: Value(row.currency),
              source: TransactionSource.manual,
              dedupeKey: Value(saccoDepositKey(row.id)),
              transferPairId: Value(row.id),
              transferAccountId: Value(row.accountId),
            ),
          );
      await (db.update(t)..where((t) => t.id.equals(row.id))).write(
        TransactionsCompanion(
          transferPairId: Value(mirrorId),
          transferAccountId: Value(account.id),
        ),
      );
      linked.add(row.id);
    } else if (mirror.amountMinor != row.amountMinor ||
        mirror.occurredAt != row.occurredAt ||
        mirror.transferAccountId != row.accountId) {
      await (db.update(t)..where((t) => t.id.equals(mirror.id))).write(
        TransactionsCompanion(
          amountMinor: Value(row.amountMinor),
          occurredAt: Value(row.occurredAt),
          transferAccountId: Value(row.accountId),
        ),
      );
    }
    final part = loanParts[row.id];
    if (split.loanMinor == 0 || loan == null) {
      if (part != null) {
        await (db.delete(t)..where((t) => t.id.equals(part.id))).go();
      }
    } else if (part == null) {
      await db
          .into(t)
          .insert(
            TransactionsCompanion.insert(
              accountId: account.id,
              occurredAt: row.occurredAt,
              amountMinor: split.loanMinor,
              direction: TransactionDirection.outflow,
              kind: const Value(TransactionKind.loanRepayment),
              currency: Value(row.currency),
              source: TransactionSource.manual,
              dedupeKey: Value(saccoLoanKey(row.id)),
              debtId: Value(loan.id),
            ),
          );
    } else if (part.amountMinor != split.loanMinor ||
        part.occurredAt != row.occurredAt ||
        part.debtId != loan.id) {
      await (db.update(t)..where((t) => t.id.equals(part.id))).write(
        TransactionsCompanion(
          amountMinor: Value(split.loanMinor),
          occurredAt: Value(row.occurredAt),
          debtId: Value(loan.id),
        ),
      );
    }
  }

  // What the app wrote for a payment that is gone or no longer a move here.
  for (final MapEntry(key: paymentId, value: m) in mirrors.entries) {
    if (wanted.contains(paymentId)) continue;
    if (only != null && !payments.containsKey(paymentId)) {
      // Not looked at, unless the payment is gone.
      final exists = await (db.select(
        t,
      )..where((t) => t.id.equals(paymentId))).getSingleOrNull();
      if (exists != null) continue;
    }
    await (db.update(t)..where((t) => t.transferPairId.equals(m.id))).write(
      const TransactionsCompanion(
        transferPairId: Value(null),
        transferAccountId: Value(null),
      ),
    );
    await (db.delete(t)..where((t) => t.id.equals(m.id))).go();
    if (loanParts[paymentId] case final part?) {
      await (db.delete(t)..where((t) => t.id.equals(part.id))).go();
    }
  }
  return linked;
}

/// The paydays of a check-off on [day] after [from] up to [today], oldest
/// first. A day past a month's end is its last day.
List<CalendarDate> checkOffDays({
  required int day,
  required CalendarDate from,
  required CalendarDate today,
}) {
  final days = <CalendarDate>[];
  var month = YearMonth(from.year, from.month);
  while (true) {
    final d = day > month.dayCount ? month.dayCount : (day < 1 ? 1 : day);
    final date = CalendarDate(month.year, month.month, d);
    if (date.isAfter(today)) break;
    if (date.isAfter(from)) days.add(date);
    month = month.next;
  }
  return days;
}

/// The next check-off payday on [day] after [today].
CalendarDate nextCheckOff(int day, CalendarDate today) {
  var month = YearMonth(today.year, today.month);
  while (true) {
    final d = day > month.dayCount ? month.dayCount : (day < 1 ? 1 : day);
    final date = CalendarDate(month.year, month.month, d);
    if (date.isAfter(today)) return date;
    month = month.next;
  }
}

/// Takes each check-off loan's instalment off by itself on every payday
/// since it was set up, up to [today], as a payment recorded by hand (no
/// message shows it), never more than is owed. Safe to run any time: a
/// payday that has its payment already gets none.
Future<int> takeCheckOffs(AppDatabase db, CalendarDate today) =>
    db.transaction(() async {
      var taken = 0;
      final rows = await (db.select(
        db.saccoDetails,
      )..where((s) => s.checkOff & s.loanDebtId.isNotNull())).get();
      for (final s in rows) {
        final day = s.checkOffDay;
        final from = s.checkOffFrom;
        if (day == null || from == null) continue;
        final debt = await (db.select(
          db.debts,
        )..where((d) => d.id.equals(s.loanDebtId!))).getSingleOrNull();
        final instalment = debt?.minimumPaymentMinor ?? 0;
        if (debt == null || instalment <= 0) continue;
        for (final payday in checkOffDays(
          day: day,
          from: CalendarDate.local(from),
          today: today,
        )) {
          final start = payday.startInstant;
          final end = payday.addDays(1).startInstant;
          final done =
              await (db.select(db.loanPayments)..where(
                    (p) =>
                        p.debtId.equals(debt.id) &
                        p.paidOn.isBiggerOrEqualValue(start) &
                        p.paidOn.isSmallerThanValue(end),
                  ))
                  .get();
          if (done.isNotEmpty) continue;
          final owed = await owedOn(db, debt, start);
          if (owed <= 0) break;
          await db
              .into(db.loanPayments)
              .insert(
                LoanPaymentsCompanion.insert(
                  debtId: Value(debt.id),
                  paidOn: start,
                  amountMinor: owed < instalment ? owed : instalment,
                ),
              );
          taken++;
        }
      }
      return taken;
    });

/// What [debt] owed just before [at]: its confirmed balance, or else its
/// starting balance, less what was repaid since.
Future<int> owedOn(AppDatabase db, DebtRecord debt, DateTime at) async {
  final asOf = debt.balanceAsOf;
  var owed = debt.balanceMinor ?? debt.startingBalanceMinor;
  final t = db.transactions;
  for (final r
      in await (db.select(t)..where(
            (t) =>
                t.debtId.equals(debt.id) &
                t.direction.equalsValue(TransactionDirection.outflow) &
                t.occurredAt.isSmallerThanValue(at),
          ))
          .get()) {
    if (asOf == null || !r.occurredAt.isBefore(asOf)) owed -= r.amountMinor;
  }
  for (final p
      in await (db.select(db.loanPayments)..where(
            (p) => p.debtId.equals(debt.id) & p.paidOn.isSmallerThanValue(at),
          ))
          .get()) {
    if (asOf == null || !p.paidOn.isBefore(asOf)) owed -= p.amountMinor;
  }
  return owed;
}

/// The payday each check-off loan is taken on, by debt id.
Future<Map<int, int>> checkOffDaysByDebt(AppDatabase db) async => {
  for (final s in await (db.select(
    db.saccoDetails,
  )..where((s) => s.checkOff & s.loanDebtId.isNotNull())).get())
    s.loanDebtId!: ?s.checkOffDay,
};
