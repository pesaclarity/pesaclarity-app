import '../../core/share/share_codec.dart';
import '../repositories/share_repository.dart';
import 'group_sync_client.dart';

/// Where a space's pull cursor is kept between syncs.
abstract interface class SyncCursorStore {
  Future<int> read(String space);
  Future<void> write(String space, int cursor);
}

class MemorySyncCursorStore implements SyncCursorStore {
  final _cursors = <String, int>{};

  @override
  Future<int> read(String space) async => _cursors[space] ?? 0;

  @override
  Future<void> write(String space, int cursor) async =>
      _cursors[space] = cursor;
}

/// What one sync did.
class SyncResult {
  const SyncResult({
    required this.sent,
    required this.received,
    this.readOnly = false,
  });

  final int sent;
  final int received;

  /// The owner's licence has run out: updates came in, none went out.
  final bool readOnly;
}

/// Moves a shared space's `.pcshare` updates through the sync server
/// instead of by hand (decision 0033). It uses the same files, the same
/// keys and the same merge as file sharing: each update is still sealed to
/// one member, and the server only relays it.
class GroupSync {
  GroupSync(this._repo, this._client, this._cursors);

  final ShareRepository _repo;
  final GroupSyncClient _client;
  final SyncCursorStore _cursors;
  final _codec = ShareCodec();

  /// Owner: lets every current member sync, and stops removed ones.
  Future<void> updateMembers() async {
    for (final m in (await _repo.members()).values) {
      final key = m.signKey;
      if (key == null) continue;
      if (m.removed) {
        await _client.removeMember(key);
      } else {
        await _client.addMember(key);
      }
    }
  }

  /// Sends what each member has not had, then applies what is waiting.
  Future<SyncResult> syncOnce({required String spaceName}) async {
    final s = await _repo.state();
    if (s == null) throw StateError('This space is not shared');
    var sent = 0;
    var readOnly = false;
    for (final m in (await _repo.members()).values) {
      if (m.id == s.myMemberId ||
          m.removed ||
          m.signKey == null ||
          m.publicKey == null) {
        continue;
      }
      final out = await _repo.buildUpdate(m.id, spaceName: spaceName);
      // Nothing in the log since the last update to them.
      final sentUpTo = (await _repo.peers())
          .where((p) => p.memberId == m.id)
          .firstOrNull
          ?.sentUpTo;
      if (sentUpTo != null && out.upTo == sentUpTo) continue;
      try {
        await _client.push(
          _codec.readHeader(out.bytes).file,
          out.bytes,
          toSignKey: m.signKey,
        );
      } on GroupSyncException catch (e) {
        if (!e.readOnly) rethrow;
        readOnly = true;
        break;
      }
      await _repo.markSent(out);
      sent++;
    }

    var cursor = await _cursors.read(s.spaceShareId);
    var received = 0;
    for (;;) {
      final pull = await _client.pull(cursor);
      readOnly = readOnly || pull.readOnly;
      for (final b in pull.batches) {
        await _repo.apply(unpadFromSync(b.data));
        received++;
      }
      cursor = pull.next;
      await _cursors.write(s.spaceShareId, cursor);
      if (!pull.more) break;
    }
    return SyncResult(sent: sent, received: received, readOnly: readOnly);
  }
}
