import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/payees/payee_directory.dart';
import 'package:pesaclarity/src/domain/payees/payee_identifier.dart';

void main() {
  final grocer = PayeeRule(
    id: 1,
    displayName: 'Test Grocer',
    identifiers: [PayeeIdentifier.till('Test Grocer')!],
    defaultCategoryId: 10,
    leakType: LeakType.lifestyle,
  );
  final friendA = PayeeRule(
    id: 2,
    displayName: 'Friend A',
    identifiers: [PayeeIdentifier.phone('0700000001')!],
    defaultCategoryId: 20,
    leakType: LeakType.friends,
  );
  final friendB = PayeeRule(
    id: 3,
    displayName: 'Friend B',
    identifiers: [PayeeIdentifier.phone('0700999001')!],
  );
  final power = PayeeRule(
    id: 4,
    displayName: 'Power',
    identifiers: [PayeeIdentifier.paybill('Test Power')!],
  );
  final powerHome = PayeeRule(
    id: 5,
    displayName: 'Power at home',
    identifiers: [PayeeIdentifier.paybill('Test Power', '1111')!],
  );
  final directory = PayeeDirectory([
    grocer,
    friendA,
    friendB,
    power,
    powerHome,
  ]);

  group('resolve', () {
    test('finds exact identifiers', () {
      expect(directory.resolve(PayeeIdentifier.till('TEST GROCER')!), grocer);
      expect(
        directory.resolve(PayeeIdentifier.phone('+254700000001')!),
        friendA,
      );
    });

    test('a masked number resolves only when one payee fits', () {
      expect(
        directory.resolve(PayeeIdentifier.phone('0700***001')!),
        isNull,
        reason: 'both friends fit',
      );
      expect(directory.resolve(PayeeIdentifier.phone('0700000***')!), friendA);
      expect(directory.resolve(PayeeIdentifier.phone('0711***001')!), isNull);
    });

    test('a specific paybill account beats the whole business', () {
      expect(
        directory.resolve(PayeeIdentifier.paybill('Test Power', '1111')!),
        powerHome,
      );
      expect(
        directory.resolve(PayeeIdentifier.paybill('Test Power', '2222')!),
        power,
      );
    });
  });

  group('applyPayee', () {
    test('gives every transaction the payee name, category and leak type', () {
      final applied = applyPayee(friendA);
      expect(applied.payeeId, 2);
      expect(applied.displayName, 'Friend A');
      expect(applied.categoryId, 20);
      expect(applied.leakType, LeakType.friends);
      expect(applied.isCategoryOverridden, isFalse);
    });

    test(
      'a category override wins over the payee default, leak type stays',
      () {
        final applied = applyPayee(friendA, categoryOverrideId: 99);
        expect(applied.categoryId, 99);
        expect(applied.isCategoryOverridden, isTrue);
        expect(applied.displayName, 'Friend A');
        expect(applied.leakType, LeakType.friends);
      },
    );

    test('a payee without a category leaves the transaction uncategorised', () {
      expect(applyPayee(friendB).categoryId, isNull);
      expect(applyPayee(friendB).leakType, LeakType.none);
    });

    test('no payee: only the override applies', () {
      expect(applyPayee(null).categoryId, isNull);
      expect(applyPayee(null, categoryOverrideId: 7).categoryId, 7);
      expect(applyPayee(null).leakType, LeakType.none);
    });
  });
}
