import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/share/share_codec.dart';
import '../../domain/sharing/hlc.dart';
import '../../domain/sharing/safety_words.dart';
import '../../domain/sharing/share_merge.dart';
import '../../domain/sharing/share_model.dart';
import '../../domain/sharing/share_rules.dart';
import '../../domain/spaces/space.dart';
import '../database/app_database.dart';
import 'journal_repository.dart';
import 'share_triggers.dart';

/// An update file ready to send, before it is marked as sent.
class OutgoingShare {
  const OutgoingShare({
    required this.bytes,
    required this.fileName,
    required this.to,
    required this.added,
    required this.changed,
    required this.upTo,
    required this.words,
    required this.wordsChecked,
  });

  final List<int> bytes;
  final String fileName;
  final ShareMember to;

  /// Records new and changed since the last file to [to].
  final int added;
  final int changed;

  /// The last log entry it carries.
  final int upTo;
  final List<String> words;
  final bool wordsChecked;
}

/// What an update file holds, as it would land here.
class IncomingShare {
  const IncomingShare({
    required this.bytes,
    required this.from,
    required this.header,
    required this.outcome,
    required this.alreadyApplied,
    required this.wordsChecked,
    required this.conflictLines,
  });

  final List<int> bytes;
  final ShareMember from;
  final ShareFileHeader header;
  final MergeOutcome outcome;
  final bool alreadyApplied;
  final bool wordsChecked;

  /// Each conflict in words, such as "Food plan: you set 18,000 on Sat,
  /// Jane set 20,000 on Sun. Jane's is later, so 20,000 stays. Yours is
  /// kept in History."
  final List<String> conflictLines;
}

/// One line of Space history.
class HistoryLine {
  const HistoryLine(this.title, {this.detail, this.useMine, this.bringBack});

  final String title;
  final String? detail;

  /// The change "Use mine instead" puts back, by its clock.
  final String? useMine;

  /// The record "Bring it back" restores, as `entity|uid`.
  final String? bringBack;
}

/// A change that needed approval, in words.
class WaitingChange {
  const WaitingChange({
    required this.id,
    required this.entity,
    required this.record,
    required this.title,
    required this.detail,
    required this.at,
    required this.state,
    this.fromMember,
    this.mineLine,
  });

  /// The change's clock, which [ShareRepository.answer] takes.
  final String id;
  final ShareEntity entity;
  final String record;

  /// Such as 'Jane wants to delete "Taxi" (KES 600)'.
  final String title;

  /// Such as "Added by you on Sat 21 Nov".
  final String detail;
  final DateTime at;
  final ApprovalState state;

  /// Whose file it came in; null for one made on this phone.
  final String? fromMember;

  /// On the author's own row: "you asked to delete it · Waiting for
  /// approval", or "Declined by Jane".
  final String? mineLine;
}

/// Space history's changes, grouped by the file they came in or the day
/// they were made on this phone.
class HistoryGroup {
  const HistoryGroup(this.at, this.fromMember, this.lines);

  final DateTime at;

  /// Whose file it was; null for changes made on this phone.
  final String? fromMember;
  final List<HistoryLine> lines;
}

/// A shared space's sharing (decision 0031, stage 1): its change log, its
/// members and keys, and the update files that carry changes between
/// phones. No server is involved.
class ShareRepository {
  ShareRepository(
    this._db, {
    required this.kind,
    ShareCodec? codec,
    int Function()? nowMillis,
  }) : _codec = codec ?? ShareCodec(),
       _fixedClock = nowMillis != null,
       _now = nowMillis ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Tests set the clock: changes are then clocked by it, not by when the
  /// database saw them.
  final bool _fixedClock;

  final AppDatabase _db;
  final SpaceKind kind;
  final ShareCodec _codec;
  final int Function() _now;

  DateTime get _nowTime => DateTime.fromMillisecondsSinceEpoch(_now());

  Future<ShareStateRow?> state() =>
      _db.select(_db.shareState).getSingleOrNull();

  Future<ShareStateRow> _state() async {
    final s = await state();
    if (s == null) throw StateError('This space is not shared');
    return s;
  }

  Map<int, List<int>> _keys(ShareStateRow s) => {
    for (final e in (jsonDecode(s.keys) as Map).entries)
      int.parse(e.key as String): base64Url.decode(e.value as String),
  };

  /// Starts sharing: this phone's member is the Owner, and every record
  /// already in the space goes in the log.
  Future<void> start({required String myName, bool hasAccount = false}) =>
      _db.transaction(() async {
        if (await state() != null) return;
        if (!canShare(kind)) throw StateError('${kind.label} is not shared');
        final me = _uuid();
        final pair = await ShareKeyPair.generate();
        await _db
            .into(_db.shareState)
            .insert(
              ShareStateCompanion.insert(
                spaceShareId: _uuid(),
                myMemberId: me,
                ownerId: me,
                seed: Uint8List.fromList(pair.seed),
                epoch: 0,
                keys: jsonEncode({'0': base64Url.encode(_codec.newSpaceKey())}),
              ),
            );
        await _log(
          await _newChange(ShareEntity.member, me, insertField, {
            'name': myName,
            'role': ShareRole.owner.name,
            'key': pair.publicKey,
            'account': hasAccount,
            'sign': await ShareSigner.publicKey(pair.seed),
          }),
        );
        await _markAllDirty();
        await recordLocalChanges();
      });

  /// Step 1 of joining, on the invitee's phone: a key pair made here and
  /// a join request carrying its public key and [name], with the safety
  /// words both phones show. The private key never leaves this phone.
  static Future<(String, ShareKeyPair, List<String>)> makeJoinRequest(
    String name,
  ) async {
    final pair = await ShareKeyPair.generate();
    final codec = ShareCodec();
    return (
      codec.joinRequest(
        name: name,
        publicKey: pair.publicKey,
        signKey: await ShareSigner.publicKey(pair.seed),
      ),
      pair,
      joinWords(pair.publicKey),
    );
  }

  /// A join request's name and safety words, as the Owner's phone shows
  /// them.
  static (String, List<String>) readJoinRequest(String request) {
    final (name, key) = ShareCodec().openJoinRequest(request);
    return (name, joinWords(key));
  }

  /// An invite's details. Anyone holding it can read them; only the phone
  /// that made the join request can open the space key in it.
  static Map<String, Object?> readInvite(String invite) =>
      ShareCodec().readInvite(invite);

  /// The safety words an invite shows on the phone it was made for: from
  /// the space, the Owner's key in it and [mine].
  static List<String> inviteWords(String invite, ShareKeyPair mine) {
    final body = ShareCodec().readInvite(invite);
    return safetyWords(
      spaceShareId: body['space']! as String,
      keyA: base64Url.decode(body['ownerKey']! as String),
      keyB: mine.publicKey,
    );
  }

