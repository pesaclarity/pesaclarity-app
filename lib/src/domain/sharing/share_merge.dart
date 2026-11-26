import '../spaces/space.dart';
import 'hlc.dart';
import 'share_model.dart';
import 'share_rules.dart';

/// What the space's rules make of one change.
enum ShareGate {
  /// It counts at once.
  free,

  /// It is kept, and counts once an approver says yes.
  waits,

  /// The author's role does not allow it.
  refused,
}

/// Where a change that needed approval stands.
enum ApprovalState { waiting, approved, declined, lapsed }

/// Two members changed the same field without seeing each other's change.
/// The later one by the clock wins; the other is kept in history.
class ShareConflict {
  const ShareConflict({required this.winner, required this.loser});

  final ShareChange winner;
  final ShareChange loser;
}

/// What opening an update file did, or would do.
class MergeOutcome {
  const MergeOutcome({
    required this.accepted,
    required this.refused,
    required this.conflicts,
    required this.added,
    required this.changed,
    required this.skipped,
    this.waiting = const [],
    this.decided = const [],
  });

  /// Accepted changes that wait for an approver.
  final List<ShareChange> waiting;

  /// Waiting changes an accepted answer decided.
  final List<ShareChange> decided;

  /// Changes now in the log, in clock order.
  final List<ShareChange> accepted;

  /// Changes their author's role does not allow.
  final List<ShareChange> refused;
  final List<ShareConflict> conflicts;

  /// Records the file added, and records whose fields it changed.
  final Set<String> added;
  final Set<String> changed;

  /// Changes this phone already had: the same file opened twice.
  final int skipped;

  /// Records whose stored rows must be written again.
  Set<String> get touched => {
    for (final c in accepted)
      if (!c.entity.logOnly) '${c.entity.name}|${c.record}',
    for (final c in decided) '${c.entity.name}|${c.record}',
  };
}

/// A shared space's log, as this phone has it: every change, and the
/// latest change for each record and field.
class ShareLog {
  ShareLog(
    this.ownerId,
    this.kind, [
    Iterable<ShareChange> changes = const [],
  ]) {
    for (final c in changes) {
      add(c);
    }
  }

  /// The member who made the space.
  final String ownerId;
  final SpaceKind kind;

  final _byId = <String, ShareChange>{};
  final _latest = <String, ShareChange>{};

  Iterable<ShareChange> get changes => _byId.values;
  bool has(String id) => _byId.containsKey(id);
  ShareChange? latest(ShareEntity e, String record, String field) =>
      _latest['${e.name}|$record|$field'];

  /// The clock after every change in the log.
  Hlc get clock =>
      _byId.values.fold(Hlc.zero, (top, c) => c.hlc > top ? c.hlc : top);

  /// Changes that need an approver's answer, by id.
  final _waiting = <String, ShareChange>{};

  /// Answers to waiting changes, by the waiting change's id.
  final _answers = <String, List<ShareChange>>{};

  void add(ShareChange c) {
    _byId[c.id] = c;
    if (c.entity == ShareEntity.approval) {
      _answers.putIfAbsent(c.record, () => []).add(c);
      if (_waiting[c.record] case final t?) _refresh(t.key);
      return;
    }
    if (gate(c) == ShareGate.waits) {
      _waiting[c.id] = c;
      if (answer(c.id)?.field == approveField) _put(c);
      return;
    }
    _put(c);
  }

  void _put(ShareChange c) {
    final now = _latest[c.key];
    if (now == null || c.hlc > now.hlc) _latest[c.key] = c;
  }

  bool _counts(ShareChange c) =>
      !_waiting.containsKey(c.id) || answer(c.id)?.field == approveField;

  void _refresh(String key) {
    _latest.remove(key);
    for (final c in _byId.values) {
      if (c.entity != ShareEntity.approval && c.key == key && _counts(c)) {
        _put(c);
      }
    }
  }

  // ----------------------------------------------------------- approvals

  /// The space's rules as they stood just before [at]: changes to them
  /// count from their own clock on, so every phone judges a change alike.
  SharePolicy policyAt([Hlc? at]) {
    final changes = [
      for (final c in _byId.values)
        if (c.entity == ShareEntity.policy &&
            c.record == policyRecord &&
            (at == null || at > c.hlc))
          c,
    ]..sort((a, b) => a.hlc.compareTo(b.hlc));
    Map<String, Object?>? fields;
    for (final c in changes) {
      if (c.isInsert && c.value is Map) {
        fields = Map<String, Object?>.of((c.value! as Map).cast());
      } else if (!c.isRemove) {
        (fields ??= {})[c.field] = c.value;
      }
    }
    return SharePolicy.fromFields(kind, fields);
  }

  ShareRole? _roleFor(String memberId) =>
      memberId == ownerId && roleOf(memberId) == null
      ? ShareRole.owner
      : roleOf(memberId);

