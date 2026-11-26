import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/share/share_codec.dart';
import 'package:pesaclarity/src/domain/sharing/hlc.dart';
import 'package:pesaclarity/src/domain/sharing/safety_words.dart';
import 'package:pesaclarity/src/domain/sharing/share_merge.dart';
import 'package:pesaclarity/src/domain/sharing/share_model.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/sharing/presentation/share_scanner.dart';

ShareChange _c(
  int millis,
  String node,
  ShareEntity e,
  String record,
  String field,
  Object? value, {
  Hlc? base,
  String? author,
}) => ShareChange(
  hlc: Hlc(millis, 0, node),
  entity: e,
  record: record,
  field: field,
  value: value,
  base: base,
  author: author ?? node,
);

ShareLog _space(SpaceKind kind, Map<String, ShareRole> roles) {
  final log = ShareLog('owner', kind);
  var t = 1;
  for (final MapEntry(key: id, value: role) in roles.entries) {
    log.add(
      _c(t++, 'owner', ShareEntity.member, id, insertField, {
        'name': id,
        'role': role.name,
      }),
    );
  }
  return log;
}

void main() {
  group('clock', () {
    test('sorts by time, then counter, then member, as text too', () {
      const a = Hlc(5, 0, 'a');
      final b = a.send(5, 'b');
      expect(b, const Hlc(5, 1, 'b'));
      expect(b > a, isTrue);
      expect(a.toString().compareTo(b.toString()), lessThan(0));
      expect(Hlc.parse(b.toString()), b);
      expect(a.send(9, 'a'), const Hlc(9, 0, 'a'));
      expect(a.receive(const Hlc(7, 3, 'x'), 6, 'a'), const Hlc(7, 4, 'a'));
    });
  });

  group('merge', () {
    final roles = {
      'owner': ShareRole.owner,
      'jane': ShareRole.member,
      'brian': ShareRole.viewer,
    };

    test('two people adding at once both land', () {
      final log = _space(SpaceKind.household, roles)
        ..add(
          _c(10, 'owner', ShareEntity.transaction, 't1', insertField, {
            'amount': 1,
          }),
        );
      final out = log.merge('jane', [
        _c(10, 'jane', ShareEntity.transaction, 't2', insertField, {
          'amount': 2,
        }),
      ]);
      expect(out.added, {'t2'});
      expect(out.conflicts, isEmpty);
      expect(log.exists(ShareEntity.transaction, 't1'), isTrue);
      expect(log.exists(ShareEntity.transaction, 't2'), isTrue);
    });

    test('the same field changed on two phones: the later wins', () {
      final insert = _c(10, 'owner', ShareEntity.budget, 'b', insertField, {
        'amount': 15000,
      });
      final log = _space(SpaceKind.household, roles)
        ..add(insert)
        ..add(
          _c(
            20,
            'owner',
            ShareEntity.budget,
            'b',
            'amount',
            18000,
            base: insert.hlc,
          ),
        );
      final out = log.merge('jane', [
        _c(
          30,
          'jane',
          ShareEntity.budget,
          'b',
          'amount',
          20000,
          base: insert.hlc,
        ),
      ]);
      expect(out.conflicts.single.winner.author, 'jane');
      expect(log.fields(ShareEntity.budget, 'b')!['amount'], 20000);

      // The same two changes the other way round end the same.
      final other = _space(SpaceKind.household, roles)
        ..add(insert)
        ..add(
          _c(
            30,
            'jane',
            ShareEntity.budget,
            'b',
            'amount',
            20000,
            base: insert.hlc,
          ),
        );
      final back = other.merge('owner', [
        _c(
          20,
          'owner',
          ShareEntity.budget,
          'b',
          'amount',
          18000,
          base: insert.hlc,
        ),
      ]);
      expect(back.conflicts.single.winner.author, 'jane');
      expect(other.fields(ShareEntity.budget, 'b')!['amount'], 20000);
    });

    test('a change made on top of another is no conflict', () {
      final insert = _c(10, 'owner', ShareEntity.budget, 'b', insertField, {
        'amount': 1,
      });
      final first = _c(
        20,
        'owner',
        ShareEntity.budget,
        'b',
        'amount',
        2,
        base: insert.hlc,
      );
      final log = _space(SpaceKind.household, roles)
        ..add(insert)
        ..add(first);
      final out = log.merge('jane', [
        _c(30, 'jane', ShareEntity.budget, 'b', 'amount', 3, base: first.hlc),
      ]);
      expect(out.conflicts, isEmpty);
      expect(out.changed, {'b'});
    });

    test("a Viewer's file is refused whole", () {
      final log = _space(SpaceKind.household, roles);
      expect(
        () => log.merge('brian', [
          _c(10, 'brian', ShareEntity.transaction, 't', insertField, {}),
        ]),
        throwsA(isA<ShareRefused>()),
      );
    });

    test('roles and removals come only from the Owner', () {
      final log = _space(SpaceKind.household, roles);
      final out = log.merge('jane', [
        _c(10, 'jane', ShareEntity.member, 'brian', 'role', 'owner'),
        _c(11, 'jane', ShareEntity.member, 'jane', 'name', 'Jane W'),
      ]);
      expect(out.refused.single.field, 'role');
      expect(log.roleOf('brian'), ShareRole.viewer);
      expect(log.members['jane']!.name, 'Jane W');
    });

    test('a change claiming to be by someone else is refused', () {
      final log = _space(SpaceKind.household, roles);
      final out = log.merge('jane', [
        _c(
          10,
          'jane',
          ShareEntity.member,
          'brian',
          'role',
          'owner',
          author: 'owner',
        ),
      ]);
      expect(out.refused, hasLength(1));
    });

    test("in a chama a member's plan change waits for approval", () {
      final log = _space(SpaceKind.savingsGroup, {
        'owner': ShareRole.owner,
        'mary': ShareRole.treasurer,
        'jane': ShareRole.member,
      });
      final out = log.merge('jane', [
        _c(10, 'jane', ShareEntity.budget, 'b', insertField, {}),
        _c(11, 'jane', ShareEntity.transaction, 't', insertField, {}),
      ]);
      expect(out.refused, isEmpty);
      expect(out.waiting.single.entity, ShareEntity.budget);
      expect(log.exists(ShareEntity.budget, 'b'), isFalse);
      expect(log.exists(ShareEntity.transaction, 't'), isTrue);
    });

    test('opening the same changes twice skips them', () {
      final log = _space(SpaceKind.household, roles);
      final c = _c(10, 'jane', ShareEntity.transaction, 't', insertField, {});
      log.merge('jane', [c]);
      expect(log.merge('jane', [c]).skipped, 1);
    });
  });

  test('limits: 6 in a Household, 30 in a chama; others are not shared', () {
    expect(memberLimit(SpaceKind.household), 6);
    expect(memberLimit(SpaceKind.savingsGroup), 30);
    expect(canShare(SpaceKind.business), isFalse);
    expect(
      ShareRole.offeredIn(SpaceKind.household),
      isNot(contains(ShareRole.treasurer)),
    );
    expect(
      ShareRole.offeredIn(SpaceKind.savingsGroup),
      contains(ShareRole.treasurer),
    );
  });

  test('safety words are the same from either side', () {
    final a = List<int>.generate(32, (i) => i);
    final b = List<int>.generate(32, (i) => 100 + i);
    final w = safetyWords(spaceShareId: 's', keyA: a, keyB: b);
    expect(w, hasLength(4));
    expect(safetyWords(spaceShareId: 's', keyA: b, keyB: a), w);
    expect(safetyWords(spaceShareId: 't', keyA: a, keyB: b), isNot(w));
    expect(
      safetyLine(['mango', 'river', 'seven', 'kettle']),
      'mango · river · seven · kettle',
    );
  });

  group('.pcshare', () {
    test('opens for its recipient only, and not once changed', () async {
      final codec = ShareCodec();
      final me = await ShareKeyPair.generate();
      final jane = await ShareKeyPair.generate();
      final brian = await ShareKeyPair.generate();
      final key = codec.newSpaceKey();
      final header = ShareFileHeader(
        space: 's',
        file: 'f',
        from: 'me',
        to: 'jane',
        epoch: 0,
        at: DateTime.utc(2026, 11, 22),
      );
      final bytes = await codec.seal(
        header: header,
        spaceKey: key,
        mySeed: me.seed,
        theirPublic: jane.publicKey,
        payload: const {
          'changes': ['x'],
        },
      );
      final opened = await codec.open(
        bytes,
        keyFor: (_) => key,
        mySeed: jane.seed,
        theirPublic: me.publicKey,
      );
      expect(opened.payload['changes'], ['x']);
      expect(codec.readHeader(bytes).to, 'jane');
      for (final (seed, pub, k) in [
        (brian.seed, me.publicKey, key),
        (jane.seed, brian.publicKey, key),
        (jane.seed, me.publicKey, codec.newSpaceKey()),
      ]) {
        await expectLater(
          codec.open(bytes, keyFor: (_) => k, mySeed: seed, theirPublic: pub),
          throwsA(isA<ShareFileException>()),
        );
      }
      final changed = [...bytes]..[bytes.length - 1] ^= 1;
      await expectLater(
        codec.open(
          changed,
          keyFor: (_) => key,
          mySeed: jane.seed,
          theirPublic: me.publicKey,
        ),
        throwsA(isA<ShareFileException>()),
      );
      final newer = [...bytes]..[7] = 2;
      expect(() => codec.readHeader(newer), throwsA(isA<ShareFileException>()));
    });

    test('a new key travels sealed to its recipient', () async {
      final codec = ShareCodec();
      final me = await ShareKeyPair.generate();
      final jane = await ShareKeyPair.generate();
      final newKey = codec.newSpaceKey();
      final bytes = await codec.seal(
        header: ShareFileHeader(
          space: 's',
          file: 'f',
          from: 'me',
          to: 'jane',
          epoch: 1,
          at: DateTime.utc(2026, 11, 22),
        ),
        spaceKey: newKey,
        mySeed: me.seed,
        theirPublic: jane.publicKey,
        payload: const {},
        carryKey: true,
      );
      final opened = await codec.open(
        bytes,
        keyFor: (_) => null,
        mySeed: jane.seed,
        theirPublic: me.publicKey,
      );
      expect(opened.spaceKey, newKey);
    });

    test('an invite opens only with the key pair that asked for it', () async {
      final codec = ShareCodec();
      final owner = await ShareKeyPair.generate();
      final invitee = await ShareKeyPair.generate();
      final other = await ShareKeyPair.generate();
      final key = codec.newSpaceKey();
      final request = codec.joinRequest(
        name: 'Jane',
        publicKey: invitee.publicKey,
      );
      final (name, theirKey) = codec.openJoinRequest(request);
      expect(name, 'Jane');
      final text = await codec.invite(
        owner: owner,
        inviteePublicKey: theirKey,
        spaceKey: key,
        details: const {'space': 's'},
      );
      final (body, opened) = await codec.openInvite(text, invitee);
      expect(body['space'], 's');
      expect(opened, key);
      await expectLater(
        codec.openInvite(text, other),
        throwsA(isA<ShareFileException>()),
      );
      await expectLater(
        codec.openInvite('${text.substring(0, text.length - 4)}AAAA', invitee),
        throwsA(isA<ShareFileException>()),
      );
    });

    test(
      'a scanned code is read as a file is, and a bad one refused',
      () async {
        final codec = ShareCodec();
        final owner = await ShareKeyPair.generate();
        final invitee = await ShareKeyPair.generate();
        final request = codec.joinRequest(
          name: 'Jane',
          publicKey: invitee.publicKey,
        );
        final invite = await codec.invite(
          owner: owner,
          inviteePublicKey: invitee.publicKey,
          spaceKey: codec.newSpaceKey(),
          details: const {
            'space': 's',
            'name': 'Home',
            'kind': 'household',
            'owner': {'id': 'o'},
            'you': {'id': 'j'},
          },
        );
        // What the camera reads may carry spaces or a line break around it.
        expect(readShareCode(' $request\n'), ShareCodeKind.joinRequest);
        expect(readShareCode(invite), ShareCodeKind.invite);
        expect(scannedProblem(request, ShareCodeKind.joinRequest), isNull);
        expect(scannedProblem(invite, ShareCodeKind.invite), isNull);
        expect(
          scannedProblem(request, ShareCodeKind.invite),
          "That code isn't an invite.",
        );
        final shortKey = base64Url.encode(
          utf8.encode('{"name":"x","key":"AA=="}'),
        );
        for (final bad in [
          'https://example.com',
          '${ShareCodec.joinPrefix}not-base64!',
          '${ShareCodec.joinPrefix}$shortKey',
          'pcshare-invite:1:old',
        ]) {
          expect(() => readShareCode(bad), throwsA(isA<ShareFileException>()));
          expect(scannedProblem(bad, ShareCodeKind.joinRequest), isNotNull);
        }
        expect(scannedProblem(null, ShareCodeKind.invite), isNotNull);
      },
    );
  });
}
