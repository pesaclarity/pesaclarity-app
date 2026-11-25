import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../config/server_config.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/share_repository.dart';
import '../../../data/sync/group_sync.dart';
import '../../../data/sync/group_sync_client.dart';
import '../../../data/sync/group_sync_store.dart';
import '../../../domain/sharing/share_model.dart';
import '../../spaces/application/spaces_providers.dart';
import 'share_providers.dart';

/// Whether this build shows group sync at all (`--dart-define=GROUP_SYNC=
/// true`). Off by default until licences (0032) and hosting are ready.
final groupSyncFlagProvider = Provider<bool>((ref) => groupSyncEnabled);

/// The owner's Premium licence (decision 0032).
class PremiumLicence {
  const PremiumLicence.none() : active = false, token = null;
  const PremiumLicence.active(String this.token) : active = true;

  final bool active;

  /// What the sync server checks when the owner makes the space.
  final String? token;
}

/// Licences are not issued yet, so nobody has Premium. A test build with
/// sync on can pretend with `--dart-define=GROUP_SYNC_DEV_PREMIUM=true`.
const _devPremium = bool.fromEnvironment('GROUP_SYNC_DEV_PREMIUM');

final premiumLicenceProvider = Provider<PremiumLicence>(
  (ref) => groupSyncEnabled && _devPremium
      ? const PremiumLicence.active('dev')
      : const PremiumLicence.none(),
);

/// The sync server: `GROUP_SYNC_URL`, else the app's own server.
final groupSyncServerProvider = Provider<Uri?>(
  (ref) =>
      parseServerBaseUrl(const String.fromEnvironment('GROUP_SYNC_URL')) ??
      ref.watch(serverBaseUrlProvider),
);

typedef GroupSyncClientFactory = GroupSyncClient Function(
  Uri server,
  String space,
  List<int> seed,
);

final groupSyncClientFactoryProvider = Provider<GroupSyncClientFactory>(
  (ref) =>
      (server, space, seed) =>
          GroupSyncClient(server: server, space: space, seed: seed),
);

/// How long to wait before each new try after a passing problem (no
/// connection, the server busy).
final groupSyncBackoffProvider = Provider<List<Duration>>(
  (ref) => const [
    Duration(seconds: 2),
    Duration(seconds: 8),
    Duration(seconds: 30),
  ],
);

enum GroupSyncPhase {
  /// Not shared, or the build has sync switched off.
  hidden,

  /// The owner has not turned it on.
  off,
  syncing,
  upToDate,
  offline,

  /// A real problem, said in red.
  error,

  /// The owner's Premium ended: changes come in, none go out.
  receivingOnly,

  /// A member whose owner has not added them on the server yet.
  waitingToBeAdded,
}

/// What Share this space shows about sync.
class GroupSyncView {
  const GroupSyncView({
    required this.phase,
    this.owner = false,
    this.ownerName,
    this.lastSyncAt,
    this.toSend = 0,
    this.problem,
  });

  static const hidden = GroupSyncView(phase: GroupSyncPhase.hidden);

  final GroupSyncPhase phase;

  /// Only the owner can turn sync on or off.
  final bool owner;
  final String? ownerName;
  final DateTime? lastSyncAt;

  /// Changes made on this phone that have not gone to everyone.
  final int toSend;
  final String? problem;

  bool get on => switch (phase) {
    GroupSyncPhase.hidden ||
    GroupSyncPhase.off ||
    GroupSyncPhase.waitingToBeAdded => false,
    _ => true,
  };
}

enum TurnOnResult { on, needsPremium, failed }

/// Problems that pass by themselves: tried again with backoff.
bool _passing(Object e) =>
    e is SocketException ||
    e is http.ClientException ||
    e is TimeoutException ||
    (e is GroupSyncException && (e.status >= 500 || e.code == 'rate_limited'));

