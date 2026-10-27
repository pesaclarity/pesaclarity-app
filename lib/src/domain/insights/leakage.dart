import '../../core/money/money.dart';
import '../enums.dart';
import '../ledger/fuliza.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';

/// Where leakages went in a period, in minor units.
///
/// Leakages are spending with a payee leak type, plus every fee. Fuliza fees
/// are kept apart from other fees so the overdraft cost shows on its own.
/// The total matches the Financial Health Index's leakage measure.
class LeakageBreakdown {
  const LeakageBreakdown({
    this.lifestyleMinor = 0,
    this.friendsMinor = 0,
    this.familyMinor = 0,
    this.feesMinor = 0,
    this.fulizaMinor = 0,
  });

  /// Leakages in entries in [currency] whose time is in `[from, to)`.
  ///
  /// [history] should reach back before [from] so Fuliza repayments find
  /// their draws. Pass [fuliza] when it is already worked out for [history].
  factory LeakageBreakdown.of(
    Iterable<LedgerEntry> history, {
    required DateTime from,
    required DateTime to,
    String? currency,
    FulizaLedger? fuliza,
  }) {
    currency ??= BaseCurrency.code;
    final all = history.where((e) => e.currency == currency);
    final ledger = fuliza ?? FulizaLedger.of(all);
    var lifestyle = 0;
    var friends = 0;
    var family = 0;
    var fees = 0;
    var fulizaFees = 0;
    for (final entry in all) {
      if (entry.occurredAt.isBefore(from) || !entry.occurredAt.isBefore(to)) {
        continue;
      }
      fees += entry.feeMinor;
      switch (roleOf(entry)) {
        case LedgerRole.fee:
          fees += entry.amountMinor;
        case LedgerRole.debtRepayment:
          fulizaFees += ledger.feeOf(entry);
        case LedgerRole.spending:
          switch (entry.leakType) {
            case LeakType.none:
              break;
            case LeakType.lifestyle:
              lifestyle += entry.amountMinor;
            case LeakType.friends:
              friends += entry.amountMinor;
            case LeakType.family:
              family += entry.amountMinor;
            case LeakType.fees:
              fees += entry.amountMinor;
          }
        case LedgerRole.income ||
            LedgerRole.tax ||
            LedgerRole.ownTransfer ||
            LedgerRole.borrowing ||
            LedgerRole.saving ||
            LedgerRole.awaitingPayee ||
            LedgerRole.reversal:
          break;
      }
    }
    return LeakageBreakdown(
      lifestyleMinor: lifestyle,
      friendsMinor: friends,
      familyMinor: family,
      feesMinor: fees,
      fulizaMinor: fulizaFees,
    );
  }

  final int lifestyleMinor;
  final int friendsMinor;
  final int familyMinor;

  /// Transaction costs and bank or wallet charges, other than Fuliza fees.
  final int feesMinor;

  /// The fee share of Fuliza repayments.
  final int fulizaMinor;

  int get totalMinor =>
      lifestyleMinor + friendsMinor + familyMinor + feesMinor + fulizaMinor;

  /// The groups in the order Insights lists them.
  List<LeakageGroup> get groups => [
    LeakageGroup('Lifestyle', lifestyleMinor),
    LeakageGroup('Friends', friendsMinor),
    LeakageGroup('Family', familyMinor),
    LeakageGroup('Fees', feesMinor),
    LeakageGroup('Fuliza fees', fulizaMinor),
  ];
}

/// One line of a [LeakageBreakdown].
class LeakageGroup {
  const LeakageGroup(this.label, this.amountMinor);

  final String label;
  final int amountMinor;
}

/// [part] as a share of [whole] in basis points, or null when [whole] is not
/// positive.
int? shareBasisPoints(int part, int whole) =>
    whole <= 0 ? null : part * 10000 ~/ whole;

/// Basis points as a whole percentage, rounded half up: 1,750 is "18%".
String percentLabel(int basisPoints) => '${(basisPoints + 50) ~/ 100}%';