  /// Step 3, on the invitee's phone: joins from [invite] with [mine], the
  /// key pair its join request was made with, as [myName]. The space's
  /// records come with the Owner's first update file.
  Future<void> join(
    String invite, {
    required ShareKeyPair mine,
    required String myName,
    bool hasAccount = false,
  }) => _db.transaction(() async {
    final pair = mine;
    final (body, key) = await _codec.openInvite(invite, mine);
    if (await state() != null) throw StateError('Already shared');
    final owner = body['owner']! as Map;
    final you = body['you']! as Map;
    final ownerId = owner['id']! as String;
    final me = you['id']! as String;
    final epoch = body['epoch']! as int;
    await _db
        .into(_db.shareState)
        .insert(
          ShareStateCompanion.insert(
            spaceShareId: body['space']! as String,
            myMemberId: me,
            ownerId: ownerId,
            seed: Uint8List.fromList(pair.seed),
            epoch: epoch,
            keys: jsonEncode({'$epoch': base64Url.encode(key)}),
          ),
        );
    // The Owner's record and this member's, as the invite gave them,
    // until the Owner's first file brings the log. Clocked as the
    // Owner's, so the file's own copies replace them.
    for (final (id, value) in [
      (
        ownerId,
        {
          'name': owner['name'],
          'role': ShareRole.owner.name,
          'key': base64Url.decode(body['ownerKey']! as String),
          'account': owner['account'] == true,
        },
      ),
      (
        me,
        {
          'name': myName,
          'role': you['role'],
          'key': pair.publicKey,
          'account': hasAccount,
          'sign': await ShareSigner.publicKey(pair.seed),
        },
      ),
    ]) {
      await _log(
        ShareChange(
          hlc: Hlc(0, id == ownerId ? 0 : 1, ownerId),
          entity: ShareEntity.member,
          record: id,
          field: insertField,
          value: value,
          author: ownerId,
        ),
      );
    }
    await _db
        .into(_db.sharePeers)
        .insertOnConflictUpdate(
          SharePeersCompanion.insert(
            memberId: ownerId,
            wordsChecked: const Value(true),
            joinedAt: Value(_nowTime),
          ),
        );
    // This phone's name in the space goes to the others as its own
    // change.
    if (myName != you['name']) {
      await _log(await _newChange(ShareEntity.member, me, 'name', myName));
    }
    if (hasAccount) {
      await _log(await _newChange(ShareEntity.member, me, 'account', true));
    }
    // Nothing here is sent until it changes: the space's records come
    // from the Owner's first file.
  });

  Future<ShareLog> log() async {
    final s = await _state();
    final rows = await (_db.select(
      _db.shareChanges,
    )..orderBy([(c) => OrderingTerm(expression: c.seq)])).get();
    return ShareLog(s.ownerId, kind, rows.map(_fromRow));
  }

  ShareChange _fromRow(ShareChangeRow r) => ShareChange(
    hlc: Hlc.parse(r.hlc),
    entity: ShareEntity.byName(r.entity)!,
    record: r.record,
    field: r.field,
    value: r.value == null ? null : jsonDecode(r.value!),
    previous: r.previous == null ? null : jsonDecode(r.previous!),
    base: r.base == null ? null : Hlc.parse(r.base!),
    author: r.author,
    recordedBy: r.recordedBy,
  );

  Future<int> _log(ShareChange c, {String? fromFile}) => _db
      .into(_db.shareChanges)
      .insert(
        ShareChangesCompanion.insert(
          hlc: c.hlc.toString(),
          entity: c.entity.name,
          record: c.record,
          field: c.field,
          value: Value(c.value == null ? null : jsonEncode(c.value)),
          previous: Value(c.previous == null ? null : jsonEncode(c.previous)),
          base: Value(c.base?.toString()),
          author: c.author,
          recordedBy: Value(c.recordedBy),
          fromFile: Value(fromFile),
          loggedAt: _nowTime,
        ),
        mode: InsertMode.insertOrIgnore,
      );

  Future<Hlc> _clock() async {
    final row = await _db
        .customSelect('SELECT MAX(hlc) AS h FROM share_changes')
        .getSingle();
    final h = row.read<String?>('h');
    return h == null ? Hlc.zero : Hlc.parse(h);
  }

  Future<ShareChange> _newChange(
    ShareEntity entity,
    String record,
    String field,
    Object? value, {
    Object? previous,
    Hlc? base,
    int? at,
    String? author,
    String? recordedBy,
  }) async {
    final s = await _state();
    final hlc = (await _clock()).send(at ?? _now(), s.myMemberId);
    return ShareChange(
      hlc: hlc,
      entity: entity,
      record: record,
      field: field,
      value: value,
      previous: previous,
      base: base,
      author: author ?? s.myMemberId,
      recordedBy: recordedBy,
    );
  }

  Future<void> _markAllDirty() async {
    final at = _now();
    for (final MapEntry(key: entity, value: table) in shareTables.entries) {
      await _db.customStatement(
        'INSERT OR REPLACE INTO share_dirty (entity, row_id, at) '
        "SELECT '$entity', id, $at FROM $table",
      );
    }
  }

  // ---------------------------------------------------------------- rows

  static const _entityOrder = [
    ShareEntity.account,
    ShareEntity.category,
    ShareEntity.budget,
    ShareEntity.transaction,
  ];

  /// A row's shared fields, or null when it is not shared: the accounts
  /// that hold another space's money stay on this phone (decision 0027),
  /// with their transactions. Messages' codes, hashes and balances never
  /// leave the phone.
  Future<(String, Map<String, Object?>)?> _rowFields(
    ShareEntity entity,
    int id,
  ) async {
    final sql = switch (entity) {
      ShareEntity.account =>
        'SELECT share_uid AS uid, name, type, currency, '
            'opening_balance_minor AS opening, opening_date AS since '
            "FROM accounts WHERE id = ? AND type <> 'heldForSpace'",
      ShareEntity.category =>
        'SELECT share_uid AS uid, name, type, key, '
            'is_daily_spending AS daily FROM categories WHERE id = ?',
      ShareEntity.budget =>
        'SELECT b.share_uid AS uid, b.month, b.name, c.share_uid AS category, '
            'b.amount_minor AS amount, b.kind, b.is_paid AS paid '
            'FROM budget_items b LEFT JOIN categories c ON c.id = b.category_id '
            'WHERE b.id = ?',
      ShareEntity.transaction =>
        'SELECT t.share_uid AS uid, a.share_uid AS account, '
            't.occurred_at AS at, t.amount_minor AS amount, t.direction, '
            't.kind, t.fee_minor AS fee, t.currency, '
            'c.share_uid AS category, t.item, t.counterparty_name AS name '
            'FROM transactions t JOIN accounts a ON a.id = t.account_id '
            'LEFT JOIN categories c ON c.id = '
            'COALESCE(t.category_override_id, t.auto_category_id) '
            "WHERE t.id = ? AND a.type <> 'heldForSpace'",
      ShareEntity.member ||
      ShareEntity.policy ||
      ShareEntity.approval => throw ArgumentError(entity),
    };
    final row = await _db
        .customSelect(sql, variables: [Variable.withInt(id)])
        .getSingleOrNull();
    if (row == null) return null;
    final data = Map<String, Object?>.of(row.data);
    final uid = data.remove('uid') as String?;
    if (uid == null) return null;
    return (uid, data);
  }

