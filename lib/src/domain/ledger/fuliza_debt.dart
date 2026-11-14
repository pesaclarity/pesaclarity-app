import '../enums.dart';
import '../time/calendar.dart';
import 'balances.dart';
import 'ledger_entry.dart';

/// One day's Fuliza daily charge, worked out from what two Fuliza messages
/// said was owed. Not a transaction: a fee on the Fuliza debt, never taken
/// from the wallet and never a correction.
class FulizaDailyCharge {
  const FulizaDailyCharge(this.date, this.amountMinor);

  final CalendarDate date;
  final int amountMinor;

  @override
  bool operator ==(Object other) =>
      other is FulizaDailyCharge &&
      other.date == date &&
      other.amountMinor == amountMinor;

  @override
  int get hashCode => Object.hash(date, amountMinor);

  @override
  String toString() => 'FulizaDailyCharge($date, $amountMinor)';
}

/// What M-Pesa's balances show Fuliza did, with no Fuliza message for it.
enum FulizaAutoKind {
  /// Money came in and M-Pesa kept part of it to repay Fuliza: the
  /// message's balance is lower than the wallet plus the amount.
  repaid,

  /// A payment took more than the wallet held and M-Pesa reported 0
  /// after it: Fuliza covered the rest.
  drawn,

  /// M-Pesa reported money in the wallet while Fuliza was owed. It only
  /// credits the wallet once Fuliza is clear, so the debt was repaid.
  cleared,
}

/// Fuliza activity worked out from an M-Pesa [entry]'s balance. Never a
/// row in the ledger: it changes what is owed, not income or spending.
class FulizaAuto {
  const FulizaAuto({
    required this.kind,
    required this.entry,
    required this.amountMinor,
    this.feeMinor = 0,
  });

  final FulizaAutoKind kind;

  /// The M-Pesa entry whose balance shows it.
  final LedgerEntry entry;

  /// Repaid or cleared: what came off the debt, daily charges included.
  /// Drawn: what Fuliza covered, before its access fee.
  final int amountMinor;

  /// Repaid: the daily charges in [amountMinor]. Drawn: the access fee.
  final int feeMinor;

  DateTime get occurredAt => entry.occurredAt;
}

/// Fuliza's access fee on [drawnMinor]: 1%, as its messages charge it.
int fulizaAccessFee(int drawnMinor) => (drawnMinor + 50) ~/ 100;

/// The most daily charges a repayment [days] after the debt was last known
/// can hold on top of [owedMinor]: 1% of it a day, at least 1.00 a day.
int fulizaChargeAllowance(int owedMinor, int days) {
  final perDay = owedMinor ~/ 100;
  return (days < 1 ? 1 : days) * (perDay < 100 ? 100 : perDay);
}

/// The Fuliza debt on one M-Pesa account, kept as its entries are walked
/// in time order (see [WalletWalk]).
///
/// A draw starts on its day owing its amount and access fee, a daily charge
/// adds to it every day after until it is repaid, and repayments come off
/// it. Each draw message prints the total owed after it. That total is a
/// checkpoint: what it holds beyond the previous total plus the draws,
/// access fees and repayments since is daily charges, spread evenly over
/// the days between the two messages (one charge a day, any remainder on
/// the last day). Before the first checkpoint, or after a repayment clears
/// the debt, there is nothing to spread from, so no charge is made up.
///
/// M-Pesa repays Fuliza from incoming money before the wallet gets any, so
/// money in the wallet after the debt means it was repaid, message or not.
class FulizaBook {
  var _owed = 0;
  DateTime? _dueAt;

  /// The day the debt was last known exactly: a total, a correction or a
  /// repayment that cleared it.
  CalendarDate? _known;

  /// The day the debt started, since it was last clear.
  CalendarDate? _since;
  final _charges = <FulizaDailyCharge>[];
  final _auto = <FulizaAuto>[];

  int get owedMinor => _owed;

  void _add(int minor, CalendarDate day) {
    if (_owed == 0 && minor > 0) _since = day;
    _owed += minor;
  }

  void _clear(CalendarDate day) {
    _owed = 0;
    _dueAt = null;
    _known = day;
    _since = null;
  }

  /// A Fuliza draw message.
  void draw(LedgerEntry e) {
    _add(e.amountMinor + e.feeMinor, e.date);
    final total = e.owedAfterMinor;
    if (total != null) {
      final extra = total - _owed;
      final since = _known;
      if (extra > 0 && since != null) {
        _charges.addAll(_spread(extra, since, e.date));
      }
      _owed = total;
      _since ??= e.date;
      _known = e.date;
    }
    _dueAt = e.owedDueAt ?? _dueAt;
  }

