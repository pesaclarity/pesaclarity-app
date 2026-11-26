import '../spaces/space.dart';
import 'share_model.dart';

/// How freely other members may make one kind of change (group approvals).
enum ChangeLevel {
  anyone,
  approval,
  restricted;

  static ChangeLevel? byName(Object? name) =>
      name is String ? values.asNameMap()[name] : null;

  String label(SpaceKind kind) => switch (this) {
    anyone => 'Anyone',
    approval => 'Needs approval',
    restricted =>
      kind == SpaceKind.savingsGroup
          ? 'Owner and Treasurer only'
          : 'Owner only',
  };

  String hint(SpaceKind kind) => switch (this) {
    anyone => 'Members change it; it shows in Space history.',
    approval => "A member's change waits until an approver says yes.",
    restricted => 'Changes by anyone else are refused.',
  };
}

/// The kinds of change "Who can change what" sets a level for.
enum RuleArea {
  plan('The plan and budgets', 'Plan amounts, new plan lines'),
  accounts('Accounts and categories', 'Add, rename or remove'),
  others(
    "Someone else's transactions",
    'Edit or delete what another member added',
  );

  const RuleArea(this.title, this.hint);

  final String title;
  final String hint;
}

/// A change that waits for no answer lapses after this long.
const approvalLapse = Duration(days: 30);

/// The record id of a space's rules in the log.
const policyRecord = 'rules';

/// The field of an [ShareEntity.approval] change that says yes.
const approveField = 'yes';

/// The field of an [ShareEntity.approval] change that says no.
const declineField = 'no';

/// Who can change what in a shared space. The Owner's own changes never
/// wait; adding members is always the Owner's alone.
class SharePolicy {
  const SharePolicy(this.kind, this.levels, {this.contributions = false});

  /// A Household: the plan, accounts and categories are anyone's; editing
  /// what someone else added needs approval. A chama: everything needs
  /// approval; contributions do only when switched on.
  factory SharePolicy.defaults(SpaceKind kind) => SharePolicy(
    kind,
    kind == SpaceKind.savingsGroup
        ? const {
            RuleArea.plan: ChangeLevel.approval,
            RuleArea.accounts: ChangeLevel.approval,
            RuleArea.others: ChangeLevel.approval,
          }
        : const {
            RuleArea.plan: ChangeLevel.anyone,
            RuleArea.accounts: ChangeLevel.anyone,
            RuleArea.others: ChangeLevel.approval,
          },
  );

  /// The defaults with [fields] (the log's `rules` record) on top.
  factory SharePolicy.fromFields(SpaceKind kind, Map<String, Object?>? fields) {
    final base = SharePolicy.defaults(kind);
    if (fields == null) return base;
    return SharePolicy(
      kind,
      {
        for (final a in RuleArea.values)
          a: ChangeLevel.byName(fields[a.name]) ?? base.levels[a]!,
      },
      contributions:
          kind == SpaceKind.savingsGroup && fields['contributions'] == true,
    );
  }

  final SpaceKind kind;
  final Map<RuleArea, ChangeLevel> levels;

  /// In a chama, whether money in added by a member waits for approval.
  final bool contributions;

  ChangeLevel level(RuleArea a) => levels[a] ?? ChangeLevel.anyone;

  Map<String, Object?> toFields() => {
    for (final a in RuleArea.values) a.name: level(a).name,
    'contributions': contributions,
  };

  /// The roles whose changes skip [ChangeLevel.restricted]: the Owner, and
  /// in a chama the Treasurer.
  bool trusted(ShareRole role) =>
      role == ShareRole.owner ||
      (kind == SpaceKind.savingsGroup && role == ShareRole.treasurer);

  /// Whether [role] may answer waiting changes, given the Owner's "Can
  /// approve" mark.
  bool canApprove(ShareRole? role, {required bool marked}) =>
      role != null && role != ShareRole.viewer && (trusted(role) || marked);
}
