/// The space every install starts with. Its database is the original file,
/// and it also keeps app-wide settings and the list of spaces.
const personalSpaceId = 'personal';

/// What a space is for.
enum SpaceKind {
  personal('Personal'),
  business('Business');

  const SpaceKind(this.label);

  final String label;
}

/// One set of money kept apart: its own encrypted database with accounts,
/// categories, Plan, goals and insights.
class Space {
  const Space({required this.id, required this.name, required this.kind});

  static const personal = Space(
    id: personalSpaceId,
    name: 'Personal',
    kind: SpaceKind.personal,
  );

  final String id;
  final String name;
  final SpaceKind kind;

  /// Letters for the space's badge: `Mama Mboga stall` is `M`.
  String get initial =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  Space copyWith({String? name}) =>
      Space(id: id, name: name ?? this.name, kind: kind);

  static Space? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final kind = SpaceKind.values.asNameMap()[json['kind']];
    if (id is! String || name is! String || kind == null) return null;
    if (!RegExp(r'^[a-z0-9]{1,32}$').hasMatch(id)) return null;
    return Space(id: id, name: name, kind: kind);
  }

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'kind': kind.name};
}

/// Every space, Personal first.
List<Space> spacesFromJson(Map<String, Object?>? json) {
  final raw = json?['spaces'];
  final spaces = <Space>[Space.personal];
  if (raw is List) {
    for (final item in raw) {
      final space = Space.fromJson(item);
      if (space != null && space.id != personalSpaceId) spaces.add(space);
    }
  }
  return spaces;
}

Map<String, Object?> spacesToJson(List<Space> spaces) => {
  'spaces': [
    for (final s in spaces)
      if (s.id != personalSpaceId) s.toJson(),
  ],
};
