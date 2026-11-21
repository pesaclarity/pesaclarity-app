import '../enums.dart';
import '../ledger/balances.dart';
import '../ledger/cross_currency_transfers.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/own_transfers.dart';
import 'book_account.dart';
import 'books.dart';

/// The posting engine of a space's double-entry journal (decision 0018,
/// stage 1): every transaction becomes one entry whose postings sum to zero,
/// plus an opening entry per account and an entry wherever a reported
/// balance moved an account by more than its records.
///
/// Each money account moves as [WalletWalk] reads its entries, and each
/// reported balance is an assertion: where the records do not reach it, the
/// gap posts to Not yet sorted until the person adds what is missing or
/// confirms a correction. What the walk adds or takes away beyond a
/// transaction's own amount posts against the account that explains it:
///
/// * A Fuliza draw credits Fuliza owed with its amount and access fee; the
///   fee and any daily charges its total shows are Fuliza charges.
/// * A draw that funded the payment just before it ([WalletWalk.fundedBy])
///   reaches that payment through Money in transit: the payment's entry
///   takes the draw's amount from transit, the draw's entry puts it there.
/// * A repayment debits Fuliza owed by what was owed; the rest is Fuliza
///   charges. Money in that M-Pesa kept for Fuliza, with or without a
///   repayment message, posts the repayment in the money in's entry, as the
///   balance shows it.
/// * A payment Fuliza covered with no draw message credits Fuliza owed with
///   what it covered plus the access fee.
/// * A reported balance that clears Fuliza with no repayment seen debits
///   Fuliza owed against Not yet sorted.
/// * A balance correction posts everything it changes, wallet and Fuliza
///   owed, against Balance corrections.
/// * Any other gap between a reported balance and the records posts against
///   Not yet sorted, in an entry of its own.
/// * Each side of an own transfer goes through Money in transit, and once
///   both sides are paired the money out's entry clears what the transfer
///   lost on the way ([transferShortfall]): a fee when less arrived than
///   left, Not yet sorted when more did.
/// * A paired transfer between two currencies posts one exchange entry per
///   currency, dated when the money arrived ([JournalSource.exchange]):
///   the money out's currency moves what left from transit to Currency
///   exchange, less what the exchange cost against the day's rate
///   ([arrivedInOutCurrency], from [rateOn]), which goes to Exchange cost;
///   the money in's currency moves what arrived from Currency exchange
///   back into transit. Every entry sums to zero in its currency, and
///   transit clears in each. With no rate for that day, or only an
///   approximate one, the cost is not known: the whole money out goes to
///   Currency exchange.
///
/// Transactions on no known account, in another currency than their account
/// or before its opening date still post, as they read alone.
///
/// [partners] holds the other sides of the own transfers in [history] that
/// [history] leaves out, by id, for posting only some accounts: a money
/// out's entry needs what arrived, and an exchange entry needs both sides.
List<JournalEntry> postJournal({
  required Iterable<AccountOpening> accounts,
  required Iterable<LedgerEntry> history,
  required Map<int, BookCategory> categories,
  Map<int, LedgerEntry> partners = const {},
  DayRate? rateOn,
}) {
  final all = history.toList();
  final byId = {for (final e in all) e.id: e};
  LedgerEntry? partnerOf(LedgerEntry e) => switch (e.transferPairId) {
    null => null,
    final id => byId[id] ?? partners[id],
  };
  final out = <JournalEntry>[];
  final walked = <int>{};
  for (final account in accounts) {
    final walk = WalletWalk.of(account, all);
    out.addAll(_postAccount(account, walk, all, categories, partnerOf));
    walked.addAll(walk.entries.map((e) => e.id));
  }
  for (final e in all) {
    if (walked.contains(e.id)) continue;
    out.add(
      _postOne(
        e,
        categories: categories,
        moneyChange: _plainChange(e),
        owedDelta: _plainOwed(e),
        partner: partnerOf(e),
      ),
    );
  }
  for (final e in all) {
    if (_exchange(e, partnerOf(e), categories, rateOn) case final entry?) {
      out.add(entry);
    }
  }
  return out;
}

