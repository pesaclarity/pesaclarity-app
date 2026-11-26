import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/share_repository.dart';
import '../../../domain/sharing/share_model.dart';
import '../../../domain/sharing/share_rules.dart';
import '../../../domain/spaces/space.dart';
import '../../spaces/application/spaces_providers.dart';

/// The open space's sharing (decision 0031), or null when its kind is not
/// shared: only a Household or a Savings group is.
final shareRepositoryProvider = Provider<ShareRepository?>((ref) {
  final space = ref.watch(activeSpaceProvider);
  if (!canShare(space.kind)) return null;
  return ShareRepository(ref.watch(appDatabaseProvider), kind: space.kind);
});

/// Who is in the open space, and what this phone last sent and received.
class ShareOverview {
  const ShareOverview({
    required this.shared,
    required this.kind,
    this.myId,
    this.members = const [],
    this.peers = const {},
  });

  final bool shared;
  final SpaceKind kind;
  final String? myId;

  /// The Owner first, then everyone else in the order they joined.
  final List<ShareMember> members;
  final Map<String, SharePeerRow> peers;

  ShareMember? get me => members.where((m) => m.id == myId).firstOrNull;
  ShareRole get myRole => me?.role ?? ShareRole.owner;
  int get count => shared ? members.length : 1;
  int get limit => memberLimit(kind) ?? 0;
  List<ShareMember> get others => [
    for (final m in members)
      if (m.id != myId && m.publicKey != null) m,
  ];

  String nameOf(String id) => id == myId
      ? 'you'
      : (members.where((m) => m.id == id).firstOrNull?.name.split(' ').first ??
            'someone');
}

final shareOverviewProvider = FutureProvider<ShareOverview>((ref) async {
  final space = ref.watch(activeSpaceProvider);
  final repo = ref.watch(shareRepositoryProvider);
  final state = await repo?.state();
  if (repo == null || state == null) {
    return ShareOverview(shared: false, kind: space.kind);
  }
  final all = await repo.members();
  final peers = {for (final p in await repo.peers()) p.memberId: p};
  final members =
      [
        for (final m in all.values)
          if (!m.removed) m,
      ]..sort((a, b) {
        if (a.role == ShareRole.owner) return -1;
        if (b.role == ShareRole.owner) return 1;
        final aj = peers[a.id]?.joinedAt;
        final bj = peers[b.id]?.joinedAt;
        if (aj == null || bj == null) return a.name.compareTo(b.name);
        return aj.compareTo(bj);
      });
  return ShareOverview(
    shared: true,
    kind: space.kind,
    myId: state.myMemberId,
    members: members,
    peers: peers,
  );
});

/// The line under a transaction someone else added: "Added by Jane", or
/// "Added by Brian, recorded by Jane", with "· category changed by you"
/// when another member recategorised it. By transaction id; none for what
/// this phone added.
final addedByLinesProvider = StreamProvider<Map<int, String>>((ref) {
  final repo = ref.watch(shareRepositoryProvider);
  if (repo == null) return Stream.value(const {});
  final db = ref.watch(appDatabaseProvider);
  return db
      .customSelect(
        'SELECT t.id, t.added_by, t.recorded_by, t.share_uid, '
        '(SELECT c.author FROM share_changes c WHERE c.entity = '
        "'transaction' AND c.record = t.share_uid AND c.field = 'category' "
        'ORDER BY c.hlc DESC LIMIT 1) AS recategorised '
        'FROM transactions t WHERE t.added_by IS NOT NULL',
        readsFrom: {db.transactions, db.shareChanges},
      )
      .watch()
      .asyncMap((rows) async {
        if (rows.isEmpty) return const <int, String>{};
        final overview = await ref.read(shareOverviewProvider.future);
        final out = <int, String>{};
        for (final r in rows) {
          final by = r.read<String>('added_by');
          if (by == overview.myId) continue;
          final recorded = r.read<String?>('recorded_by');
          final recat = r.read<String?>('recategorised');
          final buffer = StringBuffer('Added by ${overview.nameOf(by)}');
          if (recorded != null && recorded != by) {
            buffer.write(', recorded by ${overview.nameOf(recorded)}');
          }
          if (recat != null && recat != by) {
            buffer.write(' · category changed by ${overview.nameOf(recat)}');
          }
          out[r.read<int>('id')] = buffer.toString();
        }
        return out;
      });
});

/// Who can change what in the open space.
final sharePolicyProvider = FutureProvider<SharePolicy>((ref) async {
  final space = ref.watch(activeSpaceProvider);
  ref.watch(shareOverviewProvider);
  final repo = ref.watch(shareRepositoryProvider);
  if (repo == null || await repo.state() == null) {
    return SharePolicy.defaults(space.kind);
  }
  return repo.policy();
});

/// The changes this phone's member can say yes or no to, oldest first.
final toApproveProvider = FutureProvider<List<WaitingChange>>((ref) async {
  ref.watch(shareOverviewProvider);
  final repo = ref.watch(shareRepositoryProvider);
  if (repo == null || await repo.state() == null) return const [];
  return repo.toApprove();
});

/// On this member's own rows: "you asked to delete it · Waiting for
/// approval", or "Declined by Jane", by transaction id. Reading it puts
/// new edits in the log first, so a change that waits shows the old value
/// here too.
final myWaitingLinesProvider = StreamProvider<Map<int, String>>((ref) {
  final repo = ref.watch(shareRepositoryProvider);
  if (repo == null) return Stream.value(const {});
  final db = ref.watch(appDatabaseProvider);
  return db
      .customSelect(
        'SELECT COUNT(*) AS n FROM share_changes',
        readsFrom: {db.shareChanges, db.transactions},
      )
      .watch()
      .asyncMap((_) async {
        if (await repo.state() == null) return const <int, String>{};
        await repo.recordLocalChanges();
        final out = <int, String>{};
        for (final w in await repo.mine()) {
          if (w.entity != ShareEntity.transaction || w.mineLine == null) {
            continue;
          }
          final row = await db
              .customSelect(
                'SELECT id FROM transactions WHERE share_uid = ? LIMIT 1',
                variables: [Variable.withString(w.record)],
              )
              .getSingleOrNull();
          if (row != null) out[row.read<int>('id')] = w.mineLine!;
        }
        return out;
      });
});
