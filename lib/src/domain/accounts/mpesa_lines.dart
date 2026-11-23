import '../payees/payee_identifier.dart';
import '../spaces/space.dart';

/// Two or more M-Pesa lines on one phone (decision 0026, section 6).
///
/// Every line's messages come from `MPESA` and none says which number it is
/// for. On Android each message carries the SIM subscription it arrived on,
/// kept as an opaque key; on iPhone, or a phone that reports no SIM, the
/// balance every payment message prints tells the lines apart. Each line is
/// its own M-Pesa account once the person splits them: the account's
/// reference is [lineReference] of the line's id.

/// The institution whose lines these are.
const mpesaInstitutionId = 'mpesa';

const _referencePrefix = 'line:';
const _selectionPrefix = '$mpesaInstitutionId#';

/// Why a message waits in review: the balance it prints did not say which
/// line it was on ("Which line was this?").
const whichLineReason = 'mpesa_line_unknown';

/// The account reference of line [lineId]'s M-Pesa account.
String lineReference(String lineId) => '$_referencePrefix$lineId';

/// The line an account [reference] keys, or null for any other reference.
String? lineOfReference(String? reference) =>
    reference != null && reference.startsWith(_referencePrefix)
    ? reference.substring(_referencePrefix.length)
    : null;

/// The switched-on id that says a space reads line [lineId], kept beside
/// the institutions in each space, so a line, like an account, is read in
/// one space only.
String lineSelectionId(String lineId) => '$_selectionPrefix$lineId';

/// The line a switched-on [id] reads, or null for an institution.
String? lineOfSelection(String id) => id.startsWith(_selectionPrefix)
    ? id.substring(_selectionPrefix.length)
    : null;

/// What one M-Pesa message says that tells its line: the SIM it arrived on,
/// when it reports one, and how it moved the balance it prints. Amounts in
/// hundredths, as the readers give them.
class LineFacts {
  const LineFacts({
    required this.hash,
    required this.at,
    required this.amountMinor,
    required this.inflow,
    this.sim,
    this.feeMinor = 0,
    this.balanceMinor,
  });

  /// The message's hash, so a message is placed the same way when read
  /// again or by another space.
  final String hash;
  final DateTime at;
  final String? sim;
  final int amountMinor;
  final int feeMinor;
  final bool inflow;

  /// The balance the message prints after it, if any.
  final int? balanceMinor;

  /// The balance before this message, worked back from the one it prints.
  int? get balanceBefore => balanceMinor == null
      ? null
      : inflow
      ? balanceMinor! - amountMinor
      : balanceMinor! + amountMinor + feeMinor;
}

/// Whether [facts] carries on from [balance]: the balance before the
/// message, worked back from the one it prints, is [balance]. A payment
/// more than the wallet holds is covered by Fuliza and leaves it at nothing.
bool carriesOn(int? balance, LineFacts facts) {
  final printed = facts.balanceMinor;
  if (balance == null || printed == null) return false;
  if (facts.balanceBefore == balance) return true;
  return !facts.inflow &&
      printed == 0 &&
      balance - facts.amountMinor - facts.feeMinor < 0;
}

/// One M-Pesa line on this phone.
class MpesaLine {
  const MpesaLine({
    required this.id,
    this.sims = const {},
    this.name,
    this.spaceId = personalSpaceId,
    this.sharedWith,
    this.balanceMinor,
    this.balanceAt,
    this.firstAt,
    this.lastAt,
    this.messages = 0,
    this.tracked = true,
    this.number,
  });

  /// `1`, `2`, ... in the order the lines were first seen.
  final String id;

  /// The SIM subscriptions its messages arrived on. Empty on iPhone.
  final Set<String> sims;

  /// The name the person gave it, such as `Shop line`.
  final String? name;

  /// The space that reads it once the lines are split.
  final String spaceId;

  /// The business that asks about its payments, when the line is used for
  /// both ("Both"): it is then read in Personal.
  final String? sharedWith;

  /// The last balance its messages printed, and when.
  final int? balanceMinor;
  final DateTime? balanceAt;

  /// Its first and last message, and how many there were.
  final DateTime? firstAt;
  final DateTime? lastAt;
  final int messages;

  /// Off ("Don't track this line"): its new messages are skipped at every
  /// read, and its balance leaves every total. Its past records stay unless
  /// the person deleted them.
  final bool tracked;

  /// The line's phone number as the person typed it (`0712345678`), if
  /// they did. The app never reads it from the phone.
  final String? number;

