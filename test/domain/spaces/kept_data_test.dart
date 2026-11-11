import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/spaces/kept_data.dart';
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
        'kept': ['junk', {}],
      }),
      isEmpty,
    );
  });

  test('a change of kind says what comes in and what goes', () {
    final change = kindChange(SpaceKind.household, SpaceKind.business);
    expect(change.comesIn, contains('Sell'));
    expect(change.goesAway, contains('Shared bills'));
  });
}
