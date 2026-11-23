/// A SACCO as "What you own and owe" counts it: its deposits and shares
/// under Saved, shares marked as money that can't be withdrawn, and its
/// loan under Owed.
class SaccoHolding {
  const SaccoHolding({
    required this.name,
    required this.currency,
    required this.savedMinor,
    this.sharesMinor = 0,
    this.loanName,
    this.loanOwedMinor = 0,
  });

  final String name;
  final String currency;

  /// Deposits and shares: the account's balance.
  final int savedMinor;

  /// Shares, part of [savedMinor]: counted, but they can't be withdrawn.
  final int sharesMinor;

  /// What its loan goes by; null without a loan.
  final String? loanName;

  /// What is still owed on its loan.
  final int loanOwedMinor;

  int get depositsMinor => savedMinor - sharesMinor;

  bool get hasLoan => loanName != null && loanOwedMinor > 0;
}

/// The totals of "What you own and owe": the M-Pesa families' parts with
/// the SACCOs' deposits and shares added to Saved and their loans to Owed.
class OwnAndOwe {
  const OwnAndOwe({
    required this.walletMinor,
    required this.savedMinor,
    required this.investedMinor,
    required this.owedMinor,
  });

  /// Adds [saccos] to the M-Pesa families' totals, leaving out any SACCO
  /// not in [currency].
  factory OwnAndOwe.of({
    required String currency,
    int walletMinor = 0,
    int savedMinor = 0,
    int investedMinor = 0,
    int owedMinor = 0,
    Iterable<SaccoHolding> saccos = const [],
  }) {
    var saved = savedMinor;
    var owed = owedMinor;
    for (final s in saccos) {
      if (s.currency != currency) continue;
      saved += s.savedMinor;
      if (s.hasLoan) owed += s.loanOwedMinor;
    }
    return OwnAndOwe(
      walletMinor: walletMinor,
      savedMinor: saved,
      investedMinor: investedMinor,
      owedMinor: owed,
    );
  }

  final int walletMinor;
  final int savedMinor;
  final int investedMinor;
  final int owedMinor;

  int get ownMinor => walletMinor + savedMinor + investedMinor;

  int get afterDebtsMinor => ownMinor - owedMinor;
}
