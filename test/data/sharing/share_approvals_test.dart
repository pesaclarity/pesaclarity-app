import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/domain/sharing/hlc.dart';
import 'package:pesaclarity/src/domain/sharing/share_merge.dart';
import 'package:pesaclarity/src/domain/sharing/share_model.dart';
import 'package:pesaclarity/src/domain/sharing/share_rules.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';

import '../../helpers/share_phones.dart';

/// Wanjiku (Owner), Jane and Brian (Members), with Wanjiku's taxi on every
/// phone and Jane asking to delete it.
Future<(Phone, Phone, Phone)> _janeDeletesTaxi() async {
  final me = Phone('Wanjiku');
  final jane = Phone('Jane Wairimu');
  final brian = Phone('Brian');
  final cash = await me.account('Cash box');
  await share(me, {jane: ShareRole.member, brian: ShareRole.member});
  await me.spend(cash, 'Taxi', 600);
  await me.sendTo(jane);
  await me.sendTo(brian);
  await jane.db.customStatement(
    "DELETE FROM transactions WHERE counterparty_name = 'Taxi'",
  );
  await jane.repo.recordLocalChanges();
  return (me, jane, brian);
}

void main() {
  test(
    'a change that waits: totals keep the old value on every phone',
    () async {
      final (me, jane, _) = await _janeDeletesTaxi();
      // Back on Jane's own phone until an approver says yes.
      expect(await jane.payees(), contains('Taxi'));
      expect(
        (await jane.repo.mine()).single.mineLine,
        'you asked to delete it · Waiting for approval',
      );
      final out = await jane.repo.buildUpdate(await me.id, spaceName: 'Home');
      await jane.repo.markSent(out);
      final preview = await me.repo.preview(out.bytes);
      expect(preview.outcome.waiting, hasLength(1));
      final applied = await me.repo.apply(out.bytes);
      expect(applied.waiting, hasLength(1));
      expect(await me.payees(), contains('Taxi'));
      final asks = await me.repo.toApprove();
      expect(asks.single.title, 'Jane wants to delete "Taxi" (KES 600)');
      expect(asks.single.detail, startsWith('Added by you'));
      expect(asks.single.fromMember, await jane.id);

      await me.repo.answer(asks.single.id, yes: true);
      expect(await me.payees(), isNot(contains('Taxi')));
      expect(await me.repo.toApprove(), isEmpty);
      await me.sendTo(jane);
      expect(await jane.payees(), isNot(contains('Taxi')));
      expect((await jane.repo.mine()).single.state, ApprovalState.approved);
    },
  );

  test(
    'a declined change stays out, shows on the row and in History',
    () async {
      final (me, jane, _) = await _janeDeletesTaxi();
      await jane.sendTo(me);
      await me.repo.answer((await me.repo.toApprove()).single.id, yes: false);
      await me.sendTo(jane);
      expect(await jane.payees(), contains('Taxi'));
      expect((await jane.repo.mine()).single.mineLine, 'Declined by Wanjiku');
      final lines = [for (final g in await me.repo.history()) ...g.lines];
      expect(lines.where((l) => l.detail == 'Declined by You'), hasLength(1));
      expect(
        lines.map((l) => l.title),
        contains('You declined Jane\'s change to "Taxi"'),
      );
    },
  );

  test('an unanswered change lapses after 30 days', () async {
    final (me, jane, _) = await _janeDeletesTaxi();
    await jane.sendTo(me);
    final id = (await me.repo.toApprove()).single.id;
    me.now += const Duration(days: 31).inMilliseconds;
    expect(await me.repo.toApprove(), isEmpty);
    await expectLater(me.repo.answer(id, yes: true), throwsStateError);
    expect(await me.payees(), contains('Taxi'));
  });

  test('only an approver can answer; the Owner chooses who', () async {
    final (me, jane, brian) = await _janeDeletesTaxi();
    await jane.sendTo(brian);
    await jane.sendTo(me);
    expect(await brian.repo.toApprove(), isEmpty);
    expect(
      brian.repo.setApprover(await jane.id, approver: true),
      throwsStateError,
    );
    await me.repo.setApprover(await brian.id, approver: true);
    await me.sendTo(brian);
    final asks = await brian.repo.toApprove();
    expect(asks, hasLength(1));
    await brian.repo.answer(asks.single.id, yes: true);
    expect(await brian.payees(), isNot(contains('Taxi')));
    // Brian's signed yes counts on the Owner's phone too.
    await brian.sendTo(me);
    expect(await me.payees(), isNot(contains('Taxi')));
  });

  test(
    "a forged approval is refused: it isn't signed by the approver",
    () async {
      final (me, jane, brian) = await _janeDeletesTaxi();
      await jane.sendTo(brian);
      final target = (await jane.repo.mine()).single.id;
      // Jane writes a yes in the Owner's name into her own log.
      await jane.db
          .into(jane.db.shareChanges)
          .insert(
            ShareChangesCompanion.insert(
              hlc: Hlc(jane.now + 1000, 0, await me.id).toString(),
              entity: ShareEntity.approval.name,
              record: target,
              field: approveField,
              value: Value(
                jsonEncode({'sig': base64Url.encode(List.filled(64, 7))}),
              ),
              author: await me.id,
              loggedAt: DateTime.now(),
            ),
          );
      final out = await jane.repo.buildUpdate(
        await brian.id,
        spaceName: 'Home',
      );
      final applied = await brian.repo.apply(out.bytes);
      expect(applied.refused, hasLength(1));
      expect(await brian.payees(), contains('Taxi'));
    },
  );

  test('rules are the Owner\'s, and travel to the others', () async {
    final me = Phone('Wanjiku', kind: SpaceKind.savingsGroup);
    final mary = Phone('Mary', kind: SpaceKind.savingsGroup);
    await share(me, {mary: ShareRole.treasurer});
    expect(
      (await mary.repo.policy()).level(RuleArea.plan),
      ChangeLevel.approval,
    );
    await expectLater(
      mary.repo.setPolicy(SharePolicy.defaults(SpaceKind.savingsGroup)),
      throwsStateError,
    );
    final p = SharePolicy.defaults(SpaceKind.savingsGroup);
    await me.repo.setPolicy(
      SharePolicy(p.kind, {
        ...p.levels,
        RuleArea.plan: ChangeLevel.restricted,
      }, contributions: true),
    );
    await me.sendTo(mary);
    final got = await mary.repo.policy();
    expect(got.level(RuleArea.plan), ChangeLevel.restricted);
    expect(got.contributions, isTrue);
  });
}
