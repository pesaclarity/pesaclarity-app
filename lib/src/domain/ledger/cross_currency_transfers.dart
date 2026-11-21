import '../../core/money/exchange_rates.dart';
import '../../core/money/money.dart';
import '../accounts/account_reference.dart';
import '../enums.dart';
import 'ledger_entry.dart';
import 'message_twins.dart';
import 'own_transfers.dart';

/// What the rule needs to know about one of the person's accounts.
class TransferAccount {
  const TransferAccount({
    required this.currency,
    this.reference,
    this.institutionId,
  });

  /// The currency the account holds.
  final String currency;

  /// The account number its messages print, usually masked
  /// (`0170*****8765`). Null until a message shows one.
  final String? reference;

  /// The institution whose messages feed it, such as `kcb`. Null for an
  /// account added by hand.
  final String? institutionId;
}

/// The rate between two currencies on a day.
class DayRateQuote {
  const DayRateQuote(this.rate, {this.approximate = false});

  /// How much of the second currency one unit of the first bought.
  final double rate;

  /// Whether the rate was kept on a later day than the one asked for (the
  /// oldest rate the app has). It can pair amounts that fit it, but it
  /// cannot rule a pair out of what the person is offered.
  final bool approximate;
}

/// How much of [to] one unit of [from] bought on the day of [at], as the
/// app converts amounts of that day, or null when it has no rate.
typedef DayRate = DayRateQuote? Function(String from, String to, DateTime at);

/// [converter]'s rates as a [DayRate]: the person's own rate, else the
/// rates kept for that day, else the closest earlier day's. The oldest
/// kept rates, for a day before any were kept, are marked approximate.
DayRate dayRatesOf(CurrencyConverter converter) => (from, to, at) {
  final a = converter.rateOn(from, at);
  final b = converter.rateOn(to, at);
  if (a == null || b == null || a.rate <= 0 || b.rate <= 0) return null;
  bool rough(RateKind kind) =>
      kind == RateKind.approximate || kind == RateKind.latest;
  return DayRateQuote(
    b.rate / a.rate,
    approximate: rough(a.kind) || rough(b.kind),
  );
};

/// How far the rate two amounts give may be from the day's rate for them
/// to pair by themselves: 5% either way, room for a bank's margin on a
/// move between two of its accounts. Half of what a card payment abroad is
/// allowed ([cardRateToleranceBasisPoints]): a transfer's two sides sit on
/// two accounts, so a wrong pair would hide both income and spending.
const crossCurrencyRateToleranceBasisPoints = 500;

/// How the two amounts of a move between currencies fit the day's rate.
enum CrossCurrencyFit {
  /// Within [crossCurrencyRateToleranceBasisPoints] of the day's rate.
  atRate,

  /// Further off, but within [cardRateToleranceBasisPoints]: paired only
  /// when a message or the person names the other account, otherwise only
  /// ever suggested.
  loose,

  /// There is no rate for that day to check against, or only an
  /// approximate one that the amounts do not fit: only ever suggested.
  unchecked,
}

/// What, beyond time and rate, ties the two sides of a move between
/// currencies, strongest first.
enum CrossCurrencyTie {
  /// One message prints the other account's number.
  accountNumber,

  /// The person said which of their accounts the money went to or came
  /// from.
  named,

  /// Both accounts are at the same institution, such as a shilling and a
  /// dollar account at one bank.
  sameInstitution,
}

/// Money out of one of the person's accounts in one currency and the
/// matching money into another of their accounts in another currency.
class CrossCurrencyTransfer {
  const CrossCurrencyTransfer({
    required this.outflow,
    required this.inflow,
    required this.fit,
    required this.gap,
    this.tie,
    this.dayRate,
  });

  final LedgerEntry outflow;
  final LedgerEntry inflow;
  final CrossCurrencyFit fit;

  /// The time between the two sides.
  final Duration gap;

  /// Null when nothing but time and rate ties the two: then the pair is
  /// only ever suggested.
  final CrossCurrencyTie? tie;

  /// The day's rate from the money out's currency to the money in's, when
  /// the app has one.
  final DayRateQuote? dayRate;

  TransferPair get pair => TransferPair(outflow.id, inflow.id);

  /// The side that is not [entry].
  LedgerEntry partnerOf(LedgerEntry entry) =>
      entry.id == outflow.id ? inflow : outflow;