  /// [number] masked for showing: `0712 ••• 678`.
  String? get maskedNumber {
    final n = number;
    if (n == null || n.length < 10) return null;
    return '${n.substring(0, 4)} ••• ${n.substring(n.length - 3)}';
  }

  /// `SIM 1` where the phone tells lines apart by SIM, else `Line 1`.
  String get slot => sims.isEmpty ? 'Line $id' : 'SIM $id';

  /// What the line is called: its name, or [slot] until it has one.
  String get label {
    final named = name?.trim();
    return named == null || named.isEmpty ? slot : named;
  }

  MpesaLine copyWith({
    Set<String>? sims,
    String? Function()? name,
    String? spaceId,
    String? Function()? sharedWith,
    int? Function()? balanceMinor,
    DateTime? Function()? balanceAt,
    DateTime? Function()? firstAt,
    DateTime? Function()? lastAt,
    int? messages,
    bool? tracked,
    String? Function()? number,
  }) => MpesaLine(
    id: id,
    sims: sims ?? this.sims,
    name: name == null ? this.name : name(),
    spaceId: spaceId ?? this.spaceId,
    sharedWith: sharedWith == null ? this.sharedWith : sharedWith(),
    balanceMinor: balanceMinor == null ? this.balanceMinor : balanceMinor(),
    balanceAt: balanceAt == null ? this.balanceAt : balanceAt(),
    firstAt: firstAt == null ? this.firstAt : firstAt(),
    lastAt: lastAt == null ? this.lastAt : lastAt(),
    messages: messages ?? this.messages,
    tracked: tracked ?? this.tracked,
    number: number == null ? this.number : number(),
  );

  /// Whether no message came from it for more than [oldAfter] before [now]:
  /// it folds under "Old lines".
  bool isOld(DateTime now) {
    final last = lastAt;
    return last == null || now.difference(last) > oldAfter;
  }

  /// This line with [facts] seen: counted, and its balance taken, when the
  /// message is newer than any seen. A message read again changes nothing.
  MpesaLine seen(LineFacts facts) {
    final last = lastAt;
    if (last != null && !facts.at.isAfter(last)) {
      final first = firstAt;
      return first != null && facts.at.isBefore(first)
          ? copyWith(firstAt: () => facts.at)
          : this;
    }
    return copyWith(
      sims: facts.sim == null ? sims : {...sims, facts.sim!},
      firstAt: () => firstAt ?? facts.at,
      lastAt: () => facts.at,
      messages: messages + 1,
      balanceMinor: facts.balanceMinor == null
          ? null
          : () => facts.balanceMinor,
      balanceAt: facts.balanceMinor == null ? null : () => facts.at,
    );
  }

  /// Whether this line and [other] were both in use at once: each has a
  /// message after the other's first. A line that stopped before another
  /// started is more likely one line on a new SIM or phone.
  bool overlaps(MpesaLine other) {
    final (a1, a2, b1, b2) = (firstAt, lastAt, other.firstAt, other.lastAt);
    if (a1 == null || a2 == null || b1 == null || b2 == null) return false;
    return a2.isAfter(b1) && b2.isAfter(a1);
  }

  static MpesaLine? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    DateTime? when(String key) => switch (json[key]) {
      final String s => DateTime.tryParse(s),
      _ => null,
    };
    final sims = json['sims'];
    final name = json['name'];
    final space = json['space'];
    final shared = json['sharedWith'];
    final balance = json['balance'];
    final messages = json['messages'];
    return MpesaLine(
      id: id,
      sims: {
        if (sims is List)
          for (final s in sims)
            if (s is String) s,
      },
      name: name is String ? name : null,
      spaceId: space is String ? space : personalSpaceId,
      sharedWith: shared is String ? shared : null,
      balanceMinor: balance is int ? balance : null,
      balanceAt: when('balanceAt'),
      firstAt: when('firstAt'),
      lastAt: when('lastAt'),
      messages: messages is int ? messages : 0,
      tracked: json['tracked'] != false,
      number: json['number'] is String ? json['number']! as String : null,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'sims': sims.toList(),
    'name': ?name,
    'space': spaceId,
    'sharedWith': ?sharedWith,
    'balance': ?balanceMinor,
    'balanceAt': ?balanceAt?.toUtc().toIso8601String(),
    'firstAt': ?firstAt?.toUtc().toIso8601String(),
    'lastAt': ?lastAt?.toUtc().toIso8601String(),
    'messages': messages,
    if (!tracked) 'tracked': false,
    'number': ?number,
  };
}

