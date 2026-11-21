import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/spaces/line_routing.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';

void main() {
  const rules = RoutingRules(
    sharedLines: {'mpesa': 'shop1', 'kcb': 'shop2'},
    people: {
      'phone:0700***002': 'shop1',
      'phone:0700***003': 'shop2',
      'name:mum': personalSpaceId,
    },
  );

  test('a space has its own rules: the lines it shares and its people', () {
    final shop = rules.forSpace('shop1');
    expect(shop.sharedLines, {'mpesa': 'shop1'});
    expect(shop.people, {'phone:0700***002': 'shop1'});
    expect(rules.forSpace('other9').isEmpty, isTrue);
    expect(rules.isEmpty, isFalse);
    expect(const RoutingRules().isEmpty, isTrue);
  });

  test('without a space, the others and Personal keep theirs', () {
    final left = rules.withoutSpace('shop1');
    expect(left.sharedLines, {'kcb': 'shop2'});
    expect(left.people, {
      'phone:0700***003': 'shop2',
      'name:mum': personalSpaceId,
    });
    expect(left.sharedWith('shop1'), isEmpty);
    expect(left.learntFor('shop1'), (business: 0, personal: 1));
  });

  test('only rules for spaces on the list stay; Personal is always on '
      'it', () {
    final left = rules.onlyFor({'shop2'});
    expect(left.sharedLines, {'kcb': 'shop2'});
    expect(left.people, {
      'phone:0700***003': 'shop2',
      'name:mum': personalSpaceId,
    });
    expect(rules.onlyFor({'shop1', 'shop2'}).toJson(), rules.toJson());
    expect(rules.onlyFor(const {}).people, {'name:mum': personalSpaceId});
  });

  test('putting a space\'s rules back keeps what was chosen since', () {
    final now = rules.withoutSpace('shop1');
    expect(now.withPutBack(rules.forSpace('shop1')).toJson(), rules.toJson());

    // The line is shared with another business now, and one of its people
    // was sent to Personal.
    final since = now
        .withLine('mpesa', 'shop2')
        .withPerson('phone:0700***002', personalSpaceId);
    final back = since.withPutBack(
      const RoutingRules(
        sharedLines: {'mpesa': 'shop1'},
        people: {'phone:0700***002': 'shop1', 'phone:0700***004': 'shop1'},
      ),
    );
    expect(back.sharedLines, {'mpesa': 'shop2', 'kcb': 'shop2'});
    expect(back.people['phone:0700***002'], personalSpaceId);
    expect(back.people['phone:0700***004'], 'shop1');
  });
}