/// [e]'s currency's exchange entry, when [e] and [partner] are the two
/// sides of an own transfer across currencies that both go through Money
/// in transit; null otherwise. Dated when the money arrived.
JournalEntry? _exchange(
  LedgerEntry e,
  LedgerEntry? partner,
  Map<int, BookCategory> categories,
  DayRate? rateOn,
) {
  if (partner == null) return null;
  final (out, into) = e.isOutflow ? (e, partner) : (partner, e);
  if (!isCrossCurrencyPair(out, into)) return null;
  bool viaTransit(LedgerEntry side) => _ownLines(
    side,
    categories,
  ).any((l) => l.account == BookAccount.moneyInTransit);
  if (!viaTransit(out) || !viaTransit(into)) return null;
  final List<JournalLine> lines;
  if (e.isOutflow) {
    final arrived = rateOn == null
        ? null
        : arrivedInOutCurrency(out, into, rateOn);
    final cost = arrived == null ? 0 : out.amountMinor - arrived;
    lines = [
      JournalLine(BookAccount.currencyExchange, out.amountMinor - cost),
      JournalLine(BookAccount.exchangeCost, cost),
      JournalLine(BookAccount.moneyInTransit, -out.amountMinor),
    ];
  } else {
    lines = [
      JournalLine(BookAccount.moneyInTransit, into.amountMinor),
      JournalLine(BookAccount.currencyExchange, -into.amountMinor),
    ];
  }
  return JournalEntry(
    source: JournalSource.exchange,
    sourceId: e.id,
    at: into.occurredAt,
    currency: e.currency,
    accountId: e.accountId,
    lines: lines,
  );
}

/// The balance of [account] in [currency] from [entries] dated before [at],
/// positive in the account's normal direction (see [Books.balanceOf]).
int journalBalance(
  Iterable<JournalEntry> entries,
  BookAccount account, {
  required String currency,
  DateTime? at,
}) {
  var sum = 0;
  for (final e in entries) {
    if (e.currency != currency) continue;
    if (at != null && !e.at.isBefore(at)) continue;
    for (final l in e.lines) {
      if (l.account == account) sum += l.amountMinor;
    }
  }
  return account.debitNormal ? sum : -sum;
}

/// What [e] moves what is owed by, read alone.
int _plainOwed(LedgerEntry e) => switch (e.kind) {
  TransactionKind.fulizaDraw => e.amountMinor + e.feeMinor,
  TransactionKind.fulizaRepayment => -e.amountMinor,
  _ => 0,
};

/// What [e] moves its money account by, read alone.
int _plainChange(LedgerEntry e) => e.kind == TransactionKind.fulizaDraw
    ? e.signedMinor
    : e.signedMinor - e.feeMinor;

List<JournalEntry> _postAccount(
  AccountOpening account,
  WalletWalk walk,
  List<LedgerEntry> all,
  Map<int, BookCategory> categories,
  LedgerEntry? Function(LedgerEntry e) partnerOf,
) {
  final money = BookAccount.money(account.id);
  final own = walk.entries;
  final out = <JournalEntry>[];

  // Entries before the opening date post, but the opening balance already
  // holds them, as balances read it.
  var before = 0;
  for (final e in all) {
    if (e.accountId == account.id &&
        e.currency == account.currency &&
        e.occurredAt.isBefore(account.openingDate)) {
      before += _plainChange(e);
    }
  }
  // What each entry moves the wallet by. A draw that funded the payment
  // just before it moves the wallet with that payment, whether or not the
  // payment's balance was trusted: the draw is real money either way.
  int change(LedgerEntry e) => walk.change(e) + walk.fundedBy(e);

  // The first reported balance says what the account started from, so the
  // opening is that figure, as the person would have typed it.
  var start = account.openingBalanceMinor;
  final first = own.indexWhere(walk.isCheckpoint);
  if (first >= 0) {
    final upToFirst = own.take(first + 1).fold(0, (s, e) => s + change(e));
    start = walk.checkpoints[own[first].id]! - upToFirst;
  }
  out.add(
    JournalEntry(
      source: JournalSource.opening,
      sourceId: account.id,
      at: account.openingDate,
      currency: account.currency,
      accountId: account.id,
      lines: [
        JournalLine(money, start - before),
        JournalLine(BookAccount.openingBalances, -(start - before)),
      ],
    ),
  );

  var running = start;
  var owed = 0;
  for (final e in own) {
    final fundedBy = walk.fundedBy(e);
    final moved = change(e);
    final owedNow = walk.owedAfter(e);
    running += moved;
    var gap = 0;
    final reported = walk.checkpoints[e.id];
    if (reported != null) {
      gap = reported - running;
      running = reported;
    }
    out.add(
      _postOne(
        e,
        categories: categories,
        moneyChange: moved + (e.isCorrection ? gap : 0),
        // Only M-Pesa's walk keeps Fuliza; elsewhere a draw or repayment
        // moves what is borrowed by its own amount.
        owedDelta: account.canOweFuliza ? owedNow - owed : _plainOwed(e),
        fuliza: account.canOweFuliza
            ? BookAccount.fulizaOwed(account.id)
            : BookAccount.borrowed,
        fundedBy: fundedBy,
        funded: walk.isFunded(e),
        partner: partnerOf(e),
      ),
    );
    owed = owedNow;
    if (gap != 0 && !e.isCorrection) {
      out.add(
        JournalEntry(
          source: JournalSource.balanceDifference,
          sourceId: e.id,
          at: e.occurredAt,
          currency: account.currency,
          accountId: account.id,
          lines: [
            JournalLine(money, gap),
            JournalLine(BookAccount.notYetSorted, -gap),
          ],
        ),
      );
    }
  }
  return out;
}