  /// Puts what changed on this phone since last time in the log, one
  /// change per field, clocked at when it was changed. Returns how many
  /// changes it logged.
  Future<int> recordLocalChanges() => _db.transaction(() async {
    final s = await state();
    if (s == null) return 0;
    final dirty = await (_db.select(
      _db.shareDirty,
    )..orderBy([(d) => OrderingTerm(expression: d.at)])).get();
    if (dirty.isEmpty) return 0;
    final log = await this.log();
    var count = 0;
    final sorted = [...dirty]
      ..sort(
        (a, b) => _entityOrder
            .indexOf(ShareEntity.byName(a.entity)!)
            .compareTo(_entityOrder.indexOf(ShareEntity.byName(b.entity)!)),
      );
    for (final d in sorted) {
      final entity = ShareEntity.byName(d.entity)!;
      final now = await _rowFields(entity, d.rowId);
      if (now == null) {
        final uid = d.removedUid;
        if (uid != null && log.exists(entity, uid)) {
          final c = await _newChange(
            entity,
            uid,
            removeField,
            null,
            previous: log.fields(entity, uid),
            at: _fixedClock ? _now() : d.at,
          );
          log.add(c);
          await _log(c);
          await (_db.delete(
                _db.shareSeen,
              )..where((r) => r.entity.equals(entity.name) & r.uid.equals(uid)))
              .go();
          count++;
        }
        continue;
      }
      final (uid, fields) = now;
      final seen = log.fields(entity, uid);
      if (seen == null) {
        final c = await _newChange(
          entity,
          uid,
          insertField,
          fields,
          at: _fixedClock ? _now() : d.at,
        );
        log.add(c);
        await _log(c);
        count++;
      } else {
        for (final MapEntry(:key, :value) in fields.entries) {
          if (seen[key] == value) continue;
          final base =
              log.latest(entity, uid, key)?.hlc ??
              log.latest(entity, uid, insertField)!.hlc;
          final c = await _newChange(
            entity,
            uid,
            key,
            value,
            previous: seen[key],
            base: base,
            at: _fixedClock ? _now() : d.at,
          );
          log.add(c);
          await _log(c);
          count++;
        }
      }
    }
    await _db.delete(_db.shareDirty).go();
    // A change that waits for approval does not count yet, here either:
    // the row shows the old value until an approver says yes.
    final waiting = {
      for (final c in log.needingApproval)
        if (c.hlc.node == s.myMemberId && log.answer(c.id) == null)
          '${c.entity.name}|${c.record}',
    };
    if (waiting.isNotEmpty) {
      await _writeRecords(log, waiting);
      await JournalRepository(_db).sync();
    }
    return count;
  });

  // ------------------------------------------------------------- members

  Future<Map<String, ShareMember>> members() async => (await log()).members;

  Future<List<SharePeerRow>> peers() => _db.select(_db.sharePeers).get();

  /// Step 2, on the Owner's phone: from someone's join request, a member
  /// record with their own public key, and the invite that seals the space
  /// key to it. Returns the invite, the member, and the safety words their
  /// phone shows on opening it.
  Future<(String, ShareMember, List<String>)> invite({
    required String request,
    required ShareRole role,
    required String spaceName,
  }) => _db.transaction(() async {
    final s = await _state();
    final log = await this.log();
    if (log.roleOf(s.myMemberId) != ShareRole.owner) {
      throw StateError('Only the Owner adds people');
    }
    if (!ShareRole.offeredIn(kind).contains(role)) {
      throw ArgumentError.value(role, 'role');
    }
    final count = log.members.values.where((m) => !m.removed).length;
    if (count >= memberLimit(kind)!) throw const ShareLimitReached();
    final (name, theirKey) = _codec.openJoinRequest(request);
    final me = await ShareKeyPair.fromSeed(s.seed);
    final id = _uuid();
    final member = ShareMember(
      id: id,
      name: name,
      role: role,
      publicKey: theirKey,
    );
    await _log(
      await _newChange(ShareEntity.member, id, insertField, {
        'name': name,
        'role': role.name,
        'key': theirKey,
        'account': false,
        'sign': ?_codec.joinSignKey(request),
      }),
    );
    await _db
        .into(_db.sharePeers)
        .insertOnConflictUpdate(
          SharePeersCompanion.insert(memberId: id, joinedAt: Value(_nowTime)),
        );
    final owner = log.members[s.myMemberId];
    final text = await _codec.invite(
      owner: me,
      inviteePublicKey: theirKey,
      spaceKey: _keys(s)[s.epoch]!,
      details: {
        'space': s.spaceShareId,
        'name': spaceName,
        'kind': kind.name,
        'epoch': s.epoch,
        'owner': {
          'id': s.myMemberId,
          'name': owner?.name ?? '',
          'account': owner?.hasAccount ?? false,
        },
        'you': {'id': id, 'name': name, 'role': role.name},
      },
    );
    // The words both phones show once the invite is open: they cover the
    // Owner's key too, so an invite from anyone else shows other words.
    return (
      text,
      member,
      safetyWords(
        spaceShareId: s.spaceShareId,
        keyA: me.publicKey,
        keyB: theirKey,
      ),
    );
  });

  Future<void> setRole(String memberId, ShareRole role) async {
    await recordLocalChanges();
    final s = await _state();
    final log = await this.log();
    if (log.roleOf(s.myMemberId) != ShareRole.owner) {
      throw StateError('Only the Owner changes roles');
    }
    if (!ShareRole.offeredIn(kind).contains(role)) {
      throw ArgumentError.value(role, 'role');
    }
    final now = log.roleOf(memberId);
    if (now == null || now == role) return;
    await _log(
      await _newChange(
        ShareEntity.member,
        memberId,
        'role',
        role.name,
        previous: now.name,
        base:
            (log.latest(ShareEntity.member, memberId, 'role') ??
                    log.latest(ShareEntity.member, memberId, insertField))!
                .hlc,
      ),
    );
  }

  /// Removes [memberId] and replaces the space key: their phone keeps what
  /// it had, but cannot open anything sent from now on.
  Future<void> remove(String memberId) => _db.transaction(() async {
    await recordLocalChanges();
    final s = await _state();
    final log = await this.log();
    if (log.roleOf(s.myMemberId) != ShareRole.owner || memberId == s.ownerId) {
      throw StateError('Only the Owner removes people');
    }
    if (log.roleOf(memberId) == null) return;
    await _log(
      await _newChange(
        ShareEntity.member,
        memberId,
        removeField,
        null,
        previous: log.fields(ShareEntity.member, memberId),
      ),
    );
    final keys = {..._keys(s), s.epoch + 1: _codec.newSpaceKey()};
    await _db
        .update(_db.shareState)
        .write(
          ShareStateCompanion(
            epoch: Value(s.epoch + 1),
            keys: Value(_keysJson(keys)),
          ),
        );
  });

  String _keysJson(Map<int, List<int>> keys) => jsonEncode({
    for (final e in keys.entries) '${e.key}': base64Url.encode(e.value),
  });

