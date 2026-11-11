import 'space.dart';

/// How long cleared or deleted data is kept when the person asks for it.
const keepFor = Duration(days: 30);

/// What was removed and kept for [keepFor].
enum KeptKind {
  /// A space's records were cleared; the space stayed.
  cleared,

  /// A whole space was deleted.
  space,
}

/// Data the person removed but asked to keep for 30 days. Its locked copy is
/// on this phone only, under [token], opened with [keyHex].
class KeptData {
  const KeptData({
    required this.token,
    required this.kind,
    required this.space,
    required this.removedAt,
    required this.keyHex,
  });

  final String token;
  final KeptKind kind;
  final Space space;
  final DateTime removedAt;

  /// The key of the copy. It is kept in Personal's locked settings only.
  final String keyHex;

  /// When it goes for good.
  DateTime get until => removedAt.add(keepFor);

  bool expiredAt(DateTime now) => !now.isBefore(until);

  static KeptData? fromJson(Object? json) {
    if (json is! Map) return null;
    final token = json['token'];
    final kind = KeptKind.values.asNameMap()[json['kind']];
    final space = Space.fromJson(json['space']);
    final at = json['removedAt'] is String
        ? DateTime.tryParse(json['removedAt'] as String)
        : null;
    final key = json['key'];
    if (token is! String ||
        !RegExp(r'^[a-z0-9]{1,40}$').hasMatch(token) ||
        kind == null ||
        space == null ||
        at == null ||
        key is! String) {
      return null;
    }
    return KeptData(
      token: token,
      kind: kind,
      space: space,
      removedAt: at,
      keyHex: key,
    );
  }

  Map<String, Object?> toJson() => {
    'token': token,
    'kind': kind.name,
    'space': space.toJson(),
    'removedAt': removedAt.toUtc().toIso8601String(),
    'key': keyHex,
  };
}

List<KeptData> keptFromJson(Map<String, Object?>? json) => [
  for (final item in (json?['kept'] as List<Object?>?) ?? const [])
    ?KeptData.fromJson(item),
];

Map<String, Object?> keptToJson(List<KeptData> kept) => {
  'kept': [for (final k in kept) k.toJson()],
};

/// What a change of kind brings in and takes away, for the warning.
({List<String> comesIn, List<String> goesAway}) kindChange(
  SpaceKind from,
  SpaceKind to,
) {
  List<String> features(SpaceKind kind) => switch (kind) {
    SpaceKind.business => [
      'Sell',
      'Stock',
      'People',
      'Close the day',
      'Tax',
      'Receipts and invoices',
    ],
    SpaceKind.household => ['Shared bills', 'Who owes whom'],
    SpaceKind.savingsGroup => ['Contributions', 'Payouts', 'Group loans'],
    SpaceKind.rentalProperty => ['Rent in', 'Repairs', 'Profit'],
    SpaceKind.farm => ['Inputs', 'Labour', 'Harvest sales', 'Seasons'],
    SpaceKind.personal => ['Safe to spend', 'Plan', 'Goals'],
    SpaceKind.other => ['Money in and out'],
  };
  final had = features(from);
  final gets = features(to);
  return (
    comesIn: [
      for (final f in gets)
        if (!had.contains(f)) f,
    ],
    goesAway: [
      for (final f in had)
        if (!gets.contains(f)) f,
    ],
  );
}
