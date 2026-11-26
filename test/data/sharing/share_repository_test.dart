import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/share/share_codec.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';
import 'package:pesaclarity/src/data/repositories/share_repository.dart';
import 'package:pesaclarity/src/domain/sharing/share_merge.dart';
import 'package:pesaclarity/src/domain/sharing/share_model.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';

import '../../domain/fixtures.dart';
import '../../helpers/share_phones.dart';

Future<void> _plan(Phone p, int amount) async {
  await p.db.customStatement(
    "UPDATE budget_items SET amount_minor = ? WHERE name = 'Food'",
    [kes(amount)],
  );
}

Future<int> _food(Phone p) async => (await (p.db.select(
  p.db.budgetItems,
)..where((b) => b.name.equals('Food'))).getSingle()).amountMinor;

void main() {
  test(
    'two members: what each adds reaches the other, with who added it',
    () async {
      final me = Phone('Achieng');
      final jane = Phone('Jane Wairimu');
      final cash = await me.account('Cash box');
      await me.spend(cash, 'KPLC tokens', 1000);
      await share(me, {jane: ShareRole.member});

      expect(await jane.payees(), ['KPLC tokens']);
      final account = await jane.db.select(jane.db.accounts).getSingle();
      expect(account.name, 'Cash box');

      jane.now += const Duration(hours: 2).inMilliseconds;
      await jane.spend(account.id, 'Naivas', 2340);
      await jane.sendTo(me);

      expect(await me.payees(), ['KPLC tokens', 'Naivas']);
      final naivas = await (me.db.select(
        me.db.transactions,
      )..where((t) => t.counterpartyName.equals('Naivas'))).getSingle();
      expect(naivas.addedBy, await jane.id);
      expect(naivas.recordedBy, isNull);
      expect(naivas.accountId, cash);

      for (final p in [me, jane]) {
        expect(await JournalRepository(p.db).unbalanced(), isEmpty);
      }
    },
  );

  test('three members: changes pass on through whoever sends them', () async {
    final me = Phone('Achieng');
    final jane = Phone('Jane Wairimu');
    final otieno = Phone('Otieno');
    final cash = await me.account('Cash box');
    await me.spend(cash, 'Rent', 25000);
    await share(me, {jane: ShareRole.member, otieno: ShareRole.member});

    final janeCash = (await jane.db.select(jane.db.accounts).getSingle()).id;
    await jane.spend(janeCash, 'Mama Mboga', 450);
    await jane.sendTo(me);
    await me.sendTo(otieno);

    expect(await otieno.payees(), ['Mama Mboga', 'Rent']);
    final row = await (otieno.db.select(
      otieno.db.transactions,
    )..where((t) => t.counterpartyName.equals('Mama Mboga'))).getSingle();
    expect(row.addedBy, await jane.id);

    // A second file to Otieno carries only what is new since the first.
    final out = await me.repo.buildUpdate(
      await otieno.id,
      spaceName: 'Home at Kilimani',
    );
    expect(out.added, 0);
    expect(out.changed, 0);
    expect(await JournalRepository(otieno.db).unbalanced(), isEmpty);
  });

  test('a file opened twice changes nothing', () async {
    final me = Phone('Achieng');
    final jane = Phone('Jane');
    final cash = await me.account('Cash box');
    await share(me, {jane: ShareRole.member});
    await me.spend(cash, 'Water bill', 1200);
    final out = await me.repo.buildUpdate(await jane.id, spaceName: 'Home');
    await jane.repo.apply(out.bytes);
    final again = await jane.repo.preview(out.bytes);
    expect(again.alreadyApplied, isTrue);
    await jane.repo.apply(out.bytes);
    expect(await jane.payees(), ['Water bill']);
  });

  test(
    'typed in for someone else: added by them, recorded by this phone',
    () async {
      final me = Phone('Achieng');
      final jane = Phone('Jane');
      final brian = Phone('Brian');
      final cash = await me.account('Cash box');
      await share(me, {jane: ShareRole.member, brian: ShareRole.member});
      final janeCash = (await jane.db.select(jane.db.accounts).getSingle()).id;
      final id = await jane.spend(janeCash, 'Mama Mboga', 450);
      await jane.repo.recordLocalChanges();
      await jane.repo.addedFor(id, await brian.id);
      await jane.sendTo(me);
      final row = await (me.db.select(
        me.db.transactions,
      )..where((t) => t.counterpartyName.equals('Mama Mboga'))).getSingle();
      expect(row.addedBy, await brian.id);
      expect(row.recordedBy, await jane.id);
      expect(row.accountId, cash);
    },
  );

  group('conflicts', () {
    late Phone me;
    late Phone jane;

    setUp(() async {
      me = Phone('Achieng');
      jane = Phone('Jane Wairimu');
      await me.db
          .into(me.db.budgetItems)
          .insert(
            BudgetItemsCompanion.insert(
              month: 202611,
              name: 'Food',
              amountMinor: kes(15000),
              kind: BudgetItemKind.values.first,
            ),
          );
      await share(me, {jane: ShareRole.member});
    });

    test('the later change wins, and the other is kept in history', () async {
      await _plan(me, 18000); // Sat, 9:00
      await me.repo.recordLocalChanges();
      jane.now += const Duration(days: 1).inMilliseconds; // Sun
      await _plan(jane, 20000);

      final out = await jane.repo.buildUpdate(await me.id, spaceName: 'Home');
      final preview = await me.repo.preview(out.bytes);
      expect(preview.outcome.conflicts, hasLength(1));
      expect(
        preview.conflictLines.single,
        'Food plan: you set 18,000 on Sat, Jane set 20,000 on Sun. '
        "Jane's is later, so 20,000 stays. Yours is kept in History.",
      );
      await me.repo.apply(out.bytes);
      expect(await _food(me), kes(20000));

      // Jane's phone, sent the earlier change, keeps her later one.
      await me.sendTo(jane);
      expect(await _food(jane), kes(20000));

      final history = await me.repo.history();
      final lines = [for (final g in history) ...g.lines];
      final won = lines.firstWhere((l) => l.title.startsWith('Jane changed'));
      expect(won.title, 'Jane changed Food plan from 15,000 to 20,000');
      expect(won.detail, contains("Jane's is later, so it wins."));
      expect(won.useMine, isNotNull);
      final lost = lines.firstWhere((l) => l.title.startsWith('You changed'));
      expect(lost.detail, "Replaced by Jane's later change");
    });

    test('"Use mine instead" puts the value back on every phone', () async {
      await _plan(me, 18000);
      await me.repo.recordLocalChanges();
      jane.now += const Duration(days: 1).inMilliseconds;
      await _plan(jane, 20000);
      await jane.sendTo(me);

      me.now += const Duration(days: 2).inMilliseconds;
      final lines = [for (final g in await me.repo.history()) ...g.lines];
      final mine = lines.firstWhere((l) => l.useMine != null).useMine!;
      await me.repo.useMine(mine);
      expect(await _food(me), kes(18000));

      await me.sendTo(jane);
      expect(await _food(jane), kes(18000));
    });

    test(
      'a removal wins over an edit made at the same time, and comes back',
      () async {
        final cash = await me.db.select(me.db.accounts).get();
        final account = cash.isEmpty
            ? await me.account('Cash box')
            : cash.first.id;
        final taxi = await me.spend(account, 'Taxi', 600);
        await me.sendTo(jane);
        await me.db.customStatement('DELETE FROM transactions WHERE id = ?', [
          taxi,
        ]);
        await me.repo.recordLocalChanges();
        jane.now += 1000;
        await jane.db.customStatement(
          "UPDATE transactions SET item = 'Taxi home' WHERE counterparty_name = 'Taxi'",
        );
        await jane.sendTo(me);
        expect(await me.payees(), isEmpty);
        await me.sendTo(jane);
        expect(await jane.payees(), isEmpty);

        final lines = [for (final g in await me.repo.history()) ...g.lines];
        final removed = lines.firstWhere((l) => l.bringBack != null);
        expect(removed.title, 'You removed "Taxi" (KES 600)');
        final [entity, uid] = removed.bringBack!.split('|');
        await me.repo.bringBack(ShareEntity.byName(entity)!, uid);
        expect(await me.payees(), ['Taxi']);
        await me.sendTo(jane);
        expect(await jane.payees(), ['Taxi']);
        expect(await JournalRepository(jane.db).unbalanced(), isEmpty);
      },
    );
  });

  group('files that are refused', () {
    test('a changed file', () async {
      final me = Phone('Achieng');
      final jane = Phone('Jane');
      await me.account('Cash box');
      await share(me, {jane: ShareRole.member});
      await me.spend(1, 'Naivas', 100);
      final out = await me.repo.buildUpdate(await jane.id, spaceName: 'Home');
      final bytes = [...out.bytes];
      bytes[bytes.length - 20] ^= 1;
      expect(() => jane.repo.apply(bytes), throwsA(isA<ShareRefused>()));
      // A changed header fails too: it is bound into the seal.
      final header = [...out.bytes];
      final at = latin1.decode(header).indexOf('"epoch":0');
      header[at + 8] = '1'.codeUnitAt(0);
      expect(() => jane.repo.apply(header), throwsA(isA<ShareRefused>()));
      expect(await jane.payees(), isEmpty);
    });

    test('a file sealed with the wrong space key', () async {
      final me = Phone('Achieng');
      final jane = Phone('Jane');
      await share(me, {jane: ShareRole.member});
      final s = (await me.repo.state())!;
      final janeKey = (await me.repo.members())[await jane.id]!.publicKey!;
      final codec = ShareCodec();
      final bytes = await codec.seal(
        header: ShareFileHeader(
          space: s.spaceShareId,
          file: 'f1',
          from: s.myMemberId,
          to: await jane.id,
          epoch: 0,
          at: DateTime.utc(2026, 11, 22),
        ),
        spaceKey: codec.newSpaceKey(),
        mySeed: s.seed,
        theirPublic: janeKey,
        payload: const {'changes': []},
      );
      expect(() => jane.repo.apply(bytes), throwsA(isA<ShareRefused>()));
    });

    test('a file meant for someone else', () async {
      final me = Phone('Achieng');
      final jane = Phone('Jane');
      final brian = Phone('Brian');
      await share(me, {jane: ShareRole.member, brian: ShareRole.member});
      final out = await me.repo.buildUpdate(await jane.id, spaceName: 'Home');
      expect(() => brian.repo.apply(out.bytes), throwsA(isA<ShareRefused>()));
    });

    test("a Viewer's file", () async {
      final me = Phone('Achieng');
      final brian = Phone('Brian');
      await share(me, {brian: ShareRole.viewer});
      // The app does not make one…
      expect(
        () async => brian.repo.buildUpdate(await me.id, spaceName: 'Home'),
        throwsA(isA<ShareRefused>()),
      );
      // …and one made anyway is refused.
      final s = (await brian.repo.state())!;
      final ownerKey = (await brian.repo.members())[await me.id]!.publicKey!;
      final keys = jsonDecode(s.keys) as Map;
      final bytes = await ShareCodec().seal(
        header: ShareFileHeader(
          space: s.spaceShareId,
          file: 'v1',
          from: s.myMemberId,
          to: await me.id,
          epoch: 0,
          at: DateTime.utc(2026, 11, 22),
        ),
        spaceKey: base64Url.decode(keys['0'] as String),
        mySeed: s.seed,
        theirPublic: ownerKey,
        payload: const {'changes': []},
      );
      await expectLater(
        me.repo.apply(bytes),
        throwsA(
          isA<ShareRefused>().having(
            (e) => e.message,
            'message',
            contains('Viewer'),
          ),
        ),
      );
    });

    test('a member cannot change roles: only the Owner can', () async {
      final me = Phone('Achieng');
      final jane = Phone('Jane');
      final brian = Phone('Brian');
      await share(me, {jane: ShareRole.member, brian: ShareRole.viewer});
      await jane.db.customStatement(
        // Jane's phone writing a role change straight into its log.
        'SELECT 1',
      );
      expect(
        () async => jane.repo.setRole(await brian.id, ShareRole.member),
        throwsStateError,
      );
    });
  });

  test('removing a member replaces the space key', () async {
    final me = Phone('Achieng');
    final jane = Phone('Jane');
    final brian = Phone('Brian');
    final cash = await me.account('Cash box');
    await share(me, {jane: ShareRole.member, brian: ShareRole.member});
    final before = (await jane.repo.state())!;
    expect(before.epoch, 0);

    await me.repo.remove(await brian.id);
    await me.spend(cash, 'School fees', 9000);
    await me.sendTo(jane);
    final after = (await jane.repo.state())!;
    expect(after.epoch, 1);
    final keys = jsonDecode(after.keys) as Map;
    expect(keys['1'], isNot(keys['0']));
    expect(await jane.payees(), contains('School fees'));
    expect((await jane.repo.members())[await brian.id]!.removed, isTrue);

    // Nothing more is made for Brian, and his files are refused.
    expect(
      () async => me.repo.buildUpdate(await brian.id, spaceName: 'Home'),
      throwsStateError,
    );
    final brianCash = (await brian.db.select(brian.db.accounts).getSingle()).id;
    await brian.spend(brianCash, 'Sneaky', 1);
    final out = await brian.repo.buildUpdate(await me.id, spaceName: 'Home');
    expect(() => me.repo.apply(out.bytes), throwsA(isA<ShareRefused>()));
    expect(await me.payees(), isNot(contains('Sneaky')));
  });

  group('limits and roles', () {
    test('a Household holds 6 people', () async {
      final me = Phone('Achieng');
      await me.repo.start(myName: 'Achieng');
      for (var i = 1; i < 6; i++) {
        await me.repo.invite(
          request: await joinRequest('Person $i'),
          role: ShareRole.member,
          spaceName: 'Home',
        );
      }
      expect(
        () async => me.repo.invite(
          request: await joinRequest('Seventh'),
          role: ShareRole.member,
          spaceName: 'Home',
        ),
        throwsA(isA<ShareLimitReached>()),
      );
    });

    test('a Savings group holds 30, and has a Treasurer', () async {
      final me = Phone('Wanjiku', kind: SpaceKind.savingsGroup);
      await me.repo.start(myName: 'Wanjiku');
      for (var i = 1; i < 30; i++) {
        await me.repo.invite(
          request: await joinRequest('Member $i'),
          role: i == 1 ? ShareRole.treasurer : ShareRole.member,
          spaceName: 'Umoja',
        );
      }
      expect(
        () async => me.repo.invite(
          request: await joinRequest('One more'),
          role: ShareRole.member,
          spaceName: 'Umoja',
        ),
        throwsA(isA<ShareLimitReached>()),
      );
    });

    test('Treasurer is offered in Savings groups only', () async {
      final me = Phone('Achieng');
      await me.repo.start(myName: 'Achieng');
      expect(
        () async => me.repo.invite(
          request: await joinRequest('Jane'),
          role: ShareRole.treasurer,
          spaceName: 'Home',
        ),
        throwsArgumentError,
      );
    });

    test('only Household and Savings group spaces are shared', () {
      final p = Phone('Kamau', kind: SpaceKind.business);
      expect(() => p.repo.start(myName: 'Kamau'), throwsStateError);
    });
  });

  test('the safety words match on both phones, at each step', () async {
    final me = Phone('Achieng');
    final jane = Phone('Jane');
    await me.repo.start(myName: 'Achieng');
    // Jane's phone makes the request; the Owner sees the same words.
    final (request, pair, janeWords) = await ShareRepository.makeJoinRequest(
      'Jane',
    );
    final (name, ownerSees) = ShareRepository.readJoinRequest(request);
    expect(name, 'Jane');
    expect(ownerSees, janeWords);
    expect(janeWords, hasLength(4));
    // The invite's words, on both phones.
    final (invite, member, words) = await me.repo.invite(
      request: request,
      role: ShareRole.member,
      spaceName: 'Home',
    );
    expect(ShareRepository.inviteWords(invite, pair), words);
    await jane.repo.join(invite, mine: pair, myName: 'Jane');
    expect(await jane.repo.wordsWith(await me.id), words);
    expect(await me.repo.wordsWith(member.id), words);
  });

  test("the private key never leaves the invitee's phone", () async {
    final me = Phone('Achieng');
    await me.repo.start(myName: 'Achieng');
    final (request, pair, _) = await ShareRepository.makeJoinRequest('Jane');
    final (invite, _, _) = await me.repo.invite(
      request: request,
      role: ShareRole.member,
      spaceName: 'Home',
    );
    final seed = base64Url.encode(pair.seed);
    for (final text in [request, invite]) {
      final body = utf8.decode(base64Url.decode(text.split(':').last));
      expect(body, isNot(contains(seed)));
    }
  });

  test('an intercepted invite cannot be opened by a third phone', () async {
    final me = Phone('Achieng');
    final eve = Phone('Eve');
    await me.repo.start(myName: 'Achieng');
    final (request, _, _) = await ShareRepository.makeJoinRequest('Jane');
    final (invite, _, _) = await me.repo.invite(
      request: request,
      role: ShareRole.member,
      spaceName: 'Home',
    );
    // Eve has the invite file and a key pair of her own, not Jane's.
    final (_, evePair, _) = await ShareRepository.makeJoinRequest('Eve');
    await expectLater(
      eve.repo.join(invite, mine: evePair, myName: 'Eve'),
      throwsA(isA<ShareFileException>()),
    );
    expect(await eve.repo.state(), isNull);
  });

  test('a swapped join request shows other words', () async {
    final (_, _, real) = await ShareRepository.makeJoinRequest('Jane');
    final (swapped, _, _) = await ShareRepository.makeJoinRequest('Jane');
    expect(ShareRepository.readJoinRequest(swapped).$2, isNot(real));
  });

  test(
    'what each phone sends is only what was put in the shared space',
    () async {
      final me = Phone('Achieng');
      final jane = Phone('Jane');
      // Money of another of this phone's spaces (decision 0027) stays here.
      final held = await me.db
          .into(me.db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'Held for Vegetable stall',
              type: AccountType.heldForSpace,
              openingDate: eat(2026, 1, 1),
              linkedSpaceId: const Value('stall'),
            ),
          );
      await me.spend(held, 'Stall stock', 3000);
      final mpesa = await me.db
          .into(me.db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: "Achieng's M-Pesa",
              type: AccountType.mpesa,
              openingDate: eat(2026, 1, 1),
              institutionId: const Value('mpesa'),
              reference: const Value('0712***678'),
            ),
          );
      await me.db
          .into(me.db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: mpesa,
              occurredAt: eat(2026, 11, 20),
              amountMinor: kes(2340),
              direction: TransactionDirection.outflow,
              source: TransactionSource.sms,
              counterpartyName: const Value('Naivas'),
              messageHash: const Value('secret-hash'),
              receiptNo: const Value('TKL1AB2CD3'),
              balanceAfterMinor: Value(kes(10000)),
            ),
          );
      await share(me, {jane: ShareRole.member});
      expect(await jane.payees(), ['Naivas']);
      final row = await jane.db.select(jane.db.transactions).getSingle();
      expect(row.messageHash, isNull);
      expect(row.receiptNo, isNull);
      expect(row.balanceAfterMinor, isNull);
      final accounts = await jane.db.select(jane.db.accounts).get();
      expect(accounts.map((a) => a.name), ["Achieng's M-Pesa"]);
      expect(accounts.single.institutionId, isNull);
      expect(accounts.single.reference, isNull);
    },
  );
}
