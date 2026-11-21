import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/spaces/kept_data.dart';
import 'package:pesaclarity/src/domain/spaces/line_routing.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';

void main() {
  test('kept data survives a save and goes after 30 days', () {
    final kept = KeptData(
      token: 'abc123',
      kind: KeptKind.space,
      space: const Space(
        id: 'g1',
        name: 'Green Basket',
        kind: SpaceKind.business,
      ),
      removedAt: DateTime.utc(2026, 11),
      keyHex: 'k',
    );
    final back = keptFromJson(keptToJson([kept])).single;
    expect(back.space.name, 'Green Basket');
    expect(back.kind, KeptKind.space);
    expect(back.until, DateTime.utc(2026, 12));
    expect(back.expiredAt(DateTime.utc(2026, 11, 30)), isFalse);
    expect(back.expiredAt(DateTime.utc(2026, 12)), isTrue);
    expect(
      keptFromJson({
        'kept': ['junk', <String, Object?>{}],
      }),
      isEmpty,
    );
  });

  test('a deleted space\'s copy keeps the rules that sent money to it', () {
    const rules = RoutingRules(
      sharedLines: {'mpesa': 'g1'},
      people: {'phone:0700***002': 'g1'},
    );
    final kept = KeptData(
      token: 'abc123',
      kind: KeptKind.space,
      space: const Space(
        id: 'g1',
        name: 'Green Basket',
        kind: SpaceKind.business,
      ),
      removedAt: DateTime.utc(2026, 11),
      keyHex: 'k',
    );
    expect(kept.rules, isNull);
    expect(kept.toJson().containsKey('rules'), isFalse);

    final back = keptFromJson(keptToJson([kept.withRules(rules)])).single;
    expect(back.rules!.toJson(), rules.toJson());
    expect((back.token, back.keyHex, back.space.id), ('abc123', 'k', 'g1'));
    // No rules to keep: saved as a copy from before rules were kept.
    expect(
      kept.withRules(const RoutingRules()).toJson().containsKey('rules'),
      isFalse,
    );
    // Saved rules that are not a map are left out; the copy stays.
    final odd = keptFromJson({
      'kept': [
        {...kept.toJson(), 'rules': 'junk'},
      ],
    }).single;
    expect(odd.rules, isNull);
  });

  test('a change of kind says what comes in and what goes', () {
    final change = kindChange(SpaceKind.household, SpaceKind.business);
    expect(change.comesIn, contains('Sell'));
    expect(change.goesAway, contains('Shared bills'));
  });
}