  Future<List<String>> wordsWith(String memberId) async {
    final s = await _state();
    final them = (await members())[memberId];
    final me = await ShareKeyPair.fromSeed(s.seed);
    return safetyWords(
      spaceShareId: s.spaceShareId,
      keyA: me.publicKey,
      keyB: them?.publicKey ?? const [],
    );
  }

  Future<void> markWordsChecked(String memberId) => _db
      .into(_db.sharePeers)
      .insert(
        SharePeersCompanion.insert(
          memberId: memberId,
          wordsChecked: const Value(true),
        ),
        onConflict: DoUpdate(
          (_) => const SharePeersCompanion(wordsChecked: Value(true)),
        ),
      );

  // --------------------------------------------------------------- files

  /// An update file for [memberId] with only what they have not been sent.
  Future<OutgoingShare> buildUpdate(
    String memberId, {
    required String spaceName,
  }) async {
    await recordLocalChanges();
    final s = await _state();
    final log = await this.log();
    final myRole = log.roleOf(s.myMemberId);
    if (myRole == null || !myRole.canSend) throw const ShareRefused.viewer();
    final to = log.members[memberId];
    if (to == null || to.removed || to.publicKey == null) {
      throw StateError('Not a member');
    }
    final peer = await (_db.select(
      _db.sharePeers,
    )..where((p) => p.memberId.equals(memberId))).getSingleOrNull();
    final sentUpTo = peer?.sentUpTo ?? 0;
    final rows =
        await (_db.select(_db.shareChanges)
              ..where((c) => c.seq.isBiggerThanValue(sentUpTo))
              ..orderBy([(c) => OrderingTerm(expression: c.seq)]))
            .get();
    final changes = rows.map(_fromRow).toList();
    final added = <String>{};
    final changed = <String>{};
    for (final c in changes) {
      if (c.entity.logOnly) continue;
      (c.isInsert && !changed.contains(c.record) ? added : changed).add(
        c.record,
      );
    }
    changed.removeAll(added);
    final fileId = _uuid();
    final at = _nowTime;
    final keys = _keys(s);
    final bytes = await _codec.seal(
      header: ShareFileHeader(
        space: s.spaceShareId,
        file: fileId,
        from: s.myMemberId,
        to: memberId,
        epoch: s.epoch,
        at: at,
      ),
      spaceKey: keys[s.epoch]!,
      mySeed: s.seed,
      theirPublic: to.publicKey!,
      payload: {
        'changes': [for (final c in changes) c.toJson()],
      },
      // A replaced key goes, sealed to them alone, in every file after
      // someone is removed.
      carryKey: s.epoch > 0,
    );
    final me = await ShareKeyPair.fromSeed(s.seed);
    return OutgoingShare(
      bytes: bytes,
      fileName: '${_slug(spaceName)}-${at.day}${_mon[at.month - 1]}.pcshare',
      to: to,
      added: added.length,
      changed: changed.length,
      upTo: rows.isEmpty ? sentUpTo : rows.last.seq,
      words: safetyWords(
        spaceShareId: s.spaceShareId,
        keyA: me.publicKey,
        keyB: to.publicKey!,
      ),
      wordsChecked: peer?.wordsChecked ?? false,
    );
  }

  /// After [out] went: the next file to them starts after it.
  Future<void> markSent(OutgoingShare out) => _db
      .into(_db.sharePeers)
      .insert(
        SharePeersCompanion.insert(
          memberId: out.to.id,
          sentUpTo: Value(out.upTo),
          lastSentAt: Value(_nowTime),
          wordsChecked: const Value(true),
        ),
        onConflict: DoUpdate(
          (_) => SharePeersCompanion(
            sentUpTo: Value(out.upTo),
            lastSentAt: Value(_nowTime),
            // The words were on screen as it was sent: checked once.
            wordsChecked: const Value(true),
          ),
        ),
      );

  Future<(ShareStateRow, ShareLog, OpenedShareFile, ShareMember)> _open(
    List<int> bytes,
  ) async {
    await recordLocalChanges();
    final s = await _state();
    final log = await this.log();
    final ShareFileHeader header;
    try {
      header = _codec.readHeader(bytes);
    } on ShareFileException {
      throw const ShareRefused.unreadable();
    }
    if (header.space != s.spaceShareId || header.to != s.myMemberId) {
      throw const ShareRefused.unreadable();
    }
    final from = log.members[header.from];
    if (from == null || from.removed || from.publicKey == null) {
      throw const ShareRefused.notMember();
    }
    if (!from.role.canSend) throw const ShareRefused.viewer();
    // Only the Owner replaces the key, and a file under an older key than
    // this phone has is from before a removal.
    if (header.rekeyWrapped != null && from.role != ShareRole.owner) {
      if (header.epoch != s.epoch) throw const ShareRefused.unreadable();
    }
    if (header.epoch < s.epoch) throw const ShareRefused.unreadable();
    final keys = _keys(s);
    final OpenedShareFile opened;
    try {
      opened = await _codec.open(
        bytes,
        keyFor: (e) => keys[e],
        mySeed: s.seed,
        theirPublic: from.publicKey!,
      );
    } on ShareFileException {
      throw const ShareRefused.unreadable();
    }
    if (header.epoch > s.epoch && from.role != ShareRole.owner) {
      throw const ShareRefused.unreadable();
    }
    return (s, log, opened, from);
  }

  List<ShareChange> _changes(OpenedShareFile f) {
    final raw = f.payload['changes'];
    if (raw is! List) throw const ShareRefused.unreadable();
    try {
      return [for (final c in raw) ShareChange.fromJson(c)];
    } on Object {
      throw const ShareRefused.unreadable();
    }
  }

  /// What [bytes] would do here, without changing anything.
  Future<IncomingShare> preview(List<int> bytes) async {
    final (s, log, opened, from) = await _open(bytes);
    final already = await (_db.select(
      _db.shareFiles,
    )..where((f) => f.fileId.equals(opened.header.file))).getSingleOrNull();
    final incoming = _changes(opened);
    final outcome = log.merge(
      from.id,
      incoming,
      signed: await _signed(s, log, incoming),
    );
    final peer = await (_db.select(
      _db.sharePeers,
    )..where((p) => p.memberId.equals(from.id))).getSingleOrNull();
    final members = log.members;
    return IncomingShare(
      bytes: bytes,
      from: from,
      header: opened.header,
      outcome: outcome,
      alreadyApplied: already != null,
      wordsChecked: peer?.wordsChecked ?? false,
      conflictLines: [
        for (final c in outcome.conflicts)
          _conflictLine(log, c, members, s.myMemberId),
      ],
    );
  }

