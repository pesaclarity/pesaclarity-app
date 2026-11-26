import 'package:drift/drift.dart';

import '../../domain/accounts/account_reference.dart';
import '../../domain/debts/next_due.dart';
import '../../domain/ledger/balances.dart';
import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import 'accounts_repository.dart';

/// Moves the new agent withdrawal or deposit [id] into or out of the
/// person's cash account: its other side is written on the cash account
/// and the two are paired, an own transfer, so cash never vanishes from
/// the totals and only what they record as spent from cash counts. With no
/// cash account yet, "Cash in hand" is made for it.
Future<void> linkAgentCash(
  AppDatabase db,
  int id, {
  required List<Account> accounts,
}) async {
  final row = await (db.select(
    db.transactions,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
  if (row == null ||
      row.transferPairId != null ||
      row.transferAccountId != null ||
      row.categoryOverrideId != null) {
    return;
  }
  final out = row.direction == TransactionDirection.outflow;
  final agent = switch (row.kind) {
    TransactionKind.withdrawal => out,
    TransactionKind.deposit => !out,
    _ => false,
  };
  if (!agent) return;
  final from = accounts.where((a) => a.id == row.accountId).firstOrNull;
  if (from == null ||
      from.type == AccountType.cash ||
      savingsAccountTypes.contains(from.type)) {
    return;
  }
  final cashId = await DriftAccountsRepository(db)
      .cashAccount(name: cashInHandName, openingDate: row.occurredAt);
  final cash = await (db.select(
    db.accounts,
  )..where((a) => a.id.equals(cashId))).getSingle();
  if (cash.openingDate.isAfter(row.occurredAt)) {
    await (db.update(db.accounts)..where((a) => a.id.equals(cashId))).write(
      AccountsCompanion(openingDate: Value(row.occurredAt)),
    );
  }
  if (cash.currency != row.currency) return;
  final mirror = await db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: cashId,
          occurredAt: row.occurredAt,
          amountMinor: row.amountMinor,
          currency: Value(row.currency),
          direction: out
              ? TransactionDirection.inflow
              : TransactionDirection.outflow,
          kind: Value(row.kind),
          source: TransactionSource.manual,
          transferPairId: Value(id),
        ),
      );
  await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
    TransactionsCompanion(transferPairId: Value(mirror)),
  );
}

/// Runs [linkAgentCash] over every agent withdrawal and deposit stored in
/// [db], oldest first, so those read before agent cash moved to a cash
/// account get their side there too. Safe to run again: one already
/// paired is left as it is. Returns how many it linked.
Future<int> linkStoredAgentCash(AppDatabase db) async {
  final rows =
      await (db.select(db.transactions)
            ..where(
              (t) =>
                  t.kind.isInValues(const [
                    TransactionKind.withdrawal,
                    TransactionKind.deposit,
                  ]) &
                  t.transferPairId.isNull() &
                  t.transferAccountId.isNull() &
                  t.categoryOverrideId.isNull(),
            )
            ..orderBy([(t) => OrderingTerm(expression: t.occurredAt)]))
          .get();
  if (rows.isEmpty) return 0;
  var linked = 0;
  for (final row in rows) {
    final accounts = await db.select(db.accounts).get();
    await linkAgentCash(db, row.id, accounts: accounts);
    final after = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(row.id))).getSingle();
    if (after.transferPairId != null) linked++;
  }
  return linked;
}

/// The name of the cash account made for the first agent withdrawal.
const cashInHandName = 'Cash in hand';