/// A line with no message for longer than this is old: it folds under
/// "Old lines" in M-Pesa lines.
const oldAfter = Duration(days: 90);

/// What a tracked line is to the person: its balance is M-Pesa's first on
/// Home ([main]), or is added to the M-Pesa total ([second]).
enum LineRole { main, second }

/// The quiet note the first time a message from an untracked line is
/// skipped: not yet ([none]), waiting to be seen ([due]), seen ([shown]).
enum SkipNote { none, due, shown }

/// A SIM not seen before, after the lines were split, whose first message
/// carried on from no line's balance: "Is this the same line as My line?".
class NewSim {
  const NewSim({
    required this.sim,
    required this.firstAt,
    this.firstBalanceMinor,
    this.asked = const {},
  });

  final String sim;
  final DateTime firstAt;
  final int? firstBalanceMinor;

  /// The lines the person already said it is not.
  final Set<String> asked;

  static NewSim? fromJson(Object? json) {
    if (json is! Map) return null;
    final sim = json['sim'];
    final at = json['firstAt'];
    final when = at is String ? DateTime.tryParse(at) : null;
    if (sim is! String || when == null) return null;
    final balance = json['firstBalance'];
    final asked = json['asked'];
    return NewSim(
      sim: sim,
      firstAt: when,
      firstBalanceMinor: balance is int ? balance : null,
      asked: {
        if (asked is List)
          for (final a in asked)
            if (a is String) a,
      },
    );
  }

  Map<String, Object?> toJson() => {
    'sim': sim,
    'firstAt': firstAt.toUtc().toIso8601String(),
    'firstBalance': ?firstBalanceMinor,
    'asked': asked.toList(),
  };
}

/// Where one message goes.
sealed class LinePlace {
  const LinePlace();
}

/// On line [lineId].
final class OnLine extends LinePlace {
  const OnLine(this.lineId);

  final String lineId;

  @override
  bool operator ==(Object other) => other is OnLine && other.lineId == lineId;

  @override
  int get hashCode => lineId.hashCode;

  @override
  String toString() => 'OnLine($lineId)';
}

/// The balance cannot say which: "Which line was this?".
final class AskWhichLine extends LinePlace {
  const AskWhichLine();

  @override
  bool operator ==(Object other) => other is AskWhichLine;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'AskWhichLine()';
}

/// From a SIM waiting on "Is this the same line?": read once answered.
final class WaitForSim extends LinePlace {
  const WaitForSim(this.sim);

  final String sim;

  @override
  bool operator ==(Object other) => other is WaitForSim && other.sim == sim;

  @override
  int get hashCode => sim.hashCode;

  @override
  String toString() => 'WaitForSim($sim)';
}

/// On line [lineId], which the person stopped tracking: skipped.
final class NotTracked extends LinePlace {
  const NotTracked(this.lineId);

  final String lineId;

  @override
  bool operator ==(Object other) =>
      other is NotTracked && other.lineId == lineId;

  @override
  int get hashCode => Object.hash('skip', lineId);

  @override
  String toString() => 'NotTracked($lineId)';
}

/// Most placements by balance remembered, newest kept.
const placedLimit = 1000;

/// Every M-Pesa line this phone has seen, and what the person chose for
/// them. Kept in Personal's settings, so every space places a message the
/// same way.
class MpesaLines {
  const MpesaLines({
    this.lines = const [],
    this.split = false,
    this.offerHidden = false,
    this.placed = const {},
    this.newSims = const [],
    this.readFrom = const {},
    this.readUntil = const {},
    this.surveyed = false,
    this.mainId,
    this.secondId,
    this.quickSetupDone = false,
    this.skipNote = SkipNote.none,
    this.skippedLineId,
  });

