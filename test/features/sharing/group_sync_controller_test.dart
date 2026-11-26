import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/sync/group_sync_client.dart';
import 'package:pesaclarity/src/data/sync/group_sync_store.dart';
import 'package:pesaclarity/src/domain/sharing/share_model.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/sharing/application/group_sync_controller.dart';
import 'package:pesaclarity/src/features/sharing/application/share_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';

import '../../helpers/share_phones.dart';

const _kilimani = Space(
  id: 'kilimani',
  name: 'Home at Kilimani',
  kind: SpaceKind.household,
);

/// A sync server that answers by script, and counts what it was asked.
class ScriptedServer {
  final calls = <String>[];
  bool spaceExists = false;
  bool readOnly = false;

  /// Errors to answer pulls with, in turn, before answering normally.
  final pullErrors = <Object>[];

  /// When set, every call fails with it.
  (int, String)? refuse;

  late final client = MockClient((r) async {
    final what = '${r.method} ${r.url.path.split('/').skip(4).join('/')}';
    calls.add(what);
    if (refuse case (final status, final code)) return _err(status, code);
    if (r.method == 'POST' && what == 'POST ') {
      if (spaceExists) return _err(409, 'exists');
      spaceExists = true;
      return _ok({});
    }
    if (r.method == 'DELETE' && what == 'DELETE ') {
      spaceExists = false;
      return _ok({});
    }
    if (!spaceExists) return _err(404, 'not_found');
    if (r.method == 'PUT') return _ok({'cursor': 0});
    if (r.method == 'POST') {
      return readOnly ? _err(403, 'read_only') : _ok({'cursor': 1});
    }
    if (r.method == 'GET') {
      if (pullErrors.isNotEmpty) throw pullErrors.removeAt(0);
      final since = int.parse(r.url.queryParameters['since']!);
      return _ok({
        'batches': <Object>[],
        'next': since + 5,
        'more': false,
        'readOnly': readOnly,
      });
    }
    return _err(404, 'not_found');
  });

  http.Response _ok(Object body) => http.Response(jsonEncode(body), 200);
  http.Response _err(int status, String code) =>
      http.Response(jsonEncode({'error': code}), status);
}

ProviderContainer _container(
  Phone p,
  ScriptedServer server, {
  bool premium = true,
}) {
  final c = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(p.db),
      shareRepositoryProvider.overrideWithValue(p.repo),
      activeSpaceProvider.overrideWithValue(_kilimani),
      clockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(p.now),
      ),
      groupSyncFlagProvider.overrideWithValue(true),
      premiumLicenceProvider.overrideWithValue(
        premium
            ? const PremiumLicence.active('test')
            : const PremiumLicence.none(),
      ),
      groupSyncServerProvider.overrideWithValue(
        Uri.parse('https://sync.example.test'),
      ),
      groupSyncClientFactoryProvider.overrideWithValue(
        (server0, space, seed) => GroupSyncClient(
          server: server0,
          space: space,
          seed: seed,
          httpClient: server.client,
          nowMillis: () => p.now,
        ),
      ),
      groupSyncBackoffProvider.overrideWithValue(const [
        Duration.zero,
        Duration.zero,
        Duration.zero,
      ]),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<(Phone, Phone)> _space() async {
  final me = Phone('Achieng');
  final jane = Phone('Jane Wairimu');
  await share(me, {jane: ShareRole.member});
  return (me, jane);
}

