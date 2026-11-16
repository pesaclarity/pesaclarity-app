import '../enums.dart';
import '../ledger/balances.dart';
import '../ledger/ledger_entry.dart';
import 'book_account.dart';
import 'books.dart';

/// The posting engine of a space's double-entry journal (decision 0018,
/// stage 1): every transaction becomes one entry whose postings sum to zero,
/// plus an opening entry per account and an entry wherever a reported
/// balance moved an account by more than its records.
///
/// Each money account moves exactly as the balance code reads it
/// ([WalletWalk.change] and its checkpoints), so the journal's balance of an
/// account equals [balanceAt], and its Fuliza owed account equals
/// [fulizaOwedAt]. What that reading adds or takes away beyond a
/// transaction's own amount posts against the account that explains it:
///
/// * A Fuliza draw credits Fuliza owed with its amount and access fee; the
///   fee and any daily charges its total shows are fees.
/// * A draw that funded the payment just before it ([WalletWalk.fundedBy])
///   reaches that payment through Money in transit: the payment's entry
///   takes the draw's amount from transit, the draw's entry puts it there.
/// * A repayment debits Fuliza owed by what was owed; the rest is fees. Money
///   in that M-Pesa kept for Fuliza, with or without a repayment message,
///   posts the repayment in the money in's entry, as the balance shows it.
/// * A payment Fuliza covered with no draw message credits Fuliza owed with
///   what it covered plus the access fee.
/// * A reported balance that clears Fuliza with no repayment seen debits
///   Fuliza owed against Not yet sorted.
/// * A balance correction posts everything it changes, wallet and Fuliza
///   owed, against Balance corrections.
/// * Any other gap between a reported balance and the records posts against
///   Not yet sorted, in an entry of its own.
///
/// Transactions on no known account, in another currency than their account
/// or before its opening date still post, as they read alone.
List<JournalEntry> postJournal({
  required Iterable<AccountOpening> accounts,
  required Iterable<LedgerEntry> history,
  required Map<int, BookCategory> categories,
}) {
  final all = history.toList();
  final out = <JournalEntry>[];
  final walked = <int>{};
  for (final account in accounts) {
    final walk = WalletWalk.of(account, all);
    out.addAll(_postAccount(account, walk, all, categories));
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
      ),
    );
  }
  return out;
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
  // With a reported balance, balances walk back from the first one, so the
  // account starts from that figure; the difference is not yet sorted.
  var start = account.openingBalanceMinor;
  final first = own.indexWhere(walk.isCheckpoint);
  if (first >= 0) {
    final upToFirst = own.take(first + 1).fold(0, (s, e) => s + walk.change(e));
    start = walk.checkpoints[own[first].id]! - upToFirst;
  }
  out.add(
    JournalEntry(
      source: JournalSource.opening,
      sourceId: account.id,
      at: account.openingDate,
      currency: account.currency,
      lines: [
        JournalLine(money, start - before),
        JournalLine(
          BookAccount.openingBalances,
          -(account.openingBalanceMinor - before),
        ),
        JournalLine(
          BookAccount.notYetSorted,
          -(start - account.openingBalanceMinor),
        ),
      ],
    ),
  );

  var running = start;
  var owed = 0;
  for (final e in own) {
    // Balances leave a draw that funded the payment before it out of
    // [WalletWalk.change] and let the payment's reported balance carry it,
    // so it counts only where that balance is a checkpoint.
    final fundedBy = walk.isCheckpoint(e) ? walk.fundedBy(e) : 0;
    final change = walk.change(e) + fundedBy;
    final owedNow = walk.owedAfter(e);
    running += change;
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
        moneyChange: change + (e.isCorrection ? gap : 0),
        // Only M-Pesa's walk keeps Fuliza; elsewhere a draw or repayment
        // moves what is borrowed by its own amount.
        owedDelta: account.canOweFuliza ? owedNow - owed : _plainOwed(e),
        fuliza: account.canOweFuliza
            ? BookAccount.fulizaOwed(account.id)
            : BookAccount.borrowed,
        fundedBy: fundedBy,
        funded: walk.isFunded(e),
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
JournalEntry _postOne(
  LedgerEntry e, {
  required Map<int, BookCategory> categories,
  required int moneyChange,
  required int owedDelta,
  BookAccount? fuliza,
  int fundedBy = 0,
  bool funded = false,
}) {
  final money = BookAccount.money(e.accountId);
  final owedAccount = fuliza ?? BookAccount.fulizaOwed(e.accountId);
  final lines = <JournalLine>[..._ownLines(e, categories)];
  int moneyIn(Iterable<JournalLine> ls) => ls
      .where((l) => l.account == money)
      .fold(0, (sum, l) => sum + l.amountMinor);

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
            ? BookAccount.fees
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
    lines: _merged(lines),
  );
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