  /// Reads saved lines; anything malformed is left out.
  factory MpesaLines.fromJson(Map<String, Object?>? json) {
    if (json == null) return empty;
    Map<String, DateTime> times(Object? raw) => {
      if (raw is Map)
        for (final MapEntry(:key, :value) in raw.entries)
          if (key is String && value is String) key: ?DateTime.tryParse(value),
    };
    final lines = json['lines'];
    final placed = json['placed'];
    final sims = json['newSims'];
    return MpesaLines(
      lines: [
        if (lines is List)
          for (final l in lines) ?MpesaLine.fromJson(l),
      ],
      split: json['split'] == true,
      offerHidden: json['offerHidden'] == true,
      placed: {
        if (placed is Map)
          for (final MapEntry(:key, :value) in placed.entries)
            if (key is String && value is String) key: value,
      },
      newSims: [
        if (sims is List)
          for (final s in sims) ?NewSim.fromJson(s),
      ],
      readFrom: times(json['readFrom']),
      readUntil: times(json['readUntil']),
      surveyed: json['surveyed'] == true,
      mainId: json['main'] is String ? json['main']! as String : null,
      secondId: json['second'] is String ? json['second']! as String : null,
      quickSetupDone: json['quickSetup'] == true,
      skipNote:
          SkipNote.values
              .where((n) => n.name == json['skipNote'])
              .firstOrNull ??
          SkipNote.none,
      skippedLineId: json['skippedLine'] is String
          ? json['skippedLine']! as String
          : null,
    );
  }

  static const empty = MpesaLines();

  final List<MpesaLine> lines;

  /// Whether each line is its own account. Until the person splits them,
  /// every line is read into one M-Pesa account, as before.
  final bool split;

  /// "Not now" on the offer to split.
  final bool offerHidden;

  /// Messages placed by their balance, by hash: read again, or by another
  /// space, they go to the same line.
  final Map<String, String> placed;

  /// SIMs waiting on "Is this the same line?".
  final List<NewSim> newSims;

  /// Spaces that read their lines' messages again from a time, once an
  /// answer about a SIM sends them messages they skipped.
  final Map<String, DateTime> readFrom;

  /// How far each space has read the iPhone's queue of M-Pesa messages: the
  /// queue lets go only of what every space reading a line has read.
  final Map<String, DateTime> readUntil;

  /// Whether the lines were counted from the whole inbox once.
  final bool surveyed;

  /// The main line and the second line the person chose, if any.
  final String? mainId;
  final String? secondId;

  /// Whether "Keep my 2 most recent lines" was used: it is not offered
  /// again.
  final bool quickSetupDone;

  /// The quiet note on the first message skipped from an untracked line,
  /// and the line it was from.
  final SkipNote skipNote;
  final String? skippedLineId;

  Map<String, Object?> toJson() => {
    'lines': [for (final l in lines) l.toJson()],
    'split': split,
    'offerHidden': offerHidden,
    'placed': placed,
    'newSims': [for (final s in newSims) s.toJson()],
    'readFrom': {
      for (final MapEntry(:key, :value) in readFrom.entries)
        key: value.toUtc().toIso8601String(),
    },
    'readUntil': {
      for (final MapEntry(:key, :value) in readUntil.entries)
        key: value.toUtc().toIso8601String(),
    },
    'surveyed': surveyed,
    'main': ?mainId,
    'second': ?secondId,
    'quickSetup': quickSetupDone,
    'skipNote': skipNote.name,
    'skippedLine': ?skippedLineId,
  };

  MpesaLines copyWith({
    List<MpesaLine>? lines,
    bool? split,
    bool? offerHidden,
    Map<String, String>? placed,
    List<NewSim>? newSims,
    Map<String, DateTime>? readFrom,
    Map<String, DateTime>? readUntil,
    bool? surveyed,
    String? Function()? mainId,
    String? Function()? secondId,
    bool? quickSetupDone,
    SkipNote? skipNote,
    String? Function()? skippedLineId,
  }) => MpesaLines(
    lines: lines ?? this.lines,
    split: split ?? this.split,
    offerHidden: offerHidden ?? this.offerHidden,
    placed: placed ?? this.placed,
    newSims: newSims ?? this.newSims,
    readFrom: readFrom ?? this.readFrom,
    readUntil: readUntil ?? this.readUntil,
    surveyed: surveyed ?? this.surveyed,
    mainId: mainId == null ? this.mainId : mainId(),
    secondId: secondId == null ? this.secondId : secondId(),
    quickSetupDone: quickSetupDone ?? this.quickSetupDone,
    skipNote: skipNote ?? this.skipNote,
    skippedLineId: skippedLineId == null ? this.skippedLineId : skippedLineId(),
  );

  MpesaLine? line(String id) => lines.where((l) => l.id == id).firstOrNull;

  /// Whether the phone tells these lines apart by SIM.
  bool get bySim => lines.any((l) => l.sims.isNotEmpty);

