import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/sharing/hlc.dart';
import 'package:pesaclarity/src/domain/sharing/share_merge.dart';
import 'package:pesaclarity/src/domain/sharing/share_model.dart';
import 'package:pesaclarity/src/domain/sharing/share_rules.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';

const _day = 86400000;

ShareChange _c(
  int millis,
  String node,
  ShareEntity e,
  String record,
  String field,
  Object? value, {
  String? author,
}) => ShareChange(
  hlc: Hlc(millis, 0, node),
  entity: e,
  record: record,
  field: field,
  value: value,
  author: author ?? node,
);

ShareLog _space(
  SpaceKind kind,
  Map<String, ShareRole> roles, {
  Set<String> approvers = const {},
}) {
  final log = ShareLog('owner', kind);
  var t = 1;
  for (final MapEntry(key: id, value: role) in roles.entries) {
    log.add(
      _c(t++, 'owner', ShareEntity.member, id, insertField, {
        'name': id,
        'role': role.name,
        'approver': approvers.contains(id),
      }),
    );
  }
  // Something the Owner added, and something Jane added.
  log
    ..add(
      _c(10, 'owner', ShareEntity.transaction, 'taxi', insertField, {
        'amount': 60000,
        'name': 'Taxi',
      }),
    )
    ..add(
      _c(11, 'jane', ShareEntity.transaction, 'naivas', insertField, {
        'amount': 234000,
        'name': 'Naivas',
      }),
    );
  return log;
}

ShareChange _yes(
  int millis,
  String by,
  ShareChange target, {
  bool no = false,
}) => _c(
  millis,
  by,
  ShareEntity.approval,
  target.id,
  no ? declineField : approveField,
  const {'sig': 'checked'},
);

