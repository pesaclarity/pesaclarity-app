import '../enums.dart';
import 'space.dart';

/// Where one money line (an institution such as M-Pesa or a bank) is read.
enum LineChoice {
  /// Only the business reads it.
  thisBusiness,

  /// Only Personal reads it.
  personal,

  /// Personal reads it, and the business asks about each payment ("Was this
  /// for the business?").
  both,
}

/// Which lines are shared with which business, and what the owner has
/// taught the app about people on those lines. Kept in Personal's settings,
/// so every space sees the same rules.
class RoutingRules {
  const RoutingRules({this.sharedLines = const {}, this.people = const {}});

  /// Reads saved rules; anything malformed is left out.
  factory RoutingRules.fromJson(Map<String, Object?>? json) {
    Map<String, String> strings(Object? raw) => {
      if (raw is Map)
        for (final MapEntry(:key, :value) in raw.entries)
          if (key is String && value is String) key: value,
    };
    return RoutingRules(
      sharedLines: strings(json?['sharedLines']),
      people: strings(json?['people']),
    );
  }

  /// Institution id to the business space that shares it with Personal.
  final Map<String, String> sharedLines;

  /// [personKey] to the space their money goes to: a business space id, or
  /// [personalSpaceId].
  final Map<String, String> people;

  Map<String, Object?> toJson() => {
    'sharedLines': sharedLines,
    'people': people,
  };

  /// The lines Personal shares with [businessId].
  Set<String> sharedWith(String businessId) => {
    for (final MapEntry(:key, :value) in sharedLines.entries)
      if (value == businessId) key,
  };

  RoutingRules withLine(String institutionId, String? businessId) =>
      RoutingRules(
        sharedLines: {
          for (final MapEntry(:key, :value) in sharedLines.entries)
            if (key != institutionId) key: value,
          institutionId: ?businessId,
        },
        people: people,
      );

  RoutingRules withPerson(String key, String spaceId) =>
      RoutingRules(sharedLines: sharedLines, people: {...people, key: spaceId});

  bool get isEmpty => sharedLines.isEmpty && people.isEmpty;

  /// Only the rules that send money to [spaceId]: the lines it shares with
  /// Personal and the people learnt for it.
  RoutingRules forSpace(String spaceId) => RoutingRules(
    sharedLines: {
      for (final MapEntry(:key, :value) in sharedLines.entries)
        if (value == spaceId) key: value,
    },
    people: {
      for (final MapEntry(:key, :value) in people.entries)
        if (value == spaceId) key: value,
    },
  );

  /// These rules without those that send money to [spaceId].
  RoutingRules withoutSpace(String spaceId) => RoutingRules(
    sharedLines: {
      for (final MapEntry(:key, :value) in sharedLines.entries)
        if (value != spaceId) key: value,
    },
    people: {
      for (final MapEntry(:key, :value) in people.entries)
        if (value != spaceId) key: value,
    },
  );

  /// These rules without any that send money to a space outside
  /// [spaceIds]. Personal is always there. Rules never outlive their space.
  RoutingRules onlyFor(Set<String> spaceIds) => RoutingRules(
    sharedLines: {
      for (final MapEntry(:key, :value) in sharedLines.entries)
        if (spaceIds.contains(value)) key: value,
    },
    people: {
      for (final MapEntry(:key, :value) in people.entries)
        if (value == personalSpaceId || spaceIds.contains(value)) key: value,
    },
  );

  /// These rules with [older] ones put back, for a space that returns.
  /// Whatever was chosen since stays: a line shared with another business
  /// now, or a person sent elsewhere, is not taken back.
  RoutingRules withPutBack(RoutingRules older) => RoutingRules(
    sharedLines: {...older.sharedLines, ...sharedLines},
    people: {...older.people, ...people},
  );

  /// How many people go to [businessId] and how many stay personal.
  ({int business, int personal}) learntFor(String businessId) {
    var business = 0;
    var personal = 0;
    for (final space in people.values) {
      if (space == businessId) business++;
      if (space == personalSpaceId) personal++;
    }
    return (business: business, personal: personal);
  }
}

/// A stable key for the other party of a transaction, the same in every
/// space: their normalised identifier when the message gave one, else their
/// name. Null when there is neither.
String? personKey({PayeeIdentifierKind? kind, String? value, String? name}) {
  if (kind != null && value != null && value.trim().isNotEmpty) {
    return '${kind.name}:${value.trim()}';
  }
  final n = name?.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return n == null || n.isEmpty ? null : 'name:$n';
}

/// What the owner picks for a line, from where it is read now.
LineChoice lineChoiceOf({
  required bool inBusiness,
  required bool inPersonal,
  required bool shared,
}) {
  if (shared) return LineChoice.both;
  if (inBusiness && !inPersonal) return LineChoice.thisBusiness;
  if (inPersonal && !inBusiness) return LineChoice.personal;
  // Read in both without sharing reads every message twice; treat it as
  // shared so the books count each payment once.
  return inBusiness ? LineChoice.both : LineChoice.personal;
}