  /// The lines to show: once split, every line; before, those in use at the
  /// same time as another, so a line replaced by a new SIM or phone is not
  /// offered as a second one.
  List<MpesaLine> get shown => split
      ? lines
      : [
          for (final l in lines)
            if (lines.any((o) => o.id != l.id && l.overlaps(o))) l,
        ];

  /// Two lines in use and read as one: offer to split them.
  bool get offersSplit => !split && shown.length >= 2;

  /// Whether "M-Pesa lines" belongs in My accounts: once two lines have
  /// been seen.
  bool get twoSeen => shown.length >= 2;

  /// The space that reads [line]: its own, when that space is still on the
  /// phone ([listed]), else Personal.
  String readerOf(MpesaLine line, Set<String> listed) =>
      line.spaceId == personalSpaceId || listed.contains(line.spaceId)
      ? line.spaceId
      : personalSpaceId;

  MpesaLines _with(MpesaLine line) => copyWith(
    lines: [
      for (final l in lines)
        if (l.id == line.id) line else l,
      if (!lines.any((l) => l.id == line.id)) line,
    ],
  );

  String get _nextId {
    var n = 1;
    final ids = {for (final l in lines) l.id};
    while (ids.contains('$n')) {
      n++;
    }
    return '$n';
  }

  MpesaLines _remember(String hash, String lineId) {
    final next = {...placed}
      ..remove(hash)
      ..[hash] = lineId;
    while (next.length > placedLimit) {
      next.remove(next.keys.first);
    }
    return copyWith(placed: next);
  }

  /// The line seen most lately among [among].
  MpesaLine _latest(Iterable<MpesaLine> among) => among.reduce(
    (a, b) =>
        (b.lastAt ?? DateTime(0)).isAfter(a.lastAt ?? DateTime(0)) ? b : a,
  );

  /// Where [facts] goes, and these lines with it seen.
  ///
  /// A message placed before goes where it went. One from a SIM goes to the
  /// line of that SIM. A SIM not seen before joins the line whose balance
  /// its message carries on; failing that it is a new line, or, once the
  /// lines are split, it waits on "Is this the same line?". With no SIM the
  /// balance decides; when it cannot, a message before the split goes to
  /// the line used last (they are one account then) and one after asks
  /// "Which line was this?".
  ///
  /// A message on a line the person stopped tracking is skipped
  /// ([NotTracked]); the line still counts it, so its balance chain carries
  /// on. The first one skipped leaves the quiet note due.
  (MpesaLines, LinePlace) place(LineFacts facts) {
    final (next, at) = _place(facts);
    if (at case OnLine(:final lineId)) {
      final line = next.line(lineId);
      if (line != null && !line.tracked) {
        return (
          next.skipNote == SkipNote.none
              ? next.copyWith(
                  skipNote: SkipNote.due,
                  skippedLineId: () => lineId,
                )
              : next,
          NotTracked(lineId),
        );
      }
    }
    return (next, at);
  }

  (MpesaLines, LinePlace) _place(LineFacts facts) {
    final known = placed[facts.hash];
    if (known != null && line(known) != null) {
      return (this, OnLine(known));
    }
    final sim = facts.sim;
    if (sim != null) {
      final bySim = lines.where((l) => l.sims.contains(sim)).firstOrNull;
      if (bySim != null) return (_with(bySim.seen(facts)), OnLine(bySim.id));
      if (newSims.any((q) => q.sim == sim)) return (this, WaitForSim(sim));
      final carried = [
        for (final l in lines)
          if (carriesOn(l.balanceMinor, facts)) l,
      ];
      if (carried.length == 1) {
        final joined = carried.single.copyWith(
          sims: {...carried.single.sims, sim},
        );
        return (_with(joined.seen(facts)), OnLine(joined.id));
      }
      if (split && lines.isNotEmpty) {
        return (
          copyWith(
            newSims: [
              ...newSims,
              NewSim(
                sim: sim,
                firstAt: facts.at,
                firstBalanceMinor: facts.balanceMinor,
              ),
            ],
          ),
          WaitForSim(sim),
        );
      }
      final fresh = MpesaLine(id: _nextId, sims: {sim}).seen(facts);
      return (_with(fresh), OnLine(fresh.id));
    }

    if (lines.isEmpty) {
      final fresh = MpesaLine(id: _nextId).seen(facts);
      return (_with(fresh)._remember(facts.hash, fresh.id), OnLine(fresh.id));
    }
    final carried = [
      for (final l in lines)
        if (carriesOn(l.balanceMinor, facts)) l,
    ];
    MpesaLine? pick;
    if (carried.length == 1) {
      pick = carried.single;
    } else if (lines.length == 1) {
      pick = lines.single;
    } else if (!split) {
      // Read as one account anyway: follow the line used last.
      // A line no longer tracked is not guessed at.
      final tracked = [
        for (final l in lines)
          if (l.tracked) l,
      ];
      pick = _latest(
        carried.isNotEmpty
            ? carried
            : tracked.isEmpty
            ? lines
            : tracked,
      );
    }
    if (pick == null) return (this, const AskWhichLine());
    // Before the split, a balance no line explains starts a second line.
    if (carried.isEmpty &&
        !split &&
        lines.length < 2 &&
        facts.balanceMinor != null) {
      final fresh = MpesaLine(id: _nextId).seen(facts);
      return (_with(fresh)._remember(facts.hash, fresh.id), OnLine(fresh.id));
    }
    return (
      _with(pick.seen(facts))._remember(facts.hash, pick.id),
      OnLine(pick.id),
    );
  }