  /// Opens [bytes] and writes what it holds. Balances and the journal are
  /// worked out again from the records; nothing about them is merged.
  Future<MergeOutcome> apply(List<int> bytes) => _db.transaction(() async {
    final (s, log, opened, from) = await _open(bytes);
    final fileId = opened.header.file;
    final incoming = _changes(opened);
    final outcome = log.merge(
      from.id,
      incoming,
      signed: await _signed(s, log, incoming),
    );
    final already = await (_db.select(
      _db.shareFiles,
    )..where((f) => f.fileId.equals(fileId))).getSingleOrNull();
    if (already != null) return outcome;
    for (final c in outcome.accepted) {
      await _log(c, fromFile: fileId);
    }
    for (final conflict in outcome.conflicts) {
      await (_db.update(_db.shareChanges)
            ..where((r) => r.hlc.equals(conflict.loser.id)))
          .write(ShareChangesCompanion(lostTo: Value(conflict.winner.id)));
      await (_db.update(_db.shareChanges)
            ..where((r) => r.hlc.equals(conflict.winner.id)))
          .write(ShareChangesCompanion(wonOver: Value(conflict.loser.id)));
    }
    // A new space key from the Owner.
    if (opened.header.epoch > s.epoch) {
      await _db
          .update(_db.shareState)
          .write(
            ShareStateCompanion(
              epoch: Value(opened.header.epoch),
              keys: Value(
                _keysJson({..._keys(s), opened.header.epoch: opened.spaceKey}),
              ),
            ),
          );
    }
    await _writeRecords(log, outcome.touched);
    await _db
        .into(_db.shareFiles)
        .insert(
          ShareFilesCompanion.insert(
            fileId: fileId,
            fromMember: from.id,
            appliedAt: _nowTime,
          ),
        );
    await _db
        .into(_db.sharePeers)
        .insert(
          SharePeersCompanion.insert(
            memberId: from.id,
            lastFromAt: Value(_nowTime),
            wordsChecked: const Value(true),
          ),
          onConflict: DoUpdate(
            (_) => SharePeersCompanion(
              lastFromAt: Value(_nowTime),
              wordsChecked: const Value(true),
            ),
          ),
        );
    await JournalRepository(_db).sync();
    return outcome;
  });

  // ----------------------------------------------------------- approvals

  static String _answerMessage(String space, ShareChange d) =>
      'pcshare approval|$space|${d.id}|${d.record}|${d.field}';

  /// The answers in [incoming] whose signature checks out against the
  /// approver's key in the member list. Nothing else vouches for them: a
  /// file can carry answers it was handed by others.
  Future<Set<String>> _signed(
    ShareStateRow s,
    ShareLog log,
    List<ShareChange> incoming,
  ) async {
    final members = log.members;
    final out = <String>{};
    for (final d in incoming) {
      if (d.entity != ShareEntity.approval || d.value is! Map) continue;
      if (await ShareSigner.verify(
        members[d.author]?.signKey,
        _answerMessage(s.spaceShareId, d),
        (d.value! as Map)['sig'],
      )) {
        out.add(d.id);
      }
    }
    return out;
  }

  /// Who can change what in this space now.
  Future<SharePolicy> policy() async => (await log()).policyAt();

  /// Sets one of the rules. The Owner's alone.
  Future<void> setPolicy(SharePolicy policy) => _db.transaction(() async {
    final s = await _state();
    final log = await this.log();
    if (log.roleOf(s.myMemberId) != ShareRole.owner) {
      throw StateError('Only the Owner sets who can change what');
    }
    final now = log.policyAt();
    final fields = policy.toFields();
    final insert = log.latest(ShareEntity.policy, policyRecord, insertField);
    if (insert == null) {
      await _log(
        await _newChange(ShareEntity.policy, policyRecord, insertField, fields),
      );
      return;
    }
    final before = now.toFields();
    for (final MapEntry(:key, :value) in fields.entries) {
      if (before[key] == value) continue;
      await _log(
        await _newChange(
          ShareEntity.policy,
          policyRecord,
          key,
          value,
          previous: before[key],
        ),
      );
    }
  });

  /// Marks [memberId] "Can approve", or not. The Owner's alone.
  Future<void> setApprover(String memberId, {required bool approver}) async {
    final s = await _state();
    final log = await this.log();
    if (log.roleOf(s.myMemberId) != ShareRole.owner) {
      throw StateError('Only the Owner chooses who can approve');
    }
    final m = log.members[memberId];
    if (m == null || m.removed || m.approver == approver) return;
    await _log(
      await _newChange(
        ShareEntity.member,
        memberId,
        'approver',
        approver,
        previous: m.approver,
      ),
    );
  }

  /// Changes waiting for an answer from this phone's member, oldest first.
  /// Lapsed ones and this member's own are left out.
  Future<List<WaitingChange>> toApprove() async {
    await recordLocalChanges();
    final s = await _state();
    final log = await this.log();
    if (!log.canApprove(s.myMemberId)) return const [];
    return _describe(s, log, (c) => c.hlc.node != s.myMemberId);
  }

  /// This member's own changes and their answers, by record uid, for the
  /// line under a row.
  Future<List<WaitingChange>> mine() async {
    final s = await _state();
    final log = await this.log();
    return _describe(s, log, (c) => c.hlc.node == s.myMemberId, answered: true);
  }

  Future<List<WaitingChange>> _describe(
    ShareStateRow s,
    ShareLog log,
    bool Function(ShareChange) which, {
    bool answered = false,
  }) async {
    final now = _now();
    final members = log.members;
    String who(String id) => id == s.myMemberId
        ? 'you'
        : (members[id]?.name.split(' ').first ?? 'someone');
    final out = <WaitingChange>[];
    for (final c in log.needingApproval) {
      if (!which(c)) continue;
      final state = log.stateOf(c.id, now)!;
      if (state == ApprovalState.lapsed) continue;
      if (!answered && state != ApprovalState.waiting) continue;
      final row = await (_db.select(
        _db.shareChanges,
      )..where((r) => r.hlc.equals(c.id))).getSingleOrNull();
      final from = row?.fromFile == null
          ? null
          : (await (_db.select(_db.shareFiles)
                      ..where((f) => f.fileId.equals(row!.fromFile!)))
                    .getSingleOrNull())
                ?.fromMember;
      final fields =
          log.fields(c.entity, c.record) ??
          (c.isInsert ? (c.value as Map?)?.cast<String, Object?>() : null) ??
          (c.previous as Map?)?.cast<String, Object?>();
      final label = _label(c.entity, fields);
      final (addedBy, _) = log.addedBy(c.entity, c.record) ?? (c.author, null);
      final by = who(c.hlc.node);
      final cap = by[0].toUpperCase() + by.substring(1);
      final amount = fields?['amount'];
      final money = amount is int ? ' (KES ${_money(amount)})' : '';
      final owner = addedBy == c.hlc.node
          ? ''
          : addedBy == s.myMemberId
          ? 'your '
          : "${who(addedBy)[0].toUpperCase()}${who(addedBy).substring(1)}'s ";
      final String title;
      final String mineLine;
      if (c.isRemove) {
        title = '$cap wants to delete "$label"$money';
        mineLine = 'you asked to delete it';
      } else if (c.isInsert) {
        title = '$cap wants to add "$label"$money';
        mineLine = 'you added it';
      } else {
        final to = c.value is int ? _money(c.value! as int) : '${c.value}';
        final was = c.previous is int
            ? _money(c.previous! as int)
            : c.previous?.toString();
        title = c.field == 'amount' && was != null
            ? '$cap wants to change $owner"$label" from $was to $to'
            : '$cap wants to change $owner"$label"\'s ${_fieldName(c.field)}';
        mineLine = c.field == 'amount'
            ? 'you asked to change it to $to'
            : 'you asked to change its ${_fieldName(c.field)}';
      }
      final added = log.latest(c.entity, c.record, insertField);
      final addedOn = added == null || added.hlc.millis == 0
          ? ''
          : ' on ${_dayLabel(added.hlc.millis)}';
      final a = log.answer(c.id);
      out.add(
        WaitingChange(
          id: c.id,
          entity: c.entity,
          record: c.record,
          title: title,
          detail: 'Added by ${who(addedBy)}$addedOn',
          fromMember: from,
          at: DateTime.fromMillisecondsSinceEpoch(c.hlc.millis),
          state: state,
          mineLine: switch (state) {
            ApprovalState.waiting => '$mineLine · Waiting for approval',
            ApprovalState.declined => 'Declined by ${who(a!.author)}',
            _ => null,
          },
        ),
      );
    }
    out.sort((x, y) => x.at.compareTo(y.at));
    return out;
  }

