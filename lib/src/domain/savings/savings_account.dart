import '../enums.dart';
import '../time/calendar.dart';
import 'savings_pockets.dart';
import 'savings_product.dart';

/// One pocket of a savings account: the money under one account code, which
/// the savings app shows as one goal.
class SavingsPocket {
  const SavingsPocket({
    required this.id,
    required this.accountId,
    required this.code,
    required this.name,
    this.lockedUntil,
    this.ignored = false,
    this.balanceMinor = 0,
    this.paidInMinor = 0,
    this.takenOutMinor = 0,
    this.interestMinor = 0,
    this.balanceSetAt,
    this.goalId,
    this.goalTargetMinor,
  });

  final int id;
  final int accountId;

  /// The account code payments carry, such as `CH12345`; empty for a pocket
  /// that holds money with no code.
  final String code;
  final String name;

  /// The day the savings app unlocks it; null when it is open.
  final CalendarDate? lockedUntil;

  /// The person said this code is not theirs. It holds nothing.
  final bool ignored;

  /// What it holds: the balance last typed and the money in and out since.
  final int balanceMinor;
  final int paidInMinor;
  final int takenOutMinor;
  final int interestMinor;

  /// When its balance was last typed; null when it never was.
  final DateTime? balanceSetAt;

  /// The Pesa Clarity goal saved in this pocket, and its target, in the
  /// account's currency. Null when no goal is.
  final int? goalId;
  final int? goalTargetMinor;

  bool get hasCode => code.isNotEmpty;

  /// Whether it is still locked on [day]. It opens on the day it is locked
  /// until.
  bool isLockedOn(CalendarDate day) =>
      lockedUntil != null && day.isBefore(lockedUntil!);
}

/// Money into or out of a savings account, as its page lists it.
class SavingsEntry {
  const SavingsEntry({
    required this.transactionId,
    required this.kind,
    required this.at,
    required this.amountMinor,
    this.pocketId,
    this.otherAccountId,
    this.otherTransactionId,
  });

  /// The entry on the savings account.
  final int transactionId;

  /// [SavingsEntryKind.paidIn] or [SavingsEntryKind.takenOut].
  final SavingsEntryKind kind;
  final DateTime at;

  /// Always positive; [kind] says which way it moved.
  final int amountMinor;

  /// The pocket it is in; null while it is in none.
  final int? pocketId;

  /// The account the money came from or went to, and the transaction there,
  /// such as the M-Pesa payment. Null for money the person typed in.
  final int? otherAccountId;
  final int? otherTransactionId;

  bool get isPaidIn => kind == SavingsEntryKind.paidIn;

  /// Signed: paid in is positive, taken out negative.
  int get signedMinor => isPaidIn ? amountMinor : -amountMinor;
}

/// A transaction that is part of a savings account the app keeps: an entry
/// on it, or the payment on another account that an entry mirrors.
class SavingsEntryLink {
  const SavingsEntryLink({
    required this.accountId,
    required this.entryTransactionId,
    required this.kind,
    this.pocketId,
    this.readingAt,
  });

  /// The savings account.
  final int accountId;

  /// The entry on the savings account: the transaction asked about, or its
  /// other side.
  final int entryTransactionId;
  final SavingsEntryKind kind;
  final int? pocketId;

  /// For interest and corrections, the update of the balance they come
  /// from: undoing them is undoing that update.
  final DateTime? readingAt;

  /// Whether the app worked the entry out from a typed balance.
  bool get isDerived =>
      kind == SavingsEntryKind.interest || kind == SavingsEntryKind.correction;
}

/// What an account needs said about one of its pockets.
class PocketFacts {
  const PocketFacts({
    required this.id,
    required this.code,
    required this.name,
    this.lockedUntil,
    this.ignored = false,
    this.goalId,
    this.goalTargetMinor,
  });

  final int id;
  final String code;
  final String name;
  final CalendarDate? lockedUntil;
  final bool ignored;
  final int? goalId;
  final int? goalTargetMinor;
}

/// A savings account the app keeps, as its page and My accounts show it.
class SavingsAccountSummary {
  const SavingsAccountSummary({
    required this.accountId,
    required this.name,
    required this.productId,
    required this.currency,
    required this.pockets,
    required this.ignoredPockets,
    required this.entries,
    required this.updates,
    required this.balanceMinor,
    required this.putInMinor,
    required this.takenOutMinor,
    required this.interestMinor,
    required this.wasThereBeforeMinor,
    required this.otherChangesMinor,
    this.product,
    this.balanceSetAt,
  });