  /// Places every one of [facts] in order.
  (MpesaLines, List<LinePlace>) placeAll(Iterable<LineFacts> facts) {
    var lines = this;
    final places = <LinePlace>[];
    for (final f in facts) {
      final (next, place) = lines.place(f);
      lines = next;
      places.add(place);
    }
    return (lines, places);
  }

  /// [facts], whose line the person chose: [lineId]. Remembered, so it is
  /// read there, and its balance carries the line on.
  MpesaLines placedOn(LineFacts facts, String lineId) {
    final target = line(lineId);
    if (target == null) return this;
    return _with(target.seen(facts))._remember(facts.hash, lineId);
  }

  /// These lines counted afresh from [facts], the whole inbox, oldest
  /// first: names, SIMs and choices stay; counts and balances are redone.
  MpesaLines counted(Iterable<LineFacts> facts) {
    var fresh = copyWith(
      lines: [
        for (final l in lines)
          l.copyWith(
            balanceMinor: () => null,
            balanceAt: () => null,
            firstAt: () => null,
            lastAt: () => null,
            messages: 0,
          ),
      ],
    );
    for (final f in facts) {
      fresh = fresh.place(f).$1;
    }
    return fresh.copyWith(surveyed: true);
  }

  /// The SIM question to ask next, and the line it asks about: the line
  /// used last that the person has not ruled out.
  (NewSim, MpesaLine)? get nextSimQuestion {
    for (final q in newSims) {
      final left = [
        for (final l in lines)
          if (!q.asked.contains(l.id)) l,
      ];
      if (left.isNotEmpty) return (q, _latest(left));
    }
    return null;
  }

  /// The answer to "Is [sim] the same line as [lineId]?". Yes adds the SIM
  /// to that line; no asks about the next line, and once every line is
  /// ruled out the SIM is a new line. Either way, once settled, [readerOf]
  /// the line reads the messages the SIM sent from its first.
  MpesaLines answerSim(
    String sim,
    String lineId, {
    required bool same,
    required Set<String> listed,
  }) {
    final q = newSims.where((s) => s.sim == sim).firstOrNull;
    if (q == null) return this;
    final rest = [
      for (final s in newSims)
        if (s.sim != sim) s,
    ];
    MpesaLine? settled;
    if (same) {
      final target = line(lineId);
      if (target == null) return this;
      settled = target.copyWith(sims: {...target.sims, sim});
    } else {
      final asked = {...q.asked, lineId};
      if (lines.any((l) => !asked.contains(l.id))) {
        return copyWith(
          newSims: [
            for (final s in newSims)
              if (s.sim == sim)
                NewSim(
                  sim: s.sim,
                  firstAt: s.firstAt,
                  firstBalanceMinor: s.firstBalanceMinor,
                  asked: asked,
                )
              else
                s,
          ],
        );
      }
      settled = MpesaLine(id: _nextId, sims: {sim});
    }
    final reader = readerOf(settled, listed);
    final from = readFrom[reader];
    return _with(settled).copyWith(
      newSims: rest,
      readFrom: {
        ...readFrom,
        reader: from == null || q.firstAt.isBefore(from) ? q.firstAt : from,
      },
    );
  }

  /// [spaceId] has read again what it was sent.
  MpesaLines readDone(String spaceId) =>
      copyWith(readFrom: {...readFrom}..remove(spaceId));