  /// Says yes or no to waiting change [id], signed with this member's key.
  /// The answer goes to the others in the next update file.
  Future<void> answer(String id, {required bool yes}) =>
      _db.transaction(() async {
        await recordLocalChanges();
        final s = await _state();
        final log = await this.log();
        final target = log.needingApproval.where((c) => c.id == id).firstOrNull;
        if (target == null) throw StateError('Nothing waits with that id');
        final unsigned = await _newChange(
          ShareEntity.approval,
          id,
          yes ? approveField : declineField,
          null,
        );
        if (!log.validAnswer(unsigned, target)) {
          throw StateError('You cannot answer this change');
        }
        if (log.answer(id) != null) return;
        final sig = await ShareSigner.sign(
          s.seed,
          _answerMessage(s.spaceShareId, unsigned),
        );
        final d = ShareChange(
          hlc: unsigned.hlc,
          entity: unsigned.entity,
          record: unsigned.record,
          field: unsigned.field,
          value: {'sig': base64Url.encode(sig)},
          author: unsigned.author,
        );
        await _log(d);
        log.add(d);
        await _writeRecords(log, {'${target.entity.name}|${target.record}'});
        await JournalRepository(_db).sync();
      });

  /// "Use mine instead": puts the value of the change that lost back, as a
  /// new change that is later than the one that won.
  Future<void> useMine(String lostHlc) => _db.transaction(() async {
    await recordLocalChanges();
    final row = await (_db.select(
      _db.shareChanges,
    )..where((r) => r.hlc.equals(lostHlc))).getSingle();
    final lost = _fromRow(row);
    final log = await this.log();
    final now = log.latest(lost.entity, lost.record, lost.field);
    final c = await _newChange(
      lost.entity,
      lost.record,
      lost.field,
      lost.value,
      previous: now?.value,
      base: now?.hlc,
    );
    await _log(c);
    log.add(c);
    await _writeRecords(log, {'${lost.entity.name}|${lost.record}'});
    await JournalRepository(_db).sync();
  });

  /// "Bring it back": adds a removed record again, as it was.
  Future<void> bringBack(ShareEntity entity, String uid) =>
      _db.transaction(() async {
        await recordLocalChanges();
        final log = await this.log();
        if (log.exists(entity, uid)) return;
        final removal = log.latest(entity, uid, removeField);
        final insert = log.latest(entity, uid, insertField);
        final fields = (removal?.previous ?? insert?.value) as Map?;
        if (fields == null) return;
        final (by, recordedBy) = log.addedBy(entity, uid) ?? (null, null);
        final c = await _newChange(
          entity,
          uid,
          insertField,
          Map<String, Object?>.of(fields.cast()),
          author: by,
          recordedBy: recordedBy == null && by != (await _state()).myMemberId
              ? (await _state()).myMemberId
              : recordedBy,
        );
        await _log(c);
        log.add(c);
        await _writeRecords(log, {'${entity.name}|$uid'});
        await JournalRepository(_db).sync();
      });

  /// Writes the rows of [touched] (`entity|uid`) as the log has them now,
  /// and notes them as seen so they are not sent back as this phone's own.
  Future<void> _writeRecords(ShareLog log, Set<String> touched) async {
    final items = [
      for (final t in touched)
        (
          ShareEntity.byName(t.split('|').first)!,
          t.substring(t.indexOf('|') + 1),
        ),
    ]..sort((a, b) => _order(a.$1).compareTo(_order(b.$1)));
    final members = log.members;
    for (final (entity, uid) in items) {
      if (entity.logOnly) continue;
      final fields = log.fields(entity, uid);
      if (fields == null) {
        await _deleteRow(entity, uid);
      } else {
        final (by, recordedBy) = log.addedBy(entity, uid) ?? (null, null);
        await _upsertRow(entity, uid, fields, by, recordedBy, members);
      }
    }
    await _db.delete(_db.shareDirty).go();
  }

  int _order(ShareEntity e) {
    final i = _entityOrder.indexOf(e);
    return i < 0 ? 99 : i;
  }

  Future<int?> _idOf(String table, Object? uid) async {
    if (uid is! String) return null;
    final row = await _db
        .customSelect(
          'SELECT id FROM $table WHERE share_uid = ? LIMIT 1',
          variables: [Variable.withString(uid)],
        )
        .getSingleOrNull();
    return row?.read<int>('id');
  }

  Future<void> _deleteRow(ShareEntity entity, String uid) async {
    final table = shareTables[entity.name]!;
    final id = await _idOf(table, uid);
    if (id == null) return;
    try {
      if (entity == ShareEntity.category) {
        for (final sql in [
          'UPDATE transactions SET category_override_id = NULL '
              'WHERE category_override_id = ?',
          'UPDATE budget_items SET category_id = NULL WHERE category_id = ?',
          'UPDATE payees SET default_category_id = NULL '
              'WHERE default_category_id = ?',
        ]) {
          await _db.customStatement(sql, [id]);
        }
      }
      await _db.customStatement('DELETE FROM $table WHERE id = ?', [id]);
    } on Object {
      // Still used by something kept on this phone only: it stays here.
    }
  }

