import '../enums.dart';
import '../ledger/ledger_entry.dart';
import '../payees/payee_identifier.dart';
import 'debt.dart';

/// Default leeway between a payment and the expected repayment: 10%.
const defaultRepaymentToleranceBasisPoints = 1000;

/// A ledger entry that might be a repayment, with the raw identifier of who
/// it went to when the message gave one.
class RepaymentCandidate {
  const RepaymentCandidate(this.entry, {this.counterparty});

  final LedgerEntry entry;
  final PayeeIdentifier? counterparty;
}

/// Why an entry looks like a repayment, strongest first.
enum RepaymentMatch {
  /// A Fuliza repayment, which can only go to Fuliza.
  fuliza,

  /// Paid to the lender, within the tolerance of the expected amount.
  payeeAndAmount,

  /// Paid to the lender, but not the expected amount: a part payment, or a
  /// payment for something else.
  payeeOnly,
}

/// A suggestion that a ledger entry repays a debt. The user confirms it;
/// nothing is linked until they do.
class RepaymentSuggestion {
  const RepaymentSuggestion({
    required this.entryId,
    required this.debtId,
    required this.match,
  });

  final int entryId;
  final int debtId;
  final RepaymentMatch match;

  @override
  bool operator ==(Object other) =>
      other is RepaymentSuggestion &&
      other.entryId == entryId &&
      other.debtId == debtId &&
      other.match == match;

  @override
  int get hashCode => Object.hash(entryId, debtId, match);

  @override
  String toString() =>
      'RepaymentSuggestion(entry $entryId -> debt $debtId, ${match.name})';
}

/// Suggests which debt each outgoing payment repays, at most one per entry.
///
/// A payment matches a debt when it goes to the debt's payee, to one of its
/// identifiers, or to a payee whose name contains every word of the lender's
/// name. It is a strong match when the amount is within
/// [toleranceBasisPoints] of the debt's minimum or of one of its agreed
/// instalments. Fuliza repayments always go to the Fuliza debt. Inflows,
/// own transfers, other currencies and entries in [linkedEntryIds] are
/// skipped. When several debts match, the strongest wins, then the one whose
/// expected amount is closest, then the lowest id.
List<RepaymentSuggestion> suggestRepayments({
  required Iterable<Debt> debts,
  required Iterable<RepaymentCandidate> candidates,
  Set<int> linkedEntryIds = const {},
  int toleranceBasisPoints = defaultRepaymentToleranceBasisPoints,
}) {
  final debtList = debts.toList();
  final suggestions = <RepaymentSuggestion>[];

  for (final candidate in candidates) {
    final entry = candidate.entry;
    if (!entry.isOutflow ||
        entry.transferPairId != null ||
        linkedEntryIds.contains(entry.id)) {
      continue;
    }

    if (entry.kind == TransactionKind.fulizaRepayment) {
      final fuliza =
          debtList
              .where(
                (d) =>
                    d.type == DebtType.fuliza && d.currency == entry.currency,
              )
              .toList()
            ..sort((a, b) => a.id.compareTo(b.id));
      if (fuliza.isNotEmpty) {
        suggestions.add(
          RepaymentSuggestion(
            entryId: entry.id,
            debtId: fuliza.first.id,
            match: RepaymentMatch.fuliza,
          ),
        );
      }
      continue;
    }
    if (entry.kind == TransactionKind.fulizaDraw) continue;

    ({Debt debt, RepaymentMatch match, int gap})? best;
    for (final debt in debtList) {
      if (debt.currency != entry.currency || !_paidTo(debt, candidate)) {
        continue;
      }
      final nearest = _nearestExpected(debt, entry.amountMinor);
      final match =
          nearest != null &&
              nearest.gap * 10000 <= nearest.expected * toleranceBasisPoints
          ? RepaymentMatch.payeeAndAmount
          : RepaymentMatch.payeeOnly;
      final rank = (match: match, gap: nearest?.gap ?? _noGap);
      if (best == null ||
          rank.match.index < best.match.index ||
          (rank.match == best.match &&
              (rank.gap < best.gap ||
                  (rank.gap == best.gap && debt.id < best.debt.id)))) {
        best = (debt: debt, match: match, gap: rank.gap);
      }
    }
    if (best != null) {
      suggestions.add(
        RepaymentSuggestion(
          entryId: entry.id,
          debtId: best.debt.id,
          match: best.match,
        ),
      );
    }
  }
  return suggestions;
}

const _noGap = 1 << 62;

bool _paidTo(Debt debt, RepaymentCandidate candidate) {
  final entry = candidate.entry;
  if (debt.payeeId != null && entry.payeeId == debt.payeeId) return true;
  final counterparty = candidate.counterparty;
  if (counterparty != null && debt.identifiers.any(counterparty.matches)) {
    return true;
  }
  final name = entry.payeeName;
  if (name == null) return false;
  final lenderWords = _words(debt.lender);
  return lenderWords.isNotEmpty && _words(name).containsAll(lenderWords);
}

Set<String> _words(String raw) => raw
    .toUpperCase()
    .split(RegExp(r'[^A-Z0-9]+'))
    .where((w) => w.isNotEmpty)
    .toSet();

Iterable<int> _expectedAmounts(Debt debt) => [
  if (debt.minimumPaymentMinor > 0) debt.minimumPaymentMinor,
  for (final i in debt.instalments) i.amountMinor,
];

/// The expected amount closest to [amount], and how far off it is. Null when
/// the debt has no expected amount.
({int expected, int gap})? _nearestExpected(Debt debt, int amount) {
  ({int expected, int gap})? nearest;
  for (final expected in _expectedAmounts(debt)) {
    final gap = (expected - amount).abs();
    if (nearest == null || gap < nearest.gap) {
      nearest = (expected: expected, gap: gap);
    }
  }
  return nearest;
}