  /// Line [lineId] named [name] and read in [spaceId], shared with
  /// [sharedWith] when used for both.
  MpesaLines withChoice(
    String lineId, {
    String? name,
    String? spaceId,
    String? Function()? sharedWith,
  }) {
    final target = line(lineId);
    if (target == null) return this;
    final trimmed = name?.trim();
    return _with(
      target.copyWith(
        name: name == null
            ? null
            : () => trimmed == null || trimmed.isEmpty ? null : trimmed,
        spaceId: spaceId,
        sharedWith: sharedWith,
      ),
    );
  }

  /// These lines with what is gone from the phone taken out: a space
  /// deleted since gives its lines back to Personal.
  MpesaLines onlyFor(Set<String> listed) => copyWith(
    lines: [
      for (final l in lines)
        if (readerOf(l, listed) != l.spaceId ||
            (l.sharedWith != null && !listed.contains(l.sharedWith)))
          l.copyWith(
            spaceId: readerOf(l, listed),
            sharedWith: () =>
                l.sharedWith != null && listed.contains(l.sharedWith)
                ? l.sharedWith
                : null,
          )
        else
          l,
    ],
  );

  /// Every line, the one with the latest message first.
  List<MpesaLine> get newestFirst => [...lines]
    ..sort(
      (a, b) => (b.lastAt ?? DateTime(0)).compareTo(a.lastAt ?? DateTime(0)),
    );

  /// The lines still tracked.
  List<MpesaLine> get tracked => [
    for (final l in lines)
      if (l.tracked) l,
  ];

  /// How many lines are not tracked.
  int get untrackedCount => lines.length - tracked.length;

  /// What [lineId] is, if the person chose.
  LineRole? roleOf(String lineId) => lineId == mainId
      ? LineRole.main
      : lineId == secondId
      ? LineRole.second
      : null;

  /// Where an account keyed by [reference] sorts among M-Pesa lines: the
  /// main line first, then the second, then any other account.
  int rankOf(String? reference) => switch (lineOfReference(reference)) {
    final id? when id == mainId => 0,
    final id? when id == secondId => 1,
    _ => 2,
  };

  /// "Keep my 2 most recent lines, set the rest aside": offered while more
  /// than two lines are seen, until used once.
  bool get offersQuickSetup => lines.length > 2 && !quickSetupDone;

  /// The two lines with the latest messages, kept by the quick setup, and
  /// the rest, set aside, newest first.
  (List<MpesaLine>, List<MpesaLine>) get quickSetupSplit {
    final all = newestFirst;
    return (all.take(2).toList(), all.skip(2).toList());
  }

  /// The quick setup used: the newest line is the main line, the next the
  /// second; the rest stop being tracked, their past records kept.
  MpesaLines keepTwoMostRecent() {
    final (kept, aside) = quickSetupSplit;
    final keep = {for (final l in kept) l.id};
    return copyWith(
      lines: [for (final l in lines) l.copyWith(tracked: keep.contains(l.id))],
      mainId: () => kept.firstOrNull?.id,
      secondId: () => kept.length > 1 ? kept[1].id : null,
      quickSetupDone: true,
    );
  }

  /// [lineId] made the [role] line, tracked again if it was not. The line
  /// that had the role before has none.
  MpesaLines withRole(String lineId, LineRole role) {
    final target = line(lineId);
    if (target == null) return this;
    return _with(target.copyWith(tracked: true)).copyWith(
      mainId: () => role == LineRole.main
          ? lineId
          : mainId == lineId
          ? null
          : mainId,
      secondId: () => role == LineRole.second
          ? lineId
          : secondId == lineId
          ? null
          : secondId,
    );
  }

  /// "Don't track this line": its new messages are skipped, and it has no
  /// role.
  MpesaLines untracked(String lineId) {
    final target = line(lineId);
    if (target == null) return this;
    return _with(target.copyWith(tracked: false)).copyWith(
      mainId: () => mainId == lineId ? null : mainId,
      secondId: () => secondId == lineId ? null : secondId,
    );
  }