  /// A repayment message (or one checked by hand) for [amountMinor].
  void repay(int amountMinor, CalendarDate day) {
    if (amountMinor >= _owed) {
      _clear(day);
    } else {
      _owed -= amountMinor;
    }
  }

  /// [e]'s balance shows M-Pesa kept [paidMinor] of incoming money for
  /// Fuliza: what was owed, plus [chargesMinor] of daily charges since it
  /// was last known.
  void repaidFrom(LedgerEntry e, int paidMinor, int chargesMinor) {
    if (chargesMinor > 0) {
      final from = _known ?? _since;
      _charges.addAll(
        from == null
            ? [FulizaDailyCharge(e.date, chargesMinor)]
            : _spread(chargesMinor, from, e.date),
      );
    }
    _auto.add(
      FulizaAuto(
        kind: FulizaAutoKind.repaid,
        entry: e,
        amountMinor: paidMinor,
        feeMinor: chargesMinor,
      ),
    );
    final principal = paidMinor - chargesMinor;
    if (principal >= _owed) {
      _clear(e.date);
    } else {
      _owed -= principal;
    }
  }

  /// [e] took the wallet below zero: Fuliza covered [drawnMinor].
  void drawnFor(LedgerEntry e, int drawnMinor) {
    final fee = fulizaAccessFee(drawnMinor);
    _auto.add(
      FulizaAuto(
        kind: FulizaAutoKind.drawn,
        entry: e,
        amountMinor: drawnMinor,
        feeMinor: fee,
      ),
    );
    _add(drawnMinor + fee, e.date);
  }

  /// [e] reported money in the wallet: anything still owed was repaid.
  void walletHasMoney(LedgerEntry e) {
    if (_owed <= 0) return;
    _auto.add(
      FulizaAuto(kind: FulizaAutoKind.cleared, entry: e, amountMinor: _owed),
    );
    _clear(e.date);
  }

  /// A balance the person set: below zero is what Fuliza is owed.
  void correction(LedgerEntry e) {
    final stated = e.balanceAfterMinor!;
    _owed = stated < 0 ? -stated : 0;
    _known = e.date;
    _since = _owed > 0 ? e.date : null;
    if (_owed == 0) _dueAt = null;
  }

  /// The most daily charges a repayment on [day] can hold.
  int chargeAllowance(CalendarDate day) {
    final from = _known ?? _since ?? day;
    return fulizaChargeAllowance(_owed, from.daysUntil(day));
  }

  FulizaDebt result() => FulizaDebt._(
    _owed,
    _owed == 0 ? null : _dueAt,
    List.unmodifiable(_charges),
    List.unmodifiable(_auto),
  );
}

/// The Fuliza debt on one M-Pesa account after its entries: see
/// [FulizaBook] for how it is kept.
class FulizaDebt {
  FulizaDebt._(this.owedMinor, this.dueAt, this.charges, this.auto);

  /// Reads one M-Pesa account's [entries] (all from the same account) as
  /// if the account opened with nothing just before the first.
  factory FulizaDebt.of(Iterable<LedgerEntry> entries) {
    final list = entries.toList();
    if (list.isEmpty) return FulizaBook().result();
    var first = list.first.occurredAt;
    for (final e in list) {
      if (e.occurredAt.isBefore(first)) first = e.occurredAt;
    }
    return WalletWalk.of(
      AccountOpening(
        id: list.first.accountId,
        type: AccountType.mpesa,
        openingBalanceMinor: 0,
        openingDate: first,
        currency: list.first.currency,
      ),
      list,
    ).fuliza;
  }

  /// Fuliza owed after the last entry.
  final int owedMinor;

  /// When [owedMinor] is due, as the last message said.
  final DateTime? dueAt;

  /// Daily charges worked out between messages, oldest first.
  final List<FulizaDailyCharge> charges;

  /// What M-Pesa's balances show Fuliza did without a message, oldest
  /// first.
  final List<FulizaAuto> auto;

  /// Daily charges on days in [month].
  int chargesIn(YearMonth month) => charges
      .where((c) => month.contains(c.date))
      .fold(0, (sum, c) => sum + c.amountMinor);
}

/// [extra] spread over the days after [from] up to and including [to]; all
/// on [to] when they are the same day.
List<FulizaDailyCharge> _spread(int extra, CalendarDate from, CalendarDate to) {
  final days = from.daysUntil(to);
  if (days <= 0) return [FulizaDailyCharge(to, extra)];
  final each = extra ~/ days;
  final rest = extra - each * days;
  return [
    for (var d = 1; d <= days; d++)
      FulizaDailyCharge(from.addDays(d), each + (d == days ? rest : 0)),
  ];
}