  Future<void> _upsertRow(
    ShareEntity entity,
    String uid,
    Map<String, Object?> f,
    String? addedBy,
    String? recordedBy,
    Map<String, ShareMember> members,
  ) async {
    final table = shareTables[entity.name]!;
    var id = await _idOf(table, uid);
    switch (entity) {
      case ShareEntity.account:
        var type = f['type'];
        if (id != null) {
          // An account kept for money between spaces keeps its kind here.
          final row = await _db
              .customSelect(
                'SELECT type FROM accounts WHERE id = ?',
                variables: [Variable.withInt(id)],
              )
              .getSingle();
          final local = row.read<String>('type');
          if (const ['ownersAccount', 'paidBySpace'].contains(local)) {
            type = local;
          }
        } else if (const ['ownersAccount', 'paidBySpace'].contains(type)) {
          type = AccountType.other.name;
        }
        final values = [
          f['name'],
          type,
          f['currency'],
          f['opening'],
          f['since'],
        ];
        if (id == null) {
          await _db.customStatement(
            'INSERT INTO accounts (name, type, currency, '
            'opening_balance_minor, opening_date, share_uid) '
            'VALUES (?, ?, ?, ?, ?, ?)',
            [...values, uid],
          );
        } else {
          await _db.customStatement(
            'UPDATE accounts SET name = ?, type = ?, currency = ?, '
            'opening_balance_minor = ?, opening_date = ? WHERE id = ?',
            [...values, id],
          );
        }
      case ShareEntity.category:
        if (id == null) {
          // The same name made on two phones becomes one category.
          final same = await _db
              .customSelect(
                'SELECT id FROM categories WHERE name = ?',
                variables: [Variable.withString(f['name']! as String)],
              )
              .getSingleOrNull();
          if (same != null) {
            id = same.read<int>('id');
            await _db.customStatement(
              'UPDATE categories SET share_uid = ? WHERE id = ?',
              [uid, id],
            );
          }
        }
        final values = [f['name'], f['type'], f['key'], f['daily']];
        if (id == null) {
          await _db.customStatement(
            'INSERT INTO categories (name, type, key, is_daily_spending, '
            'share_uid) VALUES (?, ?, ?, ?, ?)',
            [...values, uid],
          );
        } else {
          await _db.customStatement(
            'UPDATE categories SET name = ?, type = ?, key = ?, '
            'is_daily_spending = ? WHERE id = ?',
            [...values, id],
          );
        }
      case ShareEntity.budget:
        final values = [
          f['month'],
          f['name'],
          await _idOf('categories', f['category']),
          f['amount'],
          f['kind'],
          f['paid'],
        ];
        if (id == null) {
          await _db.customStatement(
            'INSERT INTO budget_items (month, name, category_id, '
            'amount_minor, kind, is_paid, share_uid) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            [...values, uid],
          );
        } else {
          await _db.customStatement(
            'UPDATE budget_items SET month = ?, name = ?, category_id = ?, '
            'amount_minor = ?, kind = ?, is_paid = ? WHERE id = ?',
            [...values, id],
          );
        }
      case ShareEntity.transaction:
        final account = await _idOf('accounts', f['account']);
        if (account == null) return;
        final values = [
          account,
          f['at'],
          f['amount'],
          f['direction'],
          f['kind'],
          f['fee'],
          f['currency'],
          await _idOf('categories', f['category']),
          f['item'],
          f['name'],
          addedBy,
          recordedBy,
        ];
        if (id == null) {
          await _db.customStatement(
            'INSERT INTO transactions (account_id, occurred_at, amount_minor, '
            'direction, kind, fee_minor, currency, category_override_id, '
            'item, counterparty_name, added_by, recorded_by, source, '
            "share_uid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'manual', ?)",
            [...values, uid],
          );
        } else {
          await _db.customStatement(
            'UPDATE transactions SET account_id = ?, occurred_at = ?, '
            'amount_minor = ?, direction = ?, kind = ?, fee_minor = ?, '
            'currency = ?, category_override_id = ?, item = ?, '
            'counterparty_name = ?, added_by = ?, recorded_by = ? '
            'WHERE id = ?',
            [...values, id],
          );
        }
      case ShareEntity.member || ShareEntity.policy || ShareEntity.approval:
        break;
    }
  }

  /// Marks a transaction typed in on this phone as added by [memberId]
  /// ("Added by Brian, recorded by Jane").
  Future<void> addedFor(int transactionId, String memberId) async {
    final s = await _state();
    await recordLocalChanges();
    final row = await _rowFields(ShareEntity.transaction, transactionId);
    if (row == null) return;
    final (uid, _) = row;
    // The insert this phone logged is replaced by one for them, typed here.
    final log = await this.log();
    final insert = log.latest(ShareEntity.transaction, uid, insertField);
    if (insert == null || insert.hlc.node != s.myMemberId) return;
    await (_db.update(
      _db.shareChanges,
    )..where((r) => r.hlc.equals(insert.id))).write(
      ShareChangesCompanion(
        author: Value(memberId),
        recordedBy: Value(memberId == s.myMemberId ? null : s.myMemberId),
      ),
    );
    await _db.customStatement(
      'UPDATE transactions SET added_by = ?, recorded_by = ? WHERE id = ?',
      [
        memberId,
        if (memberId == s.myMemberId) null else s.myMemberId,
        transactionId,
      ],
    );
    await _db.delete(_db.shareDirty).go();
  }

  // ------------------------------------------------------------- history

  Future<List<HistoryGroup>> history() async {
    await recordLocalChanges();
    final s = await _state();
    final log = await this.log();
    final members = log.members;
    final rows =
        await (_db.select(_db.shareChanges)..orderBy([
              (c) => OrderingTerm(expression: c.seq, mode: OrderingMode.desc),
            ]))
            .get();
    String who(String id) => id == s.myMemberId
        ? 'You'
        : (members[id]?.name.split(' ').first ?? 'Someone');
    final groups = <HistoryGroup>[];
    String keyOf(ShareChangeRow r) {
      final d = r.loggedAt;
      return r.fromFile ?? 'here-${d.year}-${d.month}-${d.day}';
    }

    final byGroup = <String, List<ShareChangeRow>>{};
    for (final r in rows) {
      byGroup.putIfAbsent(keyOf(r), () => []).add(r);
    }
    for (final MapEntry(key: _, value: group) in byGroup.entries) {
      final lines = <HistoryLine>[];
      final inserts = <ShareEntity, List<ShareChangeRow>>{};
      for (final r in group) {
        final c = _fromRow(r);
        if (c.hlc.millis == 0) continue;
        if (c.isInsert && c.entity == ShareEntity.transaction) {
          inserts.putIfAbsent(c.entity, () => []).add(r);
          continue;
        }
        var line = _historyLine(log, c, r, who, s.myMemberId);
        final state = log.stateOf(c.id, _now());
        if (line != null && state != null && state != ApprovalState.approved) {
          final a = log.answer(c.id);
          line = HistoryLine(
            line.title,
            detail: switch (state) {
              ApprovalState.declined => 'Declined by ${who(a!.author)}',
              ApprovalState.lapsed => 'No answer in 30 days, so it lapsed',
              _ => 'Waiting for approval',
            },
          );
        }
        if (line != null) lines.add(line);
      }
      for (final MapEntry(key: _, value: adds) in inserts.entries) {
        final names = [
          for (final r in adds.reversed)
            _label(ShareEntity.transaction, jsonDecode(r.value!) as Map),
        ];
        final by = who(adds.first.author);
        lines.insert(
          0,
          HistoryLine(
            adds.length == 1
                ? '$by added ${names.first}'
                : '$by added ${adds.length} transactions',
            detail: adds.length == 1
                ? null
                : names.length <= 2
                ? names.join(' and ')
                : '${names.take(2).join(', ')} and ${names.length - 2} more',
          ),
        );
      }
      if (lines.isEmpty) continue;
      final first = group.first;
      groups.add(
        HistoryGroup(
          first.loggedAt,
          first.fromFile == null
              ? null
              : (await (_db.select(_db.shareFiles)
                          ..where((f) => f.fileId.equals(first.fromFile!)))
                        .getSingleOrNull())
                    ?.fromMember,
          lines,
        ),
      );
    }
    return groups;
  }