String _codeOf(Object e) => switch (e) {
  GroupSyncException(:final code) => code,
  SocketException() ||
  http.ClientException() ||
  TimeoutException() => 'offline',
  _ => 'unknown',
};

/// Group sync for the open space: the owner's switch, the status line,
/// and a sync now, kept in the space's encrypted database.
class GroupSyncController extends AsyncNotifier<GroupSyncView> {
  Future<void>? _running;
  bool _syncing = false;

  ShareRepository? get _repo => ref.read(shareRepositoryProvider);
  AppSettingsRepository get _settings =>
      ref.read(appSettingsRepositoryProvider);

  @override
  Future<GroupSyncView> build() async {
    if (!ref.watch(groupSyncFlagProvider)) return GroupSyncView.hidden;
    final repo = ref.watch(shareRepositoryProvider);
    ref.watch(appSettingsRepositoryProvider);
    if (repo == null) return GroupSyncView.hidden;
    return _view();
  }

  Future<GroupSyncView> _view() async {
    final repo = _repo;
    final s = await repo?.state();
    if (repo == null || s == null) return GroupSyncView.hidden;
    final members = await repo.members();
    final me = members[s.myMemberId];
    final owner = me?.role == ShareRole.owner;
    final ownerName = members.values
        .where((m) => m.role == ShareRole.owner)
        .firstOrNull
        ?.name
        .split(' ')
        .first;
    final settings = await GroupSyncSettings.read(_settings);
    final last = settings.lastSyncAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(settings.lastSyncAt!);
    final toSend = await _toSend(repo, s.myMemberId);
    final GroupSyncPhase phase;
    if (_syncing) {
      phase = GroupSyncPhase.syncing;
    } else if (settings.problem == 'not_member' && !owner) {
      phase = GroupSyncPhase.waitingToBeAdded;
    } else if (!settings.on) {
      phase = GroupSyncPhase.off;
    } else if (settings.problem == 'offline' ||
        settings.problem == 'rate_limited') {
      phase = GroupSyncPhase.offline;
    } else if (settings.problem != null) {
      phase = GroupSyncPhase.error;
    } else if (settings.readOnly) {
      phase = GroupSyncPhase.receivingOnly;
    } else {
      phase = GroupSyncPhase.upToDate;
    }
    return GroupSyncView(
      phase: phase,
      owner: owner,
      ownerName: ownerName,
      lastSyncAt: last,
      toSend: toSend,
      problem: settings.problem,
    );
  }

