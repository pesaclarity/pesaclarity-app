import '../time/calendar.dart';

/// Money into a pocket (positive) or out of it (negative).
class PocketFlow {
  const PocketFlow(this.at, this.amountMinor);

  final DateTime at;

  /// Signed: paid in is positive, taken out negative.
  final int amountMinor;
}

/// A balance the person typed for a pocket, as the savings app showed it.
class PocketReading {
  const PocketReading({
    required this.at,
    required this.balanceMinor,
    this.gapIsInterest = true,
  });

  final DateTime at;
  final int balanceMinor;

  /// False once the person says what the balance shows beyond the records
  /// is not interest.
  final bool gapIsInterest;
}

/// What one typed balance showed that the money paid in and taken out does
/// not explain.
class ReadingOutcome {
  const ReadingOutcome({
    required this.at,
    required this.balanceMinor,
    required this.expectedMinor,
    required this.interestMinor,
    required this.correctionMinor,
    required this.isFirst,
  });

  final DateTime at;

  /// What the person typed.
  final int balanceMinor;

  /// What the records gave: the balance typed before, or nothing, and the
  /// money paid in and taken out since.
  final int expectedMinor;

  /// The part of the gap taken as interest: never below zero.
  final int interestMinor;

  /// The rest of the gap, signed: never income or spending.
  final int correctionMinor;

  /// Whether this is the pocket's first typed balance.
  final bool isFirst;

  int get gapMinor => balanceMinor - expectedMinor;

  /// Money the first balance showed that was there before the records
  /// start.
  int get wasThereBeforeMinor =>
      isFirst && correctionMinor > 0 ? correctionMinor : 0;

  /// Any other change nothing recorded explains, signed.
  int get otherChangeMinor => correctionMinor - wasThereBeforeMinor;
}

/// One pocket worked out from its flows and typed balances.
class PocketSettlement {
  const PocketSettlement({
    required this.outcomes,
    required this.balanceMinor,
    required this.paidInMinor,
    required this.takenOutMinor,
  });

  static const empty = PocketSettlement(
    outcomes: [],
    balanceMinor: 0,
    paidInMinor: 0,
    takenOutMinor: 0,
  );

  /// One per typed balance, oldest first.
  final List<ReadingOutcome> outcomes;

  /// What the pocket holds: the last typed balance and the flows after it,
  /// or before any balance, what was paid in less what was taken out.
  final int balanceMinor;

  /// Everything paid in and taken out, both positive.
  final int paidInMinor;
  final int takenOutMinor;

  int get interestMinor => outcomes.fold(0, (sum, o) => sum + o.interestMinor);

  int get wasThereBeforeMinor =>
      outcomes.fold(0, (sum, o) => sum + o.wasThereBeforeMinor);

  int get otherChangesMinor =>
      outcomes.fold(0, (sum, o) => sum + o.otherChangeMinor);

  /// When the balance was last typed; null when it never was.
  DateTime? get lastSetAt => outcomes.isEmpty ? null : outcomes.last.at;
}

/// The most a pocket's first typed balance may be above what was paid in
/// and still be taken as interest: this much of it for each month, or part
/// of one, since the first payment found.
const setupInterestPercentPerMonth = 2;

/// Whether the gap between a pocket's first typed balance and what the
/// records show was paid in is interest, rather than money that was there
/// before the records start.
///
/// The messages read may go back only a few months, so the first balance
/// can hold money the app never saw paid in. A gap of up to
/// [setupInterestPercentPerMonth] percent of [netPaidInMinor] for each
/// month, or part of one, from [firstPaymentAt] to [at] is interest;
/// anything larger was there before. With nothing paid in, nothing is
/// interest.
bool setupGapIsInterest({
  required int gapMinor,
  required int netPaidInMinor,
  required DateTime? firstPaymentAt,
  required DateTime at,
}) {
  if (gapMinor <= 0 || netPaidInMinor <= 0 || firstPaymentAt == null) {
    return false;
  }
  final days = at.difference(firstPaymentAt).inDays;
  final months = (days < 0 ? 0 : days) ~/ 30 + 1;
  return gapMinor <=
      netPaidInMinor * setupInterestPercentPerMonth * months ~/ 100;
}