  /// Each side keeps the amount and currency it moved in.
  int get outMinor => _amount(outflow);
  String get outCurrency => _currency(outflow);
  int get inMinor => _amount(inflow);
  String get inCurrency => _currency(inflow);

  /// The rate the person got: how much of [inCurrency] one unit of
  /// [outCurrency] bought, from the two amounts alone.
  double get rateGot =>
      (inMinor / _pow10(minorUnitDigits(inCurrency))) /
      (outMinor / _pow10(minorUnitDigits(outCurrency)));

  /// What the money out would have bought at the day's rate, in
  /// [inCurrency]. Null without a rate.
  int? get expectedInMinor => switch (dayRate) {
    final quote? => convertMinor(
      outMinor,
      from: outCurrency,
      to: inCurrency,
      rate: quote.rate,
    ),
    null => null,
  };

  /// How much less came in than the day's rate gives, in [inCurrency]:
  /// what the exchange cost. Negative when more came in. Null without a
  /// rate.
  int? get costMinor => switch (expectedInMinor) {
    final expected? => expected - inMinor,
    null => null,
  };

  /// [costMinor] as a share of what the day's rate gives, in hundredths of
  /// a percent: 100 is 1% worse than the day's rate.
  int? get costBasisPoints {
    final expected = expectedInMinor;
    if (expected == null || expected <= 0) return null;
    return ((expected - inMinor) * 10000 / expected).round();
  }

  /// What the move cost in [currency]: the money out less the money in,
  /// each at the rate of its own day, as totals count them. Negative when
  /// more came in. Null when either side has no rate for its day, or only
  /// an approximate one: the cost is then not known.
  int? costIn(String currency, DayRate rateOn) {
    int? value(int minor, String code, DateTime at) {
      if (code == currency) return minor;
      final quote = rateOn(code, currency, at);
      if (quote == null || quote.approximate || quote.rate <= 0) return null;
      return convertMinor(minor, from: code, to: currency, rate: quote.rate);
    }

    final out = value(outMinor, outCurrency, outflow.occurredAt);
    final into = value(inMinor, inCurrency, inflow.occurredAt);
    return out == null || into == null ? null : out - into;
  }

  @override
  String toString() =>
      'CrossCurrencyTransfer(${outflow.id} -> ${inflow.id}, '
      '$outCurrency $outMinor -> $inCurrency $inMinor, ${fit.name}'
      '${tie == null ? '' : ', ${tie!.name}'})';
}