/// One transaction's entry. [moneyChange] is what it moves its money
/// account by and [owedDelta] what it moves Fuliza owed by; [fundedBy] is
/// a Fuliza draw that funded it, and [funded] says it is such a draw.
/// [partner] is the other side of the own transfer it is half of.
JournalEntry _postOne(
  LedgerEntry e, {
  required Map<int, BookCategory> categories,
  required int moneyChange,
  required int owedDelta,
  BookAccount? fuliza,
  int fundedBy = 0,
  bool funded = false,
  LedgerEntry? partner,
}) {
  final money = BookAccount.money(e.accountId);
  final owedAccount = fuliza ?? BookAccount.fulizaOwed(e.accountId);
  final lines = <JournalLine>[..._ownLines(e, categories)];
  int moneyIn(Iterable<JournalLine> ls) => ls
      .where((l) => l.account == money)
      .fold(0, (sum, l) => sum + l.amountMinor);

  // Both sides are here: what the transfer lost on the way leaves transit.
  final lost = _lostOnTheWay(e, partner, lines, categories);
  if (lost != 0) {
    lines
      ..add(JournalLine(BookAccount.moneyInTransit, -lost))
      ..add(
        JournalLine(
          lost > 0 ? BookAccount.fees : BookAccount.notYetSorted,
          lost,
        ),
      );
  }

  final extra = moneyChange - moneyIn(lines);
  lines.add(JournalLine(money, extra));
  lines.add(JournalLine(owedAccount, -owedDelta));
  // A draw that funded the payment before it: transit carries it there.
  lines.add(JournalLine(BookAccount.moneyInTransit, -fundedBy));
  if (funded) lines.add(JournalLine(BookAccount.moneyInTransit, e.amountMinor));

  final rest = -lines.fold(0, (sum, l) => sum + l.amountMinor);
  if (rest != 0) {
    final fulizaWork =
        e.kind == TransactionKind.fulizaDraw ||
        e.kind == TransactionKind.fulizaRepayment ||
        extra - fundedBy != 0;
    lines.add(
      JournalLine(
        e.isCorrection
            ? BookAccount.balanceCorrections
            : fulizaWork
            ? BookAccount.fulizaCharges
            : BookAccount.notYetSorted,
        rest,
      ),
    );
  }
  return JournalEntry(
    source: JournalSource.transaction,
    sourceId: e.id,
    at: e.occurredAt,
    currency: e.currency,
    accountId: e.accountId,
    lines: _merged(lines),
  );
}

/// What the own transfer money out [e] lost on the way to [partner], its
/// other side (see [transferShortfall]): zero unless both sides go through
/// Money in transit by their own meaning ([lines] are [e]'s own lines).
int _lostOnTheWay(
  LedgerEntry e,
  LedgerEntry? partner,
  List<JournalLine> lines,
  Map<int, BookCategory> categories,
) {
  if (partner == null) return 0;
  final lost = transferShortfall(e, partner);
  if (lost == null || lost == 0) return 0;
  bool viaTransit(Iterable<JournalLine> ls) =>
      ls.any((l) => l.account == BookAccount.moneyInTransit);
  return viaTransit(lines) && viaTransit(_ownLines(partner, categories))
      ? lost
      : 0;
}

/// What [e] posts by its own meaning, before what balances read into it.
/// Fuliza draws, repayments and corrections leave their other side to
/// [_postOne], which works it out from what they change.
List<JournalLine> _ownLines(LedgerEntry e, Map<int, BookCategory> categories) {
  final money = BookAccount.money(e.accountId);
  switch (e.kind) {
    case TransactionKind.fulizaDraw:
      return const [];
    case TransactionKind.fulizaRepayment:
      return [
        JournalLine(money, -(e.amountMinor + e.feeMinor)),
        JournalLine(BookAccount.fees, e.feeMinor),
      ];
    case TransactionKind.correction:
      return [JournalLine(money, e.signedMinor)];
    case _:
      return [
        for (final l in postEntry(e, categories: categories).lines)
          l.account == BookAccount.awaitingPayee
              ? JournalLine(BookAccount.notYetSorted, l.amountMinor)
              : l,
      ];
  }
}

/// [lines] with one line per account, zeros dropped, in first-seen order.
List<JournalLine> _merged(List<JournalLine> lines) {
  final sums = <BookAccount, int>{};
  for (final l in lines) {
    sums[l.account] = (sums[l.account] ?? 0) + l.amountMinor;
  }
  return [
    for (final MapEntry(:key, :value) in sums.entries)
      if (value != 0) JournalLine(key, value),
  ];
}