void main() {
  test('the pull cursor is kept per space in the database', () async {
    final p = Phone('Achieng');
    final store = SettingsSyncCursorStore(DriftAppSettingsRepository(p.db));
    expect(await store.read('a'), 0);
    await store.write('a', 42);
    await store.write('b', 7);
    // A new store on the same database, as after a restart.
    final again = SettingsSyncCursorStore(DriftAppSettingsRepository(p.db));
    expect(await again.read('a'), 42);
    expect(await again.read('b'), 7);
    await again.clear('a');
    expect(await again.read('a'), 0);
  });

  test(
    'a new shared space is off, and does not sync, until turned on',
    () async {
      final (me, _) = await _space();
      final server = ScriptedServer();
      final c = _container(me, server);
      final view = await c.read(groupSyncProvider.future);
      expect(view.phase, GroupSyncPhase.off);
      expect(view.owner, isTrue);
      await c.read(groupSyncProvider.notifier).sync();
      expect(server.calls, isEmpty);
    },
  );

  test('sync is hidden when the build flag is off', () async {
    final (me, _) = await _space();
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(me.db),
        shareRepositoryProvider.overrideWithValue(me.repo),
        groupSyncFlagProvider.overrideWithValue(false),
      ],
    );
    addTearDown(c.dispose);
    expect(
      (await c.read(groupSyncProvider.future)).phase,
      GroupSyncPhase.hidden,
    );
  });

  test('turning on needs Premium', () async {
    final (me, _) = await _space();
    final server = ScriptedServer();
    final c = _container(me, server, premium: false);
    await c.read(groupSyncProvider.future);
    expect(
      await c.read(groupSyncProvider.notifier).turnOn(),
      TurnOnResult.needsPremium,
    );
    expect(server.calls, isEmpty);
    expect((await c.read(groupSyncProvider.future)).phase, GroupSyncPhase.off);
  });

  test(
    'the owner turns it on; it syncs, and the switch and cursor persist',
    () async {
      final (me, _) = await _space();
      final server = ScriptedServer();
      final c = _container(me, server);
      await c.read(groupSyncProvider.future);
      expect(
        await c.read(groupSyncProvider.notifier).turnOn(),
        TurnOnResult.on,
      );
      expect(server.calls.first, 'POST ');
      expect(server.calls, contains('GET batches'));
      final view = await c.read(groupSyncProvider.future);
      expect(view.phase, GroupSyncPhase.upToDate);
      expect(view.lastSyncAt, DateTime.fromMillisecondsSinceEpoch(me.now));

      // After a restart: still on, and the pull carries on from its cursor.
      final again = _container(me, server);
      expect(
        (await again.read(groupSyncProvider.future)).phase,
        GroupSyncPhase.upToDate,
      );
      final s = (await me.repo.state())!;
      final cursors = SettingsSyncCursorStore(
        DriftAppSettingsRepository(me.db),
      );
      expect(await cursors.read(s.spaceShareId), 5);
      await again.read(groupSyncProvider.notifier).sync();
      expect(await cursors.read(s.spaceShareId), 10);

      // Off: the server forgets the space and the cursor starts again.
      await again.read(groupSyncProvider.notifier).turnOff();
      expect(server.spaceExists, isFalse);
      expect(await cursors.read(s.spaceShareId), 0);
      expect(
        (await again.read(groupSyncProvider.future)).phase,
        GroupSyncPhase.off,
      );
    },
  );

  test('only the owner controls sync; a member sees its status', () async {
    final (me, jane) = await _space();
    final server = ScriptedServer();
    final janes = _container(jane, server);
    var view = await janes.read(groupSyncProvider.future);
    expect(view.owner, isFalse);
    expect(view.phase, GroupSyncPhase.off);
    expect(
      await janes.read(groupSyncProvider.notifier).turnOn(),
      TurnOnResult.failed,
    );
    expect(server.spaceExists, isFalse);

    // Before the owner turns it on, the member's sync finds no space.
    await janes.read(groupSyncProvider.notifier).sync();
    expect(
      (await janes.read(groupSyncProvider.future)).phase,
      GroupSyncPhase.off,
    );

    await _container(me, server).read(groupSyncProvider.notifier).turnOn();
    await janes.read(groupSyncProvider.notifier).sync();
    view = await janes.read(groupSyncProvider.future);
    expect(view.phase, GroupSyncPhase.upToDate);
    // A member cannot turn it off for everyone.
    await janes.read(groupSyncProvider.notifier).turnOff();
    expect(server.spaceExists, isTrue);
  });

  test("one way once the owner's Premium ends", () async {
    final (me, jane) = await _space();
    final server = ScriptedServer();
    await _container(me, server).read(groupSyncProvider.notifier).turnOn();
    server.readOnly = true;
    final cash = await jane.account('Cash box');
    await jane.spend(cash, 'Naivas', 2300);
    final janes = _container(jane, server);
    await janes.read(groupSyncProvider.notifier).sync();
    final view = await janes.read(groupSyncProvider.future);
    expect(view.phase, GroupSyncPhase.receivingOnly);
    expect(view.ownerName, 'Achieng');
    expect(view.toSend, greaterThan(0));
    // Pulling still went on.
    expect(server.calls.where((c) => c == 'GET batches'), isNotEmpty);
  });

  test('a lost connection is tried again with backoff', () async {
    final (me, _) = await _space();
    final server = ScriptedServer();
    final c = _container(me, server);
    await c.read(groupSyncProvider.notifier).turnOn();
    server.pullErrors.addAll([
      const SocketException('down'),
      const SocketException('down'),
    ]);
    await c.read(groupSyncProvider.notifier).sync();
    expect(
      (await c.read(groupSyncProvider.future)).phase,
      GroupSyncPhase.upToDate,
    );

    // Still down after every try: waiting, not an error.
    server.pullErrors.addAll(List.filled(4, const SocketException('down')));
    await c.read(groupSyncProvider.notifier).sync();
    expect(
      (await c.read(groupSyncProvider.future)).phase,
      GroupSyncPhase.offline,
    );
  });

  test('a refusal is a problem with its reason, not retried', () async {
    final (me, _) = await _space();
    final server = ScriptedServer();
    final c = _container(me, server);
    await c.read(groupSyncProvider.notifier).turnOn();
    server
      ..calls.clear()
      ..refuse = (401, 'unauthorized');
    await c.read(groupSyncProvider.notifier).sync();
    final view = await c.read(groupSyncProvider.future);
    expect(view.phase, GroupSyncPhase.error);
    expect(view.problem, 'unauthorized');
    expect(server.calls, hasLength(1));
  });
}
