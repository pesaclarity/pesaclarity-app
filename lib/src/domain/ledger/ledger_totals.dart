import '../../core/money/money.dart';
import 'fuliza.dart';
import 'ledger_entry.dart';
import 'ledger_role.dart';

/// Honest totals for a period: own transfers, borrowing and money awaiting a
/// payee name never count as income or spending.
class LedgerTotals {
  const LedgerTotals({
    this.incomeMinor = 0,
    this.spendingMinor = 0,
    this.feesMinor = 0,
    this.taxMinor = 0,
    this.savingMinor = 0,
    this.debtRepaymentMinor = 0,
    this.borrowingMinor = 0,
    this.ownTransferMinor = 0,
    this.awaitingPayeeMinor = 0,
  });

  /// Totals for entries in [currency] whose time is in `[from, to)`.
  ///
  /// [history] should reach back before [from] so Fuliza repayments can be
  /// matched to earlier draws. Fees include charges, the transaction cost on
  /// every entry (own transfers too, since moving money still costs) and the
  /// fee share of Fuliza repayments; the rest of a repayment counts as debt
  /// repayment. Own transfers are counted once, by their outflow half.
  factory LedgerTotals.of(
    Iterable<LedgerEntry> history, {
    required DateTime from,
    required DateTime to,
    String? currency,
  }) {
    currency ??= BaseCurrency.code;
    final all = history.where((e) => e.currency == currency).toList();
    final fuliza = FulizaLedger.of(all);

    var income = 0;
    var spending = 0;
    var fees = 0;
    var tax = 0;
    var saving = 0;
    var repayment = 0;
    var borrowing = 0;
    var transfers = 0;
    var awaiting = 0;
    for (final entry in all) {
      if (entry.occurredAt.isBefore(from) || !entry.occurredAt.isBefore(to)) {
        continue;
      }
      final amount = entry.amountMinor;
      fees += entry.feeMinor;
      switch (roleOf(entry)) {
        case LedgerRole.income:
          income += amount;
        case LedgerRole.spending:
          spending += amount;
        case LedgerRole.fee:
          fees += amount;
        case LedgerRole.tax:
          tax += amount;
        case LedgerRole.saving:
          saving += amount;
        case LedgerRole.debtRepayment:
          final fee = fuliza.feeOf(entry);
          fees += fee;
          repayment += amount - fee;
        case LedgerRole.borrowing:
          borrowing += amount;
        case LedgerRole.ownTransfer:
          if (entry.isOutflow) transfers += amount;
        case LedgerRole.awaitingPayee:
          awaiting += amount;
        case LedgerRole.reversal:
          if (entry.isInflow) {
            spending -= amount;
          } else {
            income -= amount;
          }
      }
    }
    return LedgerTotals(
      incomeMinor: income,
      spendingMinor: spending,
      feesMinor: fees,
      taxMinor: tax,
      savingMinor: saving,
      debtRepaymentMinor: repayment,
      borrowingMinor: borrowing,
      ownTransferMinor: transfers,
      awaitingPayeeMinor: awaiting,
    );
  }

  final int incomeMinor;

  /// Spending net of refunds. Excludes fees, tax, savings and debt payments.
  final int spendingMinor;
  final int feesMinor;
  final int taxMinor;
  final int savingMinor;

  /// Debt repayments excluding the Fuliza fee share.
  final int debtRepaymentMinor;
  final int borrowingMinor;
  final int ownTransferMinor;

  /// Received from people not yet named; neutral until they are.
  final int awaitingPayeeMinor;
}