  /// What the rules make of [c], by the member whose clock it carries.
  ShareGate gate(ShareChange c) {
    final node = c.hlc.node;
    final role = _roleFor(node);
    if (role == null || !role.canSend) return ShareGate.refused;
    final owner = role == ShareRole.owner;
    switch (c.entity) {
      // Anyone may change their own name in the space, and say they have
      // an account. The member list is otherwise the Owner's alone.
      case ShareEntity.member:
        return owner ||
                (c.record == node &&
                    (c.field == 'name' || c.field == 'account'))
            ? ShareGate.free
            : ShareGate.refused;
      case ShareEntity.policy:
        return owner ? ShareGate.free : ShareGate.refused;
      case ShareEntity.approval:
        return ShareGate.free;
      case ShareEntity.transaction ||
          ShareEntity.budget ||
          ShareEntity.category ||
          ShareEntity.account:
        break;
    }
    // The Owner's own changes never wait.
    if (owner) return ShareGate.free;
    final policy = policyAt(c.hlc);
    final ChangeLevel level;
    switch (c.entity) {
      case ShareEntity.transaction:
        if (c.isInsert) {
          final inflow =
              c.value is Map && (c.value! as Map)['direction'] == 'inflow';
          // Everyone can always add transactions; in a chama that asks for
          // it, money in waits.
          if (!(policy.contributions && inflow)) return ShareGate.free;
          level = ChangeLevel.approval;
        } else {
          final (by, recordedBy) = addedBy(c.entity, c.record) ?? (node, null);
          // Everyone can always edit their own.
          if (by == node || recordedBy == node) return ShareGate.free;
          level = policy.level(RuleArea.others);
        }
      case ShareEntity.budget:
        level = policy.level(RuleArea.plan);
      default:
        level = policy.level(RuleArea.accounts);
    }
    return switch (level) {
      ChangeLevel.anyone => ShareGate.free,
      ChangeLevel.approval => ShareGate.waits,
      ChangeLevel.restricted =>
        policy.trusted(role) ? ShareGate.free : ShareGate.refused,
    };
  }

  /// Whether [memberId] may answer waiting changes now.
  bool canApprove(String memberId) => policyAt().canApprove(
    _roleFor(memberId),
    marked: members[memberId]?.approver ?? false,
  );

  /// Whether [d] is a good answer to [target]: by an approver who did not
  /// make the change, before it lapsed. Its signature is checked before
  /// it reaches the log.
  bool validAnswer(ShareChange d, ShareChange target) =>
      d.entity == ShareEntity.approval &&
      d.record == target.id &&
      (d.field == approveField || d.field == declineField) &&
      d.hlc.node == d.author &&
      d.author != target.hlc.node &&
      _waiting.containsKey(target.id) &&
      d.hlc.millis - target.hlc.millis <= approvalLapse.inMilliseconds &&
      canApprove(d.author);

  /// The answer that decides waiting change [id]: the first good one.
  /// One approver's yes is enough.
  ShareChange? answer(String id) {
    final t = _byId[id];
    final list = _answers[id];
    if (t == null || list == null) return null;
    ShareChange? best;
    for (final d in list) {
      if (!validAnswer(d, t)) continue;
      if (best == null || best.hlc > d.hlc) best = d;
    }
    return best;
  }

  /// Every change that needed approval, answered or not.
  Iterable<ShareChange> get needingApproval => _waiting.values;

  /// Where change [id] stands, or null when it never needed approval.
  ApprovalState? stateOf(String id, int nowMillis) {
    final t = _waiting[id];
    if (t == null) return null;
    final a = answer(id);
    if (a != null) {
      return a.field == approveField
          ? ApprovalState.approved
          : ApprovalState.declined;
    }
    return nowMillis - t.hlc.millis > approvalLapse.inMilliseconds
        ? ApprovalState.lapsed
        : ApprovalState.waiting;
  }

  /// Whether [record] is in the space: added, and not removed by a later
  /// change. A removal made at the same time as an edit wins over it.
  bool exists(ShareEntity e, String record) {
    final insert = latest(e, record, insertField);
    if (insert == null) return false;
    final remove = latest(e, record, removeField);
    return remove == null || insert.hlc > remove.hlc;
  }

  /// A record's fields: its insert, with each later field change on top.
  Map<String, Object?>? fields(ShareEntity e, String record) {
    final insert = latest(e, record, insertField);
    if (insert == null || !exists(e, record)) return null;
    final out = Map<String, Object?>.of((insert.value! as Map).cast());
    final prefix = '${e.name}|$record|';
    for (final entry in _latest.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final c = entry.value;
      if (c.isInsert || c.isRemove) continue;
      // A field set again by a later insert ("Bring it back") keeps the
      // insert's value.
      if (c.hlc > insert.hlc) out[c.field] = c.value;
    }
    return out;
  }

