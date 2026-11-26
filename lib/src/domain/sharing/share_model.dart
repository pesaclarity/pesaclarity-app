import '../spaces/space.dart';
import 'hlc.dart';

/// What a member may do in a shared space (decision 0031).
enum ShareRole {
  owner('Owner', 'Adds and removes people, changes the plan.'),
  treasurer(
    'Treasurer',
    'Records contributions and payouts, changes the plan.',
  ),
  member('Member', 'Adds and edits transactions.'),
  viewer('Viewer', 'Sees everything, adds nothing.');

  const ShareRole(this.label, this.hint);

  final String label;
  final String hint;

  /// The roles a space of [kind] offers: Treasurer in a Savings group only.
  static List<ShareRole> offeredIn(SpaceKind kind) => [
    for (final r in values)
      if (r != treasurer || kind == SpaceKind.savingsGroup) r,
  ];

  /// Viewers only receive: their files are refused.
  bool get canSend => this != viewer;

  static ShareRole? byName(Object? name) =>
      name is String ? values.asNameMap()[name] : null;
}

/// The kinds of space that can be shared, and how many people each holds.
int? memberLimit(SpaceKind kind) => switch (kind) {
  SpaceKind.household => 6,
  SpaceKind.savingsGroup => 30,
  _ => null,
};

bool canShare(SpaceKind kind) => memberLimit(kind) != null;

/// The records a shared space keeps in step.
enum ShareEntity {
  account,
  category,
  transaction,
  budget,
  member,

  /// Who can change what (one record, `rules`), kept in the log only.
  policy,

  /// An approver's signed yes or no to a change that waits; the record is
  /// the waiting change's id.
  approval;

  /// Records that live in the log only, not in a table.
  bool get logOnly => this == member || this == policy || this == approval;

  static ShareEntity? byName(Object? name) =>
      name is String ? values.asNameMap()[name] : null;
}

/// The field of a [ShareChange] that adds a record with all its fields.
const insertField = '+';

/// The field of a [ShareChange] that removes a record.
const removeField = '-';

/// One change in a shared space's log: a record added or removed, or one
/// field of it changed.
class ShareChange {
  const ShareChange({
    required this.hlc,
    required this.entity,
    required this.record,
    required this.field,
    required this.value,
    required this.author,
    this.previous,
    this.base,
    this.recordedBy,
  });

  /// When, by the space's clock. Also the change's id: the clock names the
  /// member who made it.
  final Hlc hlc;
  final ShareEntity entity;

  /// The record's stable id (a UUID).
  final String record;

  /// The field changed, or [insertField] or [removeField].
  final String field;

  /// The new value: a field's value, or every field for an insert.
  final Object? value;

  /// The value it replaced on the author's phone, for history.
  final Object? previous;

  /// The clock of the change it replaced on the author's phone. Another
  /// member's change to the same field that is not [base] was made at the
  /// same time without seeing this one: a conflict.
  final Hlc? base;

  /// Who it is by: who added a transaction, or who changed a field.
  final String author;

  /// Who typed it, when someone typed it in for [author].
  final String? recordedBy;

  String get id => hlc.toString();

  /// Which record and field this changes, for finding the latest change.
  String get key => '${entity.name}|$record|$field';

  bool get isInsert => field == insertField;
  bool get isRemove => field == removeField;

  Map<String, Object?> toJson() => {
    'h': hlc.toString(),
    'e': entity.name,
    'r': record,
    'f': field,
    'v': value,
    if (previous != null) 'p': previous,
    if (base != null) 'b': base.toString(),
    'a': author,
    if (recordedBy != null) 'by': recordedBy,
  };

  static ShareChange fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Not a change');
    final entity = ShareEntity.byName(json['e']);
    final record = json['r'];
    final field = json['f'];
    final author = json['a'];
    final by = json['by'];
    final base = json['b'];
    if (entity == null ||
        record is! String ||
        field is! String ||
        author is! String ||
        (by != null && by is! String) ||
        (base != null && base is! String)) {
      throw const FormatException('Not a change');
    }
    return ShareChange(
      hlc: Hlc.parse(json['h']! as String),
      entity: entity,
      record: record,
      field: field,
      value: json['v'],
      previous: json['p'],
      base: base == null ? null : Hlc.parse(base as String),
      author: author,
      recordedBy: by as String?,
    );
  }
}

/// A person in a shared space.
class ShareMember {
  const ShareMember({
    required this.id,
    required this.name,
    required this.role,
    this.publicKey,
    this.hasAccount = false,
    this.removed = false,
    this.signKey,
    this.approver = false,
  });

  final String id;
  final String name;
  final ShareRole role;

  /// Their X25519 public key, which files to and from them are bound to.
  final List<int>? publicKey;
  final bool hasAccount;
  final bool removed;

  /// Their Ed25519 public key, which their answers to waiting changes are
  /// signed with.
  final List<int>? signKey;

  /// Marked "Can approve" by the Owner.
  final bool approver;
}