  String _label(ShareEntity e, Map<dynamic, dynamic>? f) {
    if (f == null) return 'a record';
    return switch (e) {
      ShareEntity.transaction =>
        (f['name'] as String?) ?? (f['item'] as String?) ?? 'a transaction',
      ShareEntity.budget => '${f['name']} plan',
      _ => (f['name'] as String?) ?? 'a record',
    };
  }

  HistoryLine? _historyLine(
    ShareLog log,
    ShareChange c,
    ShareChangeRow r,
    String Function(String) who,
    String me,
  ) {
    final by = who(c.author);
    final members = log.members;
    if (c.entity == ShareEntity.policy) {
      return HistoryLine('$by changed who can change what');
    }
    if (c.entity == ShareEntity.approval) {
      final t = log.changes.where((x) => x.id == c.record).firstOrNull;
      final label = t == null
          ? 'a change'
          : '${who(t.hlc.node) == 'You' ? 'your' : "${who(t.hlc.node)}'s"} '
                'change to "${_label(t.entity, log.fields(t.entity, t.record) ?? (t.previous is Map ? t.previous as Map? : null) ?? (t.value is Map ? t.value as Map? : null))}"';
      return HistoryLine(
        '$by ${c.field == approveField ? 'approved' : 'declined'} $label',
      );
    }
    if (c.entity == ShareEntity.member) {
      final name = members[c.record]?.name ?? 'someone';
      if (c.isInsert) {
        if (c.record == c.author) return null;
        final role = ShareRole.byName((c.value! as Map)['role'])?.label;
        return HistoryLine('$by added $name as $role');
      }
      if (c.isRemove) return HistoryLine('$by removed $name');
      if (c.field == 'approver') {
        return HistoryLine(
          c.value == true
              ? '$by let $name approve changes'
              : '$by stopped $name approving changes',
        );
      }
      if (c.field == 'role') {
        return HistoryLine(
          "$by made $name ${ShareRole.byName(c.value)?.label ?? ''}".trim(),
        );
      }
      return null;
    }
    final current = log.fields(c.entity, c.record);
    final label = _label(
      c.entity,
      current ??
          (c.previous is Map ? c.previous as Map? : null) ??
          (c.value is Map ? c.value as Map? : null),
    );
    if (c.isInsert) return HistoryLine('$by added $label');
    if (c.isRemove) {
      final prev = c.previous as Map?;
      final amount = prev?['amount'];
      return HistoryLine(
        '$by removed "$label"${amount is int ? ' (KES ${_money(amount)})' : ''}',
        bringBack: log.exists(c.entity, c.record)
            ? null
            : '${c.entity.name}|${c.record}',
      );
    }
    final String title;
    if (c.field == 'amount') {
      title = c.previous is int
          ? '$by changed $label from ${_money(c.previous! as int)} to '
                '${_money(c.value! as int)}'
          : '$by changed $label to ${_money(c.value! as int)}';
    } else if (c.field == 'category') {
      final category = c.value is String
          ? log.fields(ShareEntity.category, c.value! as String)
          : null;
      final cat = category?['name'];
      title = "$by changed $label's category${cat == null ? '' : ' to $cat'}";
    } else {
      title = "$by changed $label's ${_fieldName(c.field)}";
    }
    if (r.lostTo case final winner?) {
      final w = log.changes.where((x) => x.id == winner).firstOrNull;
      return HistoryLine(
        title,
        detail: w == null
            ? null
            : "Replaced by ${who(w.author) == 'You' ? 'your' : "${who(w.author)}'s"} later change",
      );
    }
    if (r.wonOver case final lost?) {
      final l = log.changes.where((x) => x.id == lost).firstOrNull;
      if (l != null) {
        final lostBy = who(l.author);
        final value = l.value is int ? _money(l.value! as int) : '${l.value}';
        return HistoryLine(
          title,
          detail:
              "Conflict: ${lostBy == 'You' ? 'you' : lostBy} had changed it to $value on "
              '${_weekday(l.hlc.millis)}. ${who(c.author) == 'You' ? 'Yours' : "${who(c.author)}'s"} is later, so it wins.',
          useMine:
              l.author == me &&
                  log.latest(c.entity, c.record, c.field)?.id == c.id
              ? l.id
              : null,
        );
      }
    }
    return HistoryLine(title);
  }

  String _conflictLine(
    ShareLog log,
    ShareConflict c,
    Map<String, ShareMember> members,
    String me,
  ) {
    String name(String id) =>
        id == me ? 'you' : (members[id]?.name.split(' ').first ?? 'someone');
    String cap(String s) => s[0].toUpperCase() + s.substring(1);
    String value(Object? v) => v is int ? _money(v) : '$v';
    final f = log.fields(c.winner.entity, c.winner.record);
    final label = cap(_label(c.winner.entity, f));
    final first = c.loser.hlc.compareTo(c.winner.hlc) < 0 ? c.loser : c.winner;
    final second = identical(first, c.loser) ? c.winner : c.loser;
    final w = name(c.winner.author);
    final l = name(c.loser.author);
    return '$label: ${name(first.author)} set ${value(first.value)} on '
        '${_weekday(first.hlc.millis)}, ${name(second.author)} set '
        '${value(second.value)} on ${_weekday(second.hlc.millis)}. '
        "${w == 'you' ? 'Yours' : "${cap(w)}'s"} is later, so "
        '${value(c.winner.value)} stays. '
        "${l == 'you' ? 'Yours is' : "${cap(l)}'s is"} kept in History.";
  }

  static String _fieldName(String field) => switch (field) {
    'at' => 'date',
    'item' => 'description',
    'name' => 'name',
    'paid' => 'paid mark',
    'account' => 'account',
    _ => field,
  };
}

/// A shared space is full: 6 people in a Household, 30 in a Savings group.
class ShareLimitReached implements Exception {
  const ShareLimitReached();

  @override
  String toString() =>
      'A Household holds up to 6 people, a Savings group up to 30.';
}

const _mon = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _weekday(int millis) =>
    _days[DateTime.fromMillisecondsSinceEpoch(millis).weekday - 1];

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Such as "Sat 21 Nov".
String _dayLabel(int millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}

String _money(int minor) {
  final whole = (minor ~/ 100).abs().toString();
  final out = StringBuffer(minor < 0 ? '-' : '');
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) out.write(',');
    out.write(whole[i]);
  }
  return out.toString();
}

String _slug(String name) {
  final words = name
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9 ]'), '')
      .split(' ')
      .where((w) => w.isNotEmpty && w != 'home' && w != 'at')
      .toList();
  return words.isEmpty ? 'space' : words.join('-');
}

String _uuid() {
  final b = randomBytes(16);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