/// Marks the new transaction [id] as money moved to the person's own
/// account when its message names the account number it went to and that
/// number is one of the person's other accounts: a PesaLink from KCB to the
/// person's own Loop account, or an M-Pesa payment to KCB's paybill for
/// their own KCB account. It then counts as an own transfer even before the
/// other side's message is read, and pairs with it when it is.
///
/// Only the number decides, never the name the message prints, and only
/// when exactly one other account has it. A number that fits none of the
/// person's accounts leaves the transaction as it is.
Future<void> markTransferToOwnAccount(
  AppDatabase db,
  int id, {
  required List<Account> accounts,
}) async {
  final row = await (db.select(
    db.transactions,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
  if (row == null ||
      row.direction != TransactionDirection.outflow ||
      row.transferAccountId != null ||
      row.categoryOverrideId != null) {
    return;
  }
  const kinds = {
    TransactionKind.sent,
    TransactionKind.paybill,
    TransactionKind.bank,
  };
  if (!kinds.contains(row.kind ?? TransactionKind.bank)) return;
  final value = row.counterpartyValue;
  final paid = switch (row.counterpartyKind) {
    PayeeIdentifierKind.account => value,
    PayeeIdentifierKind.paybill when value != null && value.contains('#') =>
      value.substring(value.indexOf('#') + 1),
    _ => null,
  };
  final printed = AccountReference.tryParse(paid);
  if (printed == null) return;
  final own = [
    for (final a in accounts)
      if (a.id != row.accountId &&
          (AccountReference.tryParse(a.reference)?.sameAs(printed) ?? false))
        a,
  ];
  if (own.length != 1) return;
  await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
    TransactionsCompanion(transferAccountId: Value(own.single.id)),
  );
}

/// Records the new loan repayment [id] against the debt its message names,
/// such as "KCB Salary Advance": the debt with that lender, or a new one,
/// and, when the message gives what is left, that balance as confirmed just
/// after the payment. When the message says when the next instalment is
/// due, that becomes the debt's next due date, unless a later message or
/// the person's own edit set it. It is paying back a debt, never spending.
Future<void> linkLoanRepayment(AppDatabase db, int id) async {
  final row = await (db.select(
    db.transactions,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
  if (row == null ||
      row.kind != TransactionKind.loanRepayment ||
      row.direction != TransactionDirection.outflow ||
      row.debtId != null) {
    return;
  }
  final lender = (row.counterpartyName?.trim().isNotEmpty ?? false)
      ? row.counterpartyName!.trim()
      : 'Loan';
  final name = lender.length > 80 ? lender.substring(0, 80) : lender;
  final debts = await (db.select(
    db.debts,
  )..where((d) => d.currency.equals(row.currency))).get();
  var debt = debts
      .where((d) => d.lender.toLowerCase() == name.toLowerCase())
      .firstOrNull;
  if (debt == null) {
    final debtId = await db
        .into(db.debts)
        .insert(
          DebtsCompanion.insert(
            lender: name,
            type: name.toLowerCase().contains('salary advance')
                ? DebtType.salaryAdvance
                : DebtType.bankLoan,
            currency: Value(row.currency),
            startingBalanceMinor: (row.owedAfterMinor ?? 0) + row.amountMinor,
          ),
        );
    debt = await (db.select(
      db.debts,
    )..where((d) => d.id.equals(debtId))).getSingle();
  }
  await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
    TransactionsCompanion(debtId: Value(debt.id)),
  );
  final owed = row.owedAfterMinor;
  final asOf = debt.balanceAsOf;
  // Stored to the second: one second on, so this payment is not taken off
  // the balance it already left.
  final after = row.occurredAt.add(const Duration(seconds: 1));
  if (owed != null && (asOf == null || !after.isBefore(asOf))) {
    await (db.update(db.debts)..where((d) => d.id.equals(debt!.id))).write(
      DebtsCompanion(balanceMinor: Value(owed), balanceAsOf: Value(after)),
    );
  }
  final due = row.owedDueAt;
  final dueSetAt = debt.nextDueSetAt;
  if (due != null && (dueSetAt == null || !row.occurredAt.isBefore(dueSetAt))) {
    // The parsers give a due day as midnight in the lender's own time;
    // lenders whose messages print one are in East Africa Time.
    final day = CalendarDate.of(due, nairobiUtcOffset);
    await (db.update(db.debts)..where((d) => d.id.equals(debt!.id))).write(
      DebtsCompanion(
        nextDueDay: Value(dayKey(day)),
        nextDueSetAt: Value(row.occurredAt),
        nextDueTransactionId: Value(id),
      ),
    );
  }
}

/// Takes back what the repayment [row] set on its debt when its message was
/// read (see [linkLoanRepayment]), before [row] leaves this space: the
/// balance its message confirmed and the next due date it gave. Each goes
/// back to what the newest repayment message still linked to the debt says,
/// or to nothing, as if [row]'s message had not been read here. A balance
/// or date set since, by a later message or by the person, stays.
Future<void> unlinkLoanRepayment(AppDatabase db, TransactionRecord row) async {
  final debtId = row.debtId;
  if (debtId == null) return;
  final debt = await (db.select(
    db.debts,
  )..where((d) => d.id.equals(debtId))).getSingleOrNull();
  if (debt == null) return;
  // The other repayment messages on this debt, newest first.
  final others =
      await (db.select(db.transactions)
            ..where(
              (t) =>
                  t.debtId.equals(debtId) &
                  t.id.equals(row.id).not() &
                  t.kind.equalsValue(TransactionKind.loanRepayment) &
                  t.direction.equalsValue(TransactionDirection.outflow),
            )
            ..orderBy([
              (t) => OrderingTerm.desc(t.occurredAt),
              (t) => OrderingTerm.desc(t.id),
            ]))
          .get();
  final owed = row.owedAfterMinor;
  final asOf = debt.balanceAsOf;
  final after = row.occurredAt.add(const Duration(seconds: 1));
  final setBalance =
      owed != null &&
      debt.balanceMinor == owed &&
      asOf != null &&
      asOf.isAtSameMomentAs(after);
  final setDue = debt.nextDueTransactionId == row.id;
  if (!setBalance && !setDue) return;
  final balance = others.where((t) => t.owedAfterMinor != null).firstOrNull;
  final due = others.where((t) => t.owedDueAt != null).firstOrNull;
  await (db.update(db.debts)..where((d) => d.id.equals(debtId))).write(
    DebtsCompanion(
      balanceMinor: setBalance
          ? Value(balance?.owedAfterMinor)
          : const Value.absent(),
      balanceAsOf: setBalance
          ? Value(balance?.occurredAt.add(const Duration(seconds: 1)))
          : const Value.absent(),
      nextDueDay: setDue
          ? Value(
              due == null
                  ? null
                  : dayKey(CalendarDate.of(due.owedDueAt!, nairobiUtcOffset)),
            )
          : const Value.absent(),
      nextDueSetAt: setDue ? Value(due?.occurredAt) : const Value.absent(),
      nextDueTransactionId: setDue ? Value(due?.id) : const Value.absent(),
    ),
  );
}