  /// Who added [record], and who typed it in for them.
  (String, String?)? addedBy(ShareEntity e, String record) {
    ShareChange? first;
    for (final c in _byId.values) {
      if (c.entity == e && c.record == record && c.isInsert) {
        if (first == null || first.hlc > c.hlc) first = c;
      }
    }
    return first == null ? null : (first.author, first.recordedBy);
  }

  /// Each member as the log has them now.
  Map<String, ShareMember> get members {
    final out = <String, ShareMember>{};
    final ids = {
      for (final c in _byId.values)
        if (c.entity == ShareEntity.member) c.record,
    };
    for (final id in ids) {
      final insert = latest(ShareEntity.member, id, insertField);
      if (insert == null) continue;
      final f = fields(ShareEntity.member, id);
      final removed = f == null;
      final v = f ?? Map<String, Object?>.of((insert.value! as Map).cast());
      out[id] = ShareMember(
        id: id,
        name: v['name'] as String? ?? '',
        role: ShareRole.byName(v['role']) ?? ShareRole.viewer,
        publicKey: (v['key'] as List?)?.cast<int>(),
        hasAccount: v['account'] == true,
        removed: removed,
        signKey: (v['sign'] as List?)?.cast<int>(),
        approver: v['approver'] == true,
      );
    }
    return out;
  }

  ShareRole? roleOf(String memberId) {
    final m = members[memberId];
    if (m == null || m.removed) return null;
    return m.role;
  }

  /// Whether [memberId]'s role lets them make [c], at once or once
  /// approved.
  bool allows(String memberId, ShareChange c) =>
      c.hlc.node == memberId && gate(c) != ShareGate.refused;

  /// Takes in [incoming], sent by [sender]. Nothing is added when the
  /// sender may not send (a Viewer, or someone removed): the whole file is
  /// refused with [ShareRefused].
  ///
  /// An answer to a waiting change is taken only when its id is in
  /// [signed]: its signature was checked against the approver's key in the
  /// member list.
  MergeOutcome merge(
    String sender,
    List<ShareChange> incoming, {
    Set<String> signed = const {},
  }) {
    final senderRole = roleOf(sender);
    if (senderRole == null) throw const ShareRefused.notMember();
    if (!senderRole.canSend) throw const ShareRefused.viewer();
    final sorted = [...incoming]..sort((a, b) => a.hlc.compareTo(b.hlc));
    final accepted = <ShareChange>[];
    final refused = <ShareChange>[];
    final conflicts = <ShareConflict>[];
    final added = <String>{};
    final changed = <String>{};
    final waiting = <ShareChange>[];
    final decided = <ShareChange>[];
    var skipped = 0;
    for (final c in sorted) {
      if (has(c.id)) {
        skipped++;
        continue;
      }
      // The clock names its member: a change claiming to be by someone
      // else is refused, unless it is typed in for them.
      if (c.hlc.node != (c.recordedBy ?? c.author)) {
        refused.add(c);
        continue;
      }
      if (c.entity == ShareEntity.approval) {
        final t = _waiting[c.record];
        if (!signed.contains(c.id) || t == null || !validAnswer(c, t)) {
          refused.add(c);
          continue;
        }
        add(c);
        accepted.add(c);
        decided.add(t);
        continue;
      }
      final g = gate(c);
      if (g == ShareGate.refused) {
        refused.add(c);
        continue;
      }
      if (g == ShareGate.waits) {
        add(c);
        accepted.add(c);
        waiting.add(c);
        continue;
      }
      final now = latest(c.entity, c.record, c.field);
      if (!c.isInsert &&
          !c.isRemove &&
          now != null &&
          now.hlc.node != c.hlc.node &&
          now.hlc != c.base &&
          now.value != c.value &&
          (c.base == null || now.hlc > c.base!)) {
        conflicts.add(
          c.hlc > now.hlc
              ? ShareConflict(winner: c, loser: now)
              : ShareConflict(winner: now, loser: c),
        );
      }
      final existed = exists(c.entity, c.record);
      add(c);
      accepted.add(c);
      if (c.isInsert && !existed) {
        added.add(c.record);
      } else {
        changed.add(c.record);
      }
    }
    changed.removeAll(added);
    return MergeOutcome(
      accepted: accepted,
      refused: refused,
      conflicts: conflicts,
      added: added,
      changed: changed,
      skipped: skipped,
      waiting: waiting,
      decided: decided,
    );
  }
}

/// Why a whole update file was refused.
class ShareRefused implements Exception {
  const ShareRefused(this.message);
  const ShareRefused.viewer()
    : message = 'This file is from a Viewer. Viewers only receive updates.';
  const ShareRefused.notMember()
    : message = 'This file is from someone who is not in this space.';
  const ShareRefused.unreadable()
    : message =
          "This file can't be opened. It was changed, or it is for another "
          'space or person.';

  final String message;

  @override
  String toString() => 'ShareRefused: $message';
}
