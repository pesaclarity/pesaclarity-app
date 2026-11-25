import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pesaclarity/src/core/share/share_codec.dart';
import 'package:pesaclarity/src/data/sync/group_sync.dart';
import 'package:pesaclarity/src/data/sync/group_sync_client.dart';
import 'package:pesaclarity/src/domain/sharing/share_model.dart';

import '../../helpers/share_phones.dart';

String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');

/// The sync server's rules for one space, in memory: signed requests,
/// members, padded batches by cursor, read-only when the licence is out.
class FakeSyncServer {
  final members = <String>{};
  final batches = <Map<String, Object?>>[];
  final nonces = <String>{};
  bool readOnly = false;

  late final client = MockClient(_handle);

  Future<http.Response> _handle(http.Request r) async {
    final key = r.headers['x-pc-key']!;
    final hash = _b64((await Sha256().hash(r.bodyBytes)).bytes);
    final path = r.url.hasQuery ? '${r.url.path}?${r.url.query}' : r.url.path;
    final message = [
      'pcsync v1',
      r.method,
      path,
      r.headers['x-pc-time'],
      r.headers['x-pc-nonce'],
      hash,
    ].join('\n');
    final ok = await ShareSigner.verify(
      base64Url.decode(base64Url.normalize(key)),
      message,
      base64Url.normalize(r.headers['x-pc-sig']!),
    );
    if (!ok || !nonces.add(r.headers['x-pc-nonce']!)) {
      return _err(401, 'unauthorized');
    }
    if (!members.contains(key)) return _err(403, 'not_member');
    if (r.method == 'POST' && r.url.path.endsWith('/batches')) {
      if (readOnly) return _err(403, 'read_only');
      if (!syncSizeSteps.contains(r.bodyBytes.length)) {
        return _err(400, 'not_padded');
      }
      final id = r.headers['x-pc-batch']!;
      final existing = batches.where((b) => b['id'] == id).firstOrNull;
      if (existing != null) {
        return _ok({'cursor': existing['cursor'], 'duplicate': true});
      }
      final cursor = batches.length + 1;
      batches.add({
        'cursor': cursor,
        'id': id,
        'from': key,
        'to': r.headers['x-pc-to'],
        'data': _b64(r.bodyBytes),
      });
      return _ok({'cursor': cursor});
    }
    if (r.method == 'GET' && r.url.path.endsWith('/batches')) {
      final since = int.parse(r.url.queryParameters['since']!);
      final mine = [
        for (final b in batches)
          if ((b['cursor']! as int) > since &&
              b['from'] != key &&
              (b['to'] == null || b['to'] == key))
            b,
      ];
      return _ok({
        'batches': mine,
        'next': batches.isEmpty ? since : batches.length,
        'more': false,
        'readOnly': readOnly,
      });
    }
    return _err(404, 'not_found');
  }

  http.Response _ok(Object body) => http.Response(jsonEncode(body), 200);
  http.Response _err(int status, String code) =>
      http.Response(jsonEncode({'error': code}), status);
}

Future<(GroupSync, GroupSyncClient)> _sync(
  Phone p,
  FakeSyncServer server,
) async {
  final s = (await p.repo.state())!;
  final client = GroupSyncClient(
    server: Uri.parse('https://sync.example.test'),
    space: s.spaceShareId,
    seed: s.seed,
    httpClient: server.client,
    nowMillis: () => p.now,
  );
  server.members.add(await client.myKey());
  return (GroupSync(p.repo, client, MemorySyncCursorStore()), client);
}

void main() {
  test('padding keeps the file and lands on a size step', () {
    final file = List<int>.generate(1500, (i) => i % 251);
    final padded = padForSync(file);
    expect(padded.length, 2048);
    expect(unpadFromSync(padded), file);
    expect(padForSync(const [1]).length, 1024);
    expect(() => padForSync(List.filled(1 << 20, 0)), throwsArgumentError);
  });

  test(
    'two members sync through the server, which sees only sealed files',
    () async {
      final me = Phone('Achieng');
      final jane = Phone('Jane Wairimu');
      await share(me, {jane: ShareRole.member});
      final server = FakeSyncServer();
      final (mine, _) = await _sync(me, server);
      final (janes, _) = await _sync(jane, server);

      final cash = await me.account('Cash box');
      await me.spend(cash, 'KPLC tokens', 1000);
      final first = await mine.syncOnce(spaceName: 'Home at Kilimani');
      expect(first.sent, 1);
      // Nothing new: nothing sent again.
      expect((await mine.syncOnce(spaceName: 'Home at Kilimani')).sent, 0);

      // Only ciphertext reached the server.
      final raw = utf8.decode(
        unpadFromSync(
          base64Url.decode(
            base64Url.normalize(server.batches.single['data']! as String),
          ),
        ),
        allowMalformed: true,
      );
      expect(raw, isNot(contains('KPLC')));

      final got = await janes.syncOnce(spaceName: 'Home at Kilimani');
      expect(got.received, 1);
      expect(await jane.payees(), ['KPLC tokens']);

      jane.now += const Duration(hours: 1).inMilliseconds;
      final janeCash = (await jane.db.select(jane.db.accounts).getSingle()).id;
      await jane.spend(janeCash, 'Naivas', 2340);
      await janes.syncOnce(spaceName: 'Home at Kilimani');
      await mine.syncOnce(spaceName: 'Home at Kilimani');
      expect(await me.payees(), ['KPLC tokens', 'Naivas']);
    },
  );

  test('a read-only space still brings updates in', () async {
    final me = Phone('Achieng');
    final jane = Phone('Jane Wairimu');
    await share(me, {jane: ShareRole.member});
    final server = FakeSyncServer();
    final (mine, _) = await _sync(me, server);
    final (janes, _) = await _sync(jane, server);
    await me.spend(await me.account('Cash box'), 'Rent', 25000);
    await mine.syncOnce(spaceName: 'Home at Kilimani');

    server.readOnly = true;
    jane.now += 1000;
    await jane.spend(await jane.account('Jane cash'), 'Mama Mboga', 450);
    final r = await janes.syncOnce(spaceName: 'Home at Kilimani');
    expect(r.readOnly, isTrue);
    expect(r.sent, 0);
    expect(r.received, 1);
  });

  test('a removed member is refused by the server', () async {
    final me = Phone('Achieng');
    final jane = Phone('Jane Wairimu');
    await share(me, {jane: ShareRole.member});
    final server = FakeSyncServer();
    final (_, janeClient) = await _sync(jane, server);
    server.members.remove(await janeClient.myKey());
    await expectLater(
      janeClient.pull(0),
      throwsA(
        isA<GroupSyncException>().having((e) => e.removed, 'removed', isTrue),
      ),
    );
  });

  test('group sync is off by default', () {
    expect(groupSyncEnabled, isFalse);
  });
}