/// Works out one pocket from its [flows] and the balances typed for it
/// ([readings]), in time order.
///
/// A typed balance covers the flows up to and including its own time. What
/// it shows above the balance before it and the flows since is interest;
/// what it shows below, and any gap the person said is not interest, is a
/// correction. The first balance counts as interest only when
/// [setupGapIsInterest] says so, and is otherwise money that was there
/// before. Nothing here is fixed when a balance is typed: when an older
/// payment turns up later, the interest of the balance that already held it
/// shrinks by that much.
PocketSettlement settlePocket({
  required Iterable<PocketFlow> flows,
  required Iterable<PocketReading> readings,
}) {
  final moves = flows.toList()..sort((a, b) => a.at.compareTo(b.at));
  final typed = readings.toList()..sort((a, b) => a.at.compareTo(b.at));
  var paidIn = 0;
  var takenOut = 0;
  for (final m in moves) {
    if (m.amountMinor >= 0) {
      paidIn += m.amountMinor;
    } else {
      takenOut -= m.amountMinor;
    }
  }

  final outcomes = <ReadingOutcome>[];
  var running = 0;
  var next = 0;
  for (final reading in typed) {
    while (next < moves.length && !moves[next].at.isAfter(reading.at)) {
      running += moves[next].amountMinor;
      next++;
    }
    final isFirst = outcomes.isEmpty;
    final gap = reading.balanceMinor - running;
    final interest =
        gap > 0 &&
        reading.gapIsInterest &&
        (!isFirst ||
            setupGapIsInterest(
              gapMinor: gap,
              netPaidInMinor: running,
              firstPaymentAt: next == 0 ? null : moves.first.at,
              at: reading.at,
            ));
    outcomes.add(
      ReadingOutcome(
        at: reading.at,
        balanceMinor: reading.balanceMinor,
        expectedMinor: running,
        interestMinor: interest ? gap : 0,
        correctionMinor: interest ? 0 : gap,
        isFirst: isFirst,
      ),
    );
    running = reading.balanceMinor;
  }
  for (; next < moves.length; next++) {
    running += moves[next].amountMinor;
  }
  return PocketSettlement(
    outcomes: List.unmodifiable(outcomes),
    balanceMinor: running,
    paidInMinor: paidIn,
    takenOutMinor: takenOut,
  );
}

/// What one update of an account's balances showed across its pockets.
class UpdateOutcome {
  const UpdateOutcome({
    required this.at,
    required this.balanceMinor,
    required this.interestMinor,
    required this.wasThereBeforeMinor,
    required this.otherChangesMinor,
    required this.pocketIds,
  });

  final DateTime at;

  /// The balances typed at this time, added up.
  final int balanceMinor;
  final int interestMinor;
  final int wasThereBeforeMinor;

  /// Signed.
  final int otherChangesMinor;

  /// The pockets a balance was typed for.
  final List<int> pocketIds;

  /// What the update records beside interest, signed: one correction.
  int get correctionMinor => wasThereBeforeMinor + otherChangesMinor;

  /// What the update changed the account by.
  int get changeMinor => interestMinor + correctionMinor;
}

/// Every pocket of an account worked out, and what each update showed.
class AccountSettlement {
  const AccountSettlement({required this.pockets, required this.updates});

  /// By pocket id.
  final Map<int, PocketSettlement> pockets;

  /// One per time balances were typed, oldest first.
  final List<UpdateOutcome> updates;
}

/// Works out each pocket in [flows] and [readings] (both by pocket id) with
/// [settlePocket], and adds up what the balances typed at one time showed,
/// which the account records as one interest entry and one correction.
AccountSettlement settleAccount({
  required Map<int, List<PocketFlow>> flows,
  required Map<int, List<PocketReading>> readings,
}) {
  final pockets = <int, PocketSettlement>{};
  final byTime = <int, List<(int, ReadingOutcome)>>{};
  for (final id in {...flows.keys, ...readings.keys}) {
    final settled = settlePocket(
      flows: flows[id] ?? const [],
      readings: readings[id] ?? const [],
    );
    pockets[id] = settled;
    for (final outcome in settled.outcomes) {
      (byTime[_second(outcome.at)] ??= []).add((id, outcome));
    }
  }
  final times = byTime.keys.toList()..sort();
  return AccountSettlement(
    pockets: pockets,
    updates: [
      for (final time in times)
        UpdateOutcome(
          at: byTime[time]!.first.$2.at,
          balanceMinor: byTime[time]!.fold(
            0,
            (sum, o) => sum + o.$2.balanceMinor,
          ),
          interestMinor: byTime[time]!.fold(
            0,
            (sum, o) => sum + o.$2.interestMinor,
          ),
          wasThereBeforeMinor: byTime[time]!.fold(
            0,
            (sum, o) => sum + o.$2.wasThereBeforeMinor,
          ),
          otherChangesMinor: byTime[time]!.fold(
            0,
            (sum, o) => sum + o.$2.otherChangeMinor,
          ),
          pocketIds: [for (final o in byTime[time]!) o.$1]..sort(),
        ),
    ],
  );
}

/// Times are kept to the second, so two at the same second are one time.
int _second(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;

/// A pocket as the money-back rule sees it.
typedef PocketLock = ({int id, CalendarDate? lockedUntil});

/// The pocket money taken out on [day] came from, among the account's
/// [pockets], or null when the records cannot say: the only pocket, else
/// the only pocket not locked that day. A pocket locked until a day is open
/// from that day.
int? pocketForMoneyBack(Iterable<PocketLock> pockets, CalendarDate day) {
  final all = pockets.toList();
  if (all.length == 1) return all.single.id;
  final open = [
    for (final p in all)
      if (p.lockedUntil == null || !day.isBefore(p.lockedUntil!)) p,
  ];
  return open.length == 1 ? open.single.id : null;
}