  /// "Same line as…": [fromId] and [intoId] are one line, one SIM having
  /// replaced the other. [intoId] keeps its id, name and space and takes the
  /// other's SIMs and messages; the balance continues from whichever had
  /// the later message. Messages placed on [fromId] are now on [intoId].
  MpesaLines merged(String fromId, String intoId) {
    final from = line(fromId);
    final into = line(intoId);
    if (from == null || into == null || fromId == intoId) return this;
    DateTime? earliest(DateTime? a, DateTime? b) =>
        a == null ? b : (b == null || a.isBefore(b) ? a : b);
    DateTime? latest(DateTime? a, DateTime? b) =>
        a == null ? b : (b == null || a.isAfter(b) ? a : b);
    final newer =
        (from.lastAt ?? DateTime(0)).isAfter(into.lastAt ?? DateTime(0))
        ? from
        : into;
    final joined = into.copyWith(
      sims: {...into.sims, ...from.sims},
      firstAt: () => earliest(into.firstAt, from.firstAt),
      lastAt: () => latest(into.lastAt, from.lastAt),
      messages: into.messages + from.messages,
      balanceMinor: () => newer.balanceMinor,
      balanceAt: () => newer.balanceAt,
      tracked: into.tracked || from.tracked,
    );
    return copyWith(
      lines: [
        for (final l in lines)
          if (l.id == intoId) joined else if (l.id != fromId) l,
      ],
      placed: {
        for (final MapEntry(:key, :value) in placed.entries)
          key: value == fromId ? intoId : value,
      },
      mainId: () => mainId == fromId ? intoId : mainId,
      secondId: () => secondId == fromId
          ? (mainId == intoId ? null : intoId)
          : (mainId == fromId && secondId == intoId ? null : secondId),
      skippedLineId: () => skippedLineId == fromId ? intoId : skippedLineId,
    );
  }

  /// Line [lineId]'s number, as typed: kept as `0712345678`, or cleared
  /// when [typed] is empty or no phone number.
  MpesaLines withNumber(String lineId, String? typed) {
    final target = line(lineId);
    if (target == null) return this;
    final phone = typed == null ? null : PayeeIdentifier.phone(typed)?.value;
    final clean = phone != null && !phone.contains('*') ? phone : null;
    return _with(target.copyWith(number: () => clean));
  }

  /// The typed numbers, by line id: the person's own numbers for matching
  /// moves between their accounts (decision 0030).
  Map<String, String> get numbers => {
    for (final l in lines)
      if (l.number != null) l.id: l.number!,
  };

  /// The quiet note on the first skipped message was seen.
  MpesaLines skipNoteSeen() => copyWith(skipNote: SkipNote.shown);

  /// How far the iPhone's queue may let go of M-Pesa messages, once
  /// [spaceId] has read up to [until]: what every space reading a line has
  /// read. Null while one of them has read nothing yet.
  (MpesaLines, DateTime?) readTo(
    String spaceId,
    DateTime until,
    Set<String> listed,
  ) {
    final next = copyWith(readUntil: {...readUntil, spaceId: until});
    if (!split) return (next, until);
    final readers = {for (final l in lines) readerOf(l, listed)}..add(spaceId);
    DateTime? least;
    for (final reader in readers) {
      final at = next.readUntil[reader];
      if (at == null) return (next, null);
      if (least == null || at.isBefore(least)) least = at;
    }
    return (next, least);
  }
}

/// One M-Pesa transaction already stored, for telling its line apart on a
/// phone that keeps no copy of past messages to read again.
class StoredLineFacts {
  const StoredLineFacts(this.id, this.facts);

  final int id;
  final LineFacts facts;
}

/// The line of each of [stored], oldest first, by the balance chain alone:
/// a message placed before keeps its line; otherwise it goes to the one line
/// whose running balance it carries on, or starts the next line not yet
/// running, or else goes to the line used last. Lines are [lineIds], in
/// order. Pure: the lines kept are not changed.
Map<int, String> placeStored(MpesaLines lines, List<StoredLineFacts> stored) {
  final ids = [for (final l in lines.lines) l.id];
  if (ids.isEmpty) return const {};
  final running = <String, int?>{for (final id in ids) id: null};
  final started = <String>{};
  String? last;
  final out = <int, String>{};
  for (final s in stored) {
    final f = s.facts;
    var id = lines.placed[f.hash];
    if (id == null || !running.containsKey(id)) {
      final carried = [
        for (final l in ids)
          if (carriesOn(running[l], f)) l,
      ];
      if (carried.length == 1) {
        id = carried.single;
      } else {
        final idle = ids.where((l) => !started.contains(l)).firstOrNull;
        id = carried.isEmpty && idle != null && f.balanceMinor != null
            ? idle
            : (carried.contains(last) ? last : null) ??
                  carried.firstOrNull ??
                  last ??
                  ids.first;
      }
    }
    out[s.id] = id;
    started.add(id);
    if (f.balanceMinor != null) running[id] = f.balanceMinor;
    last = id;
  }
  return out;
}