  /// This member's own changes the slowest other member has not had.
  Future<int> _toSend(ShareRepository repo, String myId) async {
    final db = ref.read(appDatabaseProvider);
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM share_changes WHERE author = ? AND '
          'from_file IS NULL AND seq > (SELECT COALESCE(MIN(sent_up_to), 0) '
          'FROM share_peers WHERE member_id != ?)',
          variables: [Variable.withString(myId), Variable.withString(myId)],
        )
        .getSingle();
    return row.read<int>('n');
  }

  Future<void> _refresh() async {
    state = AsyncData(await _view());
  }

  GroupSync? _sync(ShareRepository repo, String spaceId, List<int> seed) {
    final server = ref.read(groupSyncServerProvider);
    if (server == null) return null;
    final client = ref.read(groupSyncClientFactoryProvider)(
      server,
      spaceId,
      seed,
    );
    return GroupSync(repo, client, SettingsSyncCursorStore(_settings));
  }

  /// The owner turns sync on: needs Premium. Members cannot.
  Future<TurnOnResult> turnOn() async {
    final view = await future;
    if (!view.owner) return TurnOnResult.failed;
    final licence = ref.read(premiumLicenceProvider);
    if (!licence.active) return TurnOnResult.needsPremium;
    final repo = _repo!;
    final s = (await repo.state())!;
    final server = ref.read(groupSyncServerProvider);
    if (server == null) return TurnOnResult.failed;
    final client = ref.read(groupSyncClientFactoryProvider)(
      server,
      s.spaceShareId,
      s.seed,
    );
    final settings = await GroupSyncSettings.read(_settings);
    try {
      await client.createSpace(licence.token!);
    } on GroupSyncException catch (e) {
      if (e.licenceProblem) return TurnOnResult.needsPremium;
      if (e.code != 'exists') {
        await settings.copyWith(on: true, problem: e.code).write(_settings);
        await _refresh();
        return TurnOnResult.on;
      }
    } catch (e) {
      // No connection: on, and it starts once online.
      await settings.copyWith(on: true, problem: _codeOf(e)).write(_settings);
      await _refresh();
      return TurnOnResult.on;
    }
    await settings.copyWith(on: true, clearProblem: true).write(_settings);
    await sync();
    return TurnOnResult.on;
  }

  /// The owner turns sync off: the server forgets the space, and every
  /// phone keeps its copy. Members cannot.
  Future<void> turnOff() async {
    final view = await future;
    if (!view.owner) return;
    final repo = _repo!;
    final s = (await repo.state())!;
    final server = ref.read(groupSyncServerProvider);
    if (server != null) {
      try {
        await ref
            .read(groupSyncClientFactoryProvider)(
              server,
              s.spaceShareId,
              s.seed,
            )
            .deleteSpace();
      } catch (_) {
        // Offline: members are refused once the space is gone anyway.
      }
    }
    await SettingsSyncCursorStore(_settings).clear(s.spaceShareId);
    await const GroupSyncSettings().write(_settings);
    await _refresh();
  }

  /// Syncs now (on open, on resume, on pull-to-refresh), trying again with
  /// backoff when the connection or server is briefly away.
  Future<void> sync() {
    return _running ??= _syncNow().whenComplete(() => _running = null);
  }

  Future<void> _syncNow() async {
    await future;
    // Fresh from the database: the switch may have just changed.
    final view = await _view();
    if (view.phase == GroupSyncPhase.hidden) return;
    if (view.owner && !view.on) return;
    final repo = _repo!;
    final s = (await repo.state())!;
    final sync = _sync(repo, s.spaceShareId, s.seed);
    if (sync == null) return;
    _syncing = true;
    await _refresh();
    final delays = ref.read(groupSyncBackoffProvider);
    var settings = await GroupSyncSettings.read(_settings);
    try {
      for (var attempt = 0; ; attempt++) {
        try {
          if (view.owner) await sync.updateMembers();
          final r = await sync.syncOnce(
            spaceName: ref.read(activeSpaceProvider).name,
          );
          settings = settings.copyWith(
            on: true,
            lastSyncAt: ref.read(clockProvider)().millisecondsSinceEpoch,
            clearProblem: true,
            readOnly: r.readOnly,
          );
          if (r.received > 0) ref.invalidate(shareOverviewProvider);
          break;
        } on GroupSyncException catch (e) {
          if (!view.owner && e.code == 'not_found') {
            // The owner has not turned it on, or turned it off.
            await SettingsSyncCursorStore(_settings).clear(s.spaceShareId);
            settings = const GroupSyncSettings();
            break;
          }
          if (!view.owner && e.code == 'not_member') {
            settings = settings.copyWith(on: false, problem: e.code);
            break;
          }
          if (_passing(e) && attempt < delays.length) {
            await Future<void>.delayed(delays[attempt]);
            continue;
          }
          settings = settings.copyWith(problem: e.code);
          break;
        } catch (e) {
          if (_passing(e) && attempt < delays.length) {
            await Future<void>.delayed(delays[attempt]);
            continue;
          }
          settings = settings.copyWith(problem: _codeOf(e));
          break;
        }
      }
      await settings.write(_settings);
    } finally {
      _syncing = false;
      await _refresh();
    }
  }
}

final groupSyncProvider =
    AsyncNotifierProvider<GroupSyncController, GroupSyncView>(
      GroupSyncController.new,
    );