void main() {
  const household = {
    'owner': ShareRole.owner,
    'jane': ShareRole.member,
    'brian': ShareRole.member,
  };
  const chama = {
    'owner': ShareRole.owner,
    'mary': ShareRole.treasurer,
    'jane': ShareRole.member,
    'brian': ShareRole.member,
  };

  group('rules', () {
    test('Household defaults: plan and accounts free, others waits', () {
      final p = SharePolicy.defaults(SpaceKind.household);
      expect(p.level(RuleArea.plan), ChangeLevel.anyone);
      expect(p.level(RuleArea.accounts), ChangeLevel.anyone);
      expect(p.level(RuleArea.others), ChangeLevel.approval);
      expect(p.contributions, isFalse);
      expect(ChangeLevel.restricted.label(SpaceKind.household), 'Owner only');
    });

    test('chama defaults: everything waits; contributions off', () {
      final p = SharePolicy.defaults(SpaceKind.savingsGroup);
      for (final a in RuleArea.values) {
        expect(p.level(a), ChangeLevel.approval);
      }
      expect(p.contributions, isFalse);
      expect(
        ChangeLevel.restricted.label(SpaceKind.savingsGroup),
        'Owner and Treasurer only',
      );
    });

    test("editing someone else's transaction waits; your own does not", () {
      final log = _space(SpaceKind.household, household);
      final out = log.merge('jane', [
        _c(20, 'jane', ShareEntity.transaction, 'taxi', removeField, null),
        _c(21, 'jane', ShareEntity.transaction, 'naivas', 'amount', 1),
        _c(22, 'jane', ShareEntity.budget, 'food', insertField, {}),
      ]);
      expect(out.waiting.single.record, 'taxi');
      // Totals keep the old value while it waits.
      expect(log.exists(ShareEntity.transaction, 'taxi'), isTrue);
      expect(log.fields(ShareEntity.transaction, 'naivas')!['amount'], 1);
      expect(log.exists(ShareEntity.budget, 'food'), isTrue);
    });

    test("the Owner's changes never wait; a Treasurer's in a chama do", () {
      final log = _space(SpaceKind.savingsGroup, chama);
      expect(
        log.merge('owner', [
          _c(20, 'owner', ShareEntity.budget, 'b', insertField, {}),
        ]).waiting,
        isEmpty,
      );
      expect(
        log.merge('mary', [
          _c(21, 'mary', ShareEntity.budget, 'b2', insertField, {}),
        ]).waiting,
        hasLength(1),
      );
    });

    test('Owner and Treasurer only: others are refused', () {
      final log = _space(SpaceKind.savingsGroup, chama)
        ..add(
          _c(15, 'owner', ShareEntity.policy, policyRecord, insertField, {
            'plan': 'restricted',
          }),
        );
      expect(
        log.merge('jane', [
          _c(20, 'jane', ShareEntity.budget, 'b', insertField, {}),
        ]).refused,
        hasLength(1),
      );
      final mary = log.merge('mary', [
        _c(21, 'mary', ShareEntity.budget, 'b', insertField, {}),
      ]);
      expect(mary.refused, isEmpty);
      expect(mary.waiting, isEmpty);
    });

    test('rules count from their own clock, and only the Owner sets them', () {
      final log = _space(SpaceKind.household, household);
      expect(
        log.merge('jane', [
          _c(20, 'jane', ShareEntity.policy, policyRecord, 'plan', 'approval'),
        ]).refused,
        hasLength(1),
      );
      log.add(
        _c(30, 'owner', ShareEntity.policy, policyRecord, insertField, {
          'plan': 'approval',
        }),
      );
      final out = log.merge('jane', [
        _c(25, 'jane', ShareEntity.budget, 'early', insertField, {}),
        _c(35, 'jane', ShareEntity.budget, 'late', insertField, {}),
      ]);
      expect([for (final c in out.waiting) c.record], ['late']);
    });

    test('chama contributions wait only when switched on', () {
      final log = _space(SpaceKind.savingsGroup, chama);
      ShareChange money(int t, String id) => _c(
        t,
        'jane',
        ShareEntity.transaction,
        id,
        insertField,
        {'direction': 'inflow', 'amount': 100000},
      );
      expect(log.merge('jane', [money(20, 'c1')]).waiting, isEmpty);
      log.add(
        _c(25, 'owner', ShareEntity.policy, policyRecord, insertField, {
          'contributions': true,
        }),
      );
      expect(log.merge('jane', [money(30, 'c2')]).waiting, hasLength(1));
      expect(log.exists(ShareEntity.transaction, 'c2'), isFalse);
    });
  });

  group('answers', () {
    late ShareLog log;
    late ShareChange delete;
    setUp(() {
      log = _space(SpaceKind.household, household, approvers: {'brian'});
      delete = _c(
        20,
        'jane',
        ShareEntity.transaction,
        'taxi',
        removeField,
        null,
      );
      log.merge('jane', [delete]);
    });

    test("one approver's yes is enough", () {
      final yes = _yes(30, 'brian', delete);
      final out = log.merge('brian', [yes], signed: {yes.id});
      expect(out.decided.single.id, delete.id);
      expect(out.touched, contains('transaction|taxi'));
      expect(log.exists(ShareEntity.transaction, 'taxi'), isFalse);
      expect(log.stateOf(delete.id, 40), ApprovalState.approved);
    });

    test('a decline keeps the old value, and is the answer', () {
      final no = _yes(30, 'owner', delete, no: true);
      log.merge('owner', [no], signed: {no.id});
      expect(log.exists(ShareEntity.transaction, 'taxi'), isTrue);
      expect(log.stateOf(delete.id, 40), ApprovalState.declined);
      expect(log.answer(delete.id)!.author, 'owner');
      // A later yes does not undo it.
      final yes = _yes(31, 'brian', delete);
      log.merge('brian', [yes], signed: {yes.id});
      expect(log.exists(ShareEntity.transaction, 'taxi'), isTrue);
    });

    test('an unanswered change lapses after 30 days', () {
      expect(log.stateOf(delete.id, 20 + 29 * _day), ApprovalState.waiting);
      expect(log.stateOf(delete.id, 21 + 30 * _day), ApprovalState.lapsed);
      final late = _yes(21 + 30 * _day, 'owner', delete);
      expect(
        log.merge('owner', [late], signed: {late.id}).refused,
        hasLength(1),
      );
      expect(log.exists(ShareEntity.transaction, 'taxi'), isTrue);
    });

    test('only an approver, and not the author, can answer', () {
      final log2 = _space(SpaceKind.household, household);
      log2.merge('jane', [delete]);
      final brian = _yes(30, 'brian', delete);
      final jane = _yes(31, 'jane', delete);
      final out = log2.merge(
        'brian',
        [brian, jane],
        signed: {brian.id, jane.id},
      );
      expect(out.refused, hasLength(2));
      expect(log2.stateOf(delete.id, 40), ApprovalState.waiting);
      expect(log2.canApprove('owner'), isTrue);
      expect(log2.canApprove('brian'), isFalse);
      expect(log.canApprove('brian'), isTrue);
    });

    test('an answer whose signature did not check is refused', () {
      final forged = _yes(30, 'owner', delete);
      final out = log.merge('jane', [forged]);
      expect(out.refused.single.id, forged.id);
      expect(log.exists(ShareEntity.transaction, 'taxi'), isTrue);
    });

    test('an answer claiming another approver is refused', () {
      final forged = _c(
        30,
        'jane',
        ShareEntity.approval,
        delete.id,
        approveField,
        const {'sig': 'x'},
        author: 'owner',
      );
      expect(
        log.merge('jane', [forged], signed: {forged.id}).refused,
        hasLength(1),
      );
    });

    test('a log read back gives the same answer', () {
      final yes = _yes(30, 'brian', delete);
      log.merge('brian', [yes], signed: {yes.id});
      final again = ShareLog('owner', SpaceKind.household, log.changes);
      expect(again.exists(ShareEntity.transaction, 'taxi'), isFalse);
    });
  });
}