/// Finds own transfers between accounts in different currencies, such as
/// KES 13,050 out of a shilling account and USD 100.00 into a dollar
/// account at the same bank, among entries not already paired. Run it
/// after [findOwnTransfers], on what that leaves unpaired.
///
/// It starts from the same-currency rule and takes its amount check from
/// the card-payment rule ([cardAmountsAgree]). Two entries pair when:
///
/// * they are on different accounts, one out and one in, each in the
///   currency of its own account ([accounts]), and the two currencies
///   differ. A card payment abroad on a shilling account is not in its
///   account's currency, so it is never a side;
/// * they are transfer movements, as for one currency: send, paybill and
///   bank out, received and bank in, not put in a non-transfer category,
///   and not typed in by hand unless the person said where it went;
/// * the rate they give is close to the day's ([rateOn], for the day the
///   money left): within [crossCurrencyRateToleranceBasisPoints] either
///   way. With no rate for that day, nothing pairs by itself;
/// * something more than time and rate ties them, since two unrelated
///   payments can give a likely rate where they cannot give equal
///   amounts. Either both accounts are at the same institution and the
///   two are no more than [window] apart; or one message prints the other
///   account's number, or the person named the other account, and then
///   they may be [waitingTransferWindow] apart and the rate up to
///   [cardRateToleranceBasisPoints] off.
///
/// Money out that names another account than the inflow's, money in that
/// names another account than the outflow's, a side the person named for
/// another account, a side the bank reversed ([reversedEntries]), and
/// pairs in [declined] never pair.
///
/// A fee the money out's message prints is on top of its amount, so the
/// rate is worked out without it. A fee folded into either amount cannot
/// be told from the rate: it shows as a worse one.
///
/// When several candidates fit, pairs confirmed by account number come
/// first, then ones the person named, then those at one institution; then
/// the closer rate fit, the closest in time and the rate nearest the
/// day's. Each entry is used once, and the result does not depend on the
/// order of [entries]. One out pairs with one in: money that arrives in
/// two parts is not paired.
List<CrossCurrencyTransfer> findCrossCurrencyTransfers(
  Iterable<LedgerEntry> entries, {
  required Map<int, TransferAccount> accounts,
  required DayRate rateOn,
  Duration window = defaultTransferWindow,
  Set<TransferPair> declined = const {},
}) {
  final all = entries.toList();
  final reversed = reversedEntries(all);
  final outflows = <String, List<LedgerEntry>>{};
  final inflows = <String, List<LedgerEntry>>{};
  for (final entry in all) {
    if (reversed.contains(entry.id) || !_canBeSide(entry, accounts)) continue;
    (entry.isOutflow ? outflows : inflows)
        .putIfAbsent(_currency(entry), () => [])
        .add(entry);
  }

  final candidates = <CrossCurrencyTransfer>[];
  for (final MapEntry(key: outCurrency, value: outs) in outflows.entries) {
    for (final MapEntry(key: inCurrency, value: ins) in inflows.entries) {
      if (inCurrency == outCurrency) continue;
      for (final out in outs) {
        for (final into in ins) {
          final found = _judge(out, into, accounts, rateOn, declined);
          if (found == null) continue;
          final allowed = switch (found.tie) {
            CrossCurrencyTie.accountNumber || CrossCurrencyTie.named =>
              found.fit == CrossCurrencyFit.unchecked
                  ? null
                  : waitingTransferWindow,
            CrossCurrencyTie.sameInstitution =>
              found.fit == CrossCurrencyFit.atRate ? window : null,
            null => null,
          };
          if (allowed != null && found.gap <= allowed) candidates.add(found);
        }
      }
    }
  }
  candidates.sort((a, b) {
    final byTie = a.tie!.index.compareTo(b.tie!.index);
    return byTie != 0 ? byTie : _byFitThenTime(a, b);
  });

  final used = <int>{};
  final pairs = <CrossCurrencyTransfer>[];
  for (final candidate in candidates) {
    final out = candidate.outflow.id;
    final into = candidate.inflow.id;
    if (used.contains(out) || used.contains(into)) continue;
    used
      ..add(out)
      ..add(into);
    pairs.add(candidate);
  }
  return pairs;
}

/// Entries that could be [entry]'s other side in another currency, best
/// first, for the person to choose; never paired without them.
///
/// The other side is unpaired, on another account, the opposite way, in
/// another currency, each in its own account's currency, and up to
/// [waitingTransferWindow] away. The rate the two give is within
/// [cardRateToleranceBasisPoints] of the day's; with no rate for that
/// day, or only an approximate one, every such entry is offered as
/// [CrossCurrencyFit.unchecked], so the person can still match by hand.
/// The closer rate fit first, then the closest in time.
List<CrossCurrencyTransfer> suggestCrossCurrencyPartners(
  LedgerEntry entry,
  Iterable<LedgerEntry> entries, {
  required Map<int, TransferAccount> accounts,
  required DayRate rateOn,
  Set<TransferPair> declined = const {},
  int limit = 3,
}) {
  if (entry.transferPairId != null || entry.isCorrection) return const [];
  if (_amount(entry) <= 0 || !_inOwnCurrency(entry, accounts)) return const [];
  final all = entries.toList();
  final reversed = reversedEntries(all);
  if (reversed.contains(entry.id)) return const [];
  final found = <CrossCurrencyTransfer>[];
  for (final other in all) {
    if (other.id == entry.id || other.direction == entry.direction) continue;
    if (reversed.contains(other.id)) continue;
    if (!_canBeSide(other, accounts, byHand: true)) continue;
    final out = entry.isOutflow ? entry : other;
    final into = entry.isOutflow ? other : entry;
    final judged = _judge(out, into, accounts, rateOn, declined);
    if (judged != null) found.add(judged);
  }
  found.sort(_byFitThenTime);
  return found.take(limit).toList();
}