  /// Works the account out from its pockets, the money in and out
  /// ([entries], in any order) and the balances typed ([readings], by
  /// pocket id).
  ///
  /// The balance is every pocket's balance and the entries in no pocket
  /// yet, so it always equals what the account's own transactions add up
  /// to: [putInMinor] less [takenOutMinor], plus [interestMinor],
  /// [wasThereBeforeMinor] and [otherChangesMinor].
  factory SavingsAccountSummary.of({
    required int accountId,
    required String name,
    required String productId,
    required String currency,
    required Iterable<PocketFacts> pockets,
    required Iterable<SavingsEntry> entries,
    required Map<int, List<PocketReading>> readings,
    SavingsProduct? product,
  }) {
    final live = [
      for (final p in pockets)
        if (!p.ignored) p,
    ];
    final liveIds = {for (final p in live) p.id};
    final moves = [
      for (final e in entries)
        if (e.kind == SavingsEntryKind.paidIn ||
            e.kind == SavingsEntryKind.takenOut)
          e,
    ]..sort(_newestFirst);
    final settled = settleAccount(
      flows: {
        for (final p in live)
          p.id: [
            for (final e in moves)
              if (e.pocketId == p.id) PocketFlow(e.at, e.signedMinor),
          ],
      },
      readings: {
        for (final p in live) p.id: readings[p.id] ?? const <PocketReading>[],
      },
    );
    final loose = moves.where((e) => !liveIds.contains(e.pocketId));
    final pocketsTotal = settled.pockets.values.fold(
      0,
      (sum, p) => sum + p.balanceMinor,
    );
    SavingsPocket view(PocketFacts p, [PocketSettlement? s]) => SavingsPocket(
      id: p.id,
      accountId: accountId,
      code: p.code,
      name: p.name,
      lockedUntil: p.lockedUntil,
      ignored: p.ignored,
      balanceMinor: s?.balanceMinor ?? 0,
      paidInMinor: s?.paidInMinor ?? 0,
      takenOutMinor: s?.takenOutMinor ?? 0,
      interestMinor: s?.interestMinor ?? 0,
      balanceSetAt: s?.lastSetAt,
      goalId: p.goalId,
      goalTargetMinor: p.goalTargetMinor,
    );
    final updates = settled.updates.reversed.toList();
    return SavingsAccountSummary(
      accountId: accountId,
      name: name,
      productId: productId,
      product: product,
      currency: currency,
      pockets: List.unmodifiable([
        for (final p in live) view(p, settled.pockets[p.id]),
      ]),
      ignoredPockets: List.unmodifiable([
        for (final p in pockets)
          if (p.ignored) view(p),
      ]),
      entries: List.unmodifiable(moves),
      updates: List.unmodifiable(updates),
      balanceMinor:
          pocketsTotal + loose.fold(0, (sum, e) => sum + e.signedMinor),
      putInMinor: moves
          .where((e) => e.isPaidIn)
          .fold(0, (sum, e) => sum + e.amountMinor),
      takenOutMinor: moves
          .where((e) => !e.isPaidIn)
          .fold(0, (sum, e) => sum + e.amountMinor),
      interestMinor: updates.fold(0, (sum, u) => sum + u.interestMinor),
      wasThereBeforeMinor: updates.fold(
        0,
        (sum, u) => sum + u.wasThereBeforeMinor,
      ),
      otherChangesMinor: updates.fold(0, (sum, u) => sum + u.otherChangesMinor),
      balanceSetAt: updates.isEmpty ? null : updates.first.at,
    );
  }

  final int accountId;

  /// The account's name, which the person can change.
  final String name;

  /// The product's id as kept on the account, and the product when this
  /// app knows it.
  final String productId;
  final SavingsProduct? product;
  final String currency;

  /// The pockets that hold money, in the order they were first seen.
  final List<SavingsPocket> pockets;

  /// Pockets the person said are not theirs.
  final List<SavingsPocket> ignoredPockets;

  /// Money paid in and taken out, newest first.
  final List<SavingsEntry> entries;

  /// Each time balances were typed and what that showed, newest first.
  final List<UpdateOutcome> updates;

  /// What the account holds.
  final int balanceMinor;

  /// Everything paid in and taken out, both positive.
  final int putInMinor;
  final int takenOutMinor;

  /// Interest the typed balances showed.
  final int interestMinor;

  /// Money a first typed balance showed was there before the records start.
  final int wasThereBeforeMinor;

  /// Other changes a typed balance showed that nothing recorded explains,
  /// signed.
  final int otherChangesMinor;

  /// When a balance was last typed; null when none ever was.
  final DateTime? balanceSetAt;

  /// Money in or out that is in no pocket yet. Each needs a pocket before
  /// balances are typed, so a balance is not set against money it does not
  /// know about.
  List<SavingsEntry> get unassigned {
    final ids = {for (final p in pockets) p.id};
    return [
      for (final e in entries)
        if (!ids.contains(e.pocketId)) e,
    ];
  }

  /// Whether there is more than one pocket, so balances are typed for each.
  bool get hasSeveralPockets => pockets.length > 1;

  /// How many pockets are still locked on [day].
  int lockedCount(CalendarDate day) =>
      pockets.where((p) => p.isLockedOn(day)).length;

  SavingsPocket? pocket(int? id) {
    for (final p in pockets) {
      if (p.id == id) return p;
    }
    return null;
  }
}

int _newestFirst(SavingsEntry a, SavingsEntry b) {
  final byTime = b.at.compareTo(a.at);
  return byTime != 0 ? byTime : b.transactionId.compareTo(a.transactionId);
}
