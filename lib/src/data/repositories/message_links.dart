import 'package:drift/drift.dart';

import '../../domain/accounts/account_reference.dart';
import '../../domain/debts/next_due.dart';
import '../../domain/time/calendar.dart';
import '../database/app_database.dart';

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