/// The ids of entries the bank undid: for each reversal message, the
/// latest entry before it on the same account, the other way, with the
/// same amount and currency, up to [waitingTransferWindow] earlier and not
/// already taken by another reversal. A move that bounced (KES 13,050 out,
/// then KES 13,050 back) left nothing to arrive in the other currency, so
/// neither half is a side; the reversal itself never is one either.
Set<int> reversedEntries(Iterable<LedgerEntry> entries) {
  final sorted = entries.toList()
    ..sort((a, b) {
      final byTime = a.occurredAt.compareTo(b.occurredAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  final taken = <int>{};
  for (final (i, reversal) in sorted.indexed) {
    if (reversal.kind != TransactionKind.reversal) continue;
    for (var j = i - 1; j >= 0; j--) {
      final undone = sorted[j];
      if (reversal.occurredAt.difference(undone.occurredAt) >
          waitingTransferWindow) {
        break;
      }
      if (taken.contains(undone.id) ||
          undone.kind == TransactionKind.reversal ||
          undone.accountId != reversal.accountId ||
          undone.direction == reversal.direction ||
          _currency(undone) != _currency(reversal) ||
          _amount(undone) != _amount(reversal)) {
        continue;
      }
      taken.add(undone.id);
      break;
    }
  }
  return taken;
}

/// The closer rate fit first, then the closest in time, then the rate
/// nearest the day's, then by id so the order never depends on the
/// input's.
int _byFitThenTime(CrossCurrencyTransfer a, CrossCurrencyTransfer b) {
  final byFit = a.fit.index.compareTo(b.fit.index);
  if (byFit != 0) return byFit;
  final byGap = a.gap.compareTo(b.gap);
  if (byGap != 0) return byGap;
  final byRate = (a.costBasisPoints ?? 0).abs().compareTo(
    (b.costBasisPoints ?? 0).abs(),
  );
  if (byRate != 0) return byRate;
  final byOut = a.outflow.id.compareTo(b.outflow.id);
  return byOut != 0 ? byOut : a.inflow.id.compareTo(b.inflow.id);
}

// The kinds an own transfer comes as, the same as for one currency.
const _outflowKinds = {
  TransactionKind.sent,
  TransactionKind.paybill,
  TransactionKind.bank,
};

const _inflowKinds = {TransactionKind.received, TransactionKind.bank};

/// The amount and currency [entry] moved in, also when it was read
/// converted into the base currency.
int _amount(LedgerEntry entry) =>
    entry.originalAmountMinor ?? entry.amountMinor;

String _currency(LedgerEntry entry) => entry.originalCurrency ?? entry.currency;

/// Whether [entry] moved in the currency its account holds. A card payment
/// in dollars on a shilling account did not: it is a payment, and the
/// card-payment rule's to merge with the account's own debit.
bool _inOwnCurrency(LedgerEntry entry, Map<int, TransferAccount> accounts) =>
    accounts[entry.accountId]?.currency == _currency(entry);

/// Whether [entry] may be one side: unpaired, in its account's currency,
/// and a movement transfers come as, not put in a non-transfer category.
/// Money typed in by hand is a side only when the person said where it
/// went, or when they are choosing it themselves ([byHand]).
bool _canBeSide(
  LedgerEntry entry,
  Map<int, TransferAccount> accounts, {
  bool byHand = false,
}) {
  if (entry.transferPairId != null || entry.isCorrection) return false;
  if (_amount(entry) <= 0 || !_inOwnCurrency(entry, accounts)) return false;
  if (entry.transferAccountId != null) return true;
  if (entry.source == TransactionSource.manual && !byHand) return false;
  final type = entry.categoryType;
  if (type != null && type != CategoryType.transfer) return false;
  return entry.isOutflow
      ? _outflowKinds.contains(entry.kind)
      : _inflowKinds.contains(entry.kind);
}

/// [out] and [into] as one transfer, with how well they fit and what ties
/// them, or null when they can never be one: the same account or
/// currency, more than [waitingTransferWindow] apart, named or numbered
/// apart, unmatched by the person, or ruled out by the day's rate.
CrossCurrencyTransfer? _judge(
  LedgerEntry out,
  LedgerEntry into,
  Map<int, TransferAccount> accounts,
  DayRate rateOn,
  Set<TransferPair> declined,
) {
  if (out.accountId == into.accountId) return null;
  final outCurrency = _currency(out);
  final inCurrency = _currency(into);
  if (outCurrency == inCurrency) return null;
  final gap = out.occurredAt.difference(into.occurredAt).abs();
  if (gap > waitingTransferWindow) return null;
  if (_namedApart(out, into) || _numberedApart(out, into, accounts)) {
    return null;
  }
  if (declined.contains(TransferPair(out.id, into.id))) return null;

  final quote = rateOn(outCurrency, inCurrency, out.occurredAt);
  final usable = quote != null && quote.rate > 0 && quote.rate.isFinite
      ? quote
      : null;
  final fit = _fit(
    outMinor: _amount(out),
    outCurrency: outCurrency,
    inMinor: _amount(into),
    inCurrency: inCurrency,
    quote: usable,
  );
  if (fit == null) return null;
  return CrossCurrencyTransfer(
    outflow: out,
    inflow: into,
    fit: fit,
    gap: gap,
    tie: _tie(out, into, accounts),
    dayRate: usable,
  );
}

/// How the two amounts fit the day's rate, or null when it rules them
/// out: the money in is more than [cardRateToleranceBasisPoints] from
/// what the money out bought that day.
CrossCurrencyFit? _fit({
  required int outMinor,
  required String outCurrency,
  required int inMinor,
  required String inCurrency,
  required DayRateQuote? quote,
}) {
  if (quote == null) return CrossCurrencyFit.unchecked;
  final expected = convertMinor(
    outMinor,
    from: outCurrency,
    to: inCurrency,
    rate: quote.rate,
  );
  // Too small to compare in the money in's smallest unit.
  if (expected <= 0) return CrossCurrencyFit.unchecked;
  final off = (expected - inMinor).abs();
  if (off * 10000 <= expected * crossCurrencyRateToleranceBasisPoints) {
    return CrossCurrencyFit.atRate;
  }
  if (off * 10000 <= expected * cardRateToleranceBasisPoints) {
    return CrossCurrencyFit.loose;
  }
  return quote.approximate ? CrossCurrencyFit.unchecked : null;
}

/// What, beyond time and rate, ties [out] and [into]: the strongest tie
/// when there are several.
CrossCurrencyTie? _tie(
  LedgerEntry out,
  LedgerEntry into,
  Map<int, TransferAccount> accounts,
) {
  if (_byNumber(out, into, accounts)) return CrossCurrencyTie.accountNumber;
  if (out.transferAccountId != null || into.transferAccountId != null) {
    return CrossCurrencyTie.named;
  }
  final a = accounts[out.accountId]?.institutionId;
  final b = accounts[into.accountId]?.institutionId;
  return a != null && a == b ? CrossCurrencyTie.sameInstitution : null;
}

/// Whether the person's own naming of either side rules the pair out.
bool _namedApart(LedgerEntry out, LedgerEntry into) =>
    (out.transferAccountId != null &&
        out.transferAccountId != into.accountId) ||
    (into.transferAccountId != null && into.transferAccountId != out.accountId);

/// The bank account number [entry]'s message says the money came from or
/// went to (not a paybill reference, which may be a phone number).
String? _otherAccountNumber(LedgerEntry entry) =>
    entry.counterpartyKind == PayeeIdentifierKind.account
    ? entry.counterpartyValue
    : null;

/// Whether [printed] and [own] both show digits, and whether they can be
/// the same account; null when either shows none.
bool? _sameNumber(String? printed, String? own) {
  final a = AccountReference.tryParse(printed);
  final b = AccountReference.tryParse(own);
  return a == null || b == null ? null : a.sameAs(b);
}

/// Whether one message prints the other account's number: money out that
/// paid into [into]'s account (a masked `131***4567` and a full
/// `1310004567` agree), or money in that names [out]'s account as where
/// it came from.
bool _byNumber(
  LedgerEntry out,
  LedgerEntry into,
  Map<int, TransferAccount> accounts,
) =>
    _sameNumber(paidToReference(out), accounts[into.accountId]?.reference) ==
        true ||
    _sameNumber(
          _otherAccountNumber(into),
          accounts[out.accountId]?.reference,
        ) ==
        true;

/// Whether the account numbers the messages print rule the pair out: money
/// in that names another bank account than [out]'s as where it came from,
/// or money out that names another than [into]'s as where it went.
bool _numberedApart(
  LedgerEntry out,
  LedgerEntry into,
  Map<int, TransferAccount> accounts,
) =>
    _sameNumber(
          _otherAccountNumber(into),
          accounts[out.accountId]?.reference,
        ) ==
        false ||
    _sameNumber(
          _otherAccountNumber(out),
          accounts[into.accountId]?.reference,
        ) ==
        false;

double _pow10(int digits) {
  var result = 1.0;
  for (var i = 0; i < digits; i++) {
    result *= 10;
  }
  return result;
}
