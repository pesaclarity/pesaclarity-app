import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/payees/payee_identifier.dart';

void main() {
  group('phone', () {
    test('normalises the usual Kenyan forms to one value', () {
      for (final raw in [
        '0700 000 001',
        '+254 700 000001',
        '254700000001',
        '700000001',
        '0700-000-001',
      ]) {
        expect(PayeeIdentifier.phone(raw)?.value, '0700000001', reason: raw);
      }
      expect(PayeeIdentifier.phone('0110 000 001')?.value, '0110000001');
    });

    test('keeps masked digits as wildcards', () {
      final masked = PayeeIdentifier.phone('2547xxxxx001')!;
      expect(masked.value, '07*****001');
      expect(masked.isMasked, isTrue);
      expect(PayeeIdentifier.phone('0700***001')!.value, '0700***001');
    });

    test('rejects what is not a mobile number', () {
      expect(PayeeIdentifier.phone('12345'), isNull);
      expect(PayeeIdentifier.phone('0200000001'), isNull);
      expect(PayeeIdentifier.phone('TEST GROCER'), isNull);
    });

    test('masked and full numbers match where the digits agree', () {
      final full = PayeeIdentifier.phone('0700000001')!;
      expect(PayeeIdentifier.phone('0700***001')!.matches(full), isTrue);
      expect(full.matches(PayeeIdentifier.phone('07*****001')!), isTrue);
      expect(PayeeIdentifier.phone('0700***002')!.matches(full), isFalse);
      expect(
        full.matches(
          const PayeeIdentifier.stored(
            PayeeIdentifierKind.account,
            '0700000001',
          ),
        ),
        isFalse,
      );
    });
  });

  test('tills compare by tidied name, exactly', () {
    final a = PayeeIdentifier.till('  Test  Grocer. ')!;
    expect(a.value, 'TEST GROCER');
    expect(a, PayeeIdentifier.till('test grocer'));
    expect(a.matches(PayeeIdentifier.till('TEST GROCERS')!), isFalse);
    expect(PayeeIdentifier.till('  '), isNull);
  });

  group('paybill', () {
    test('combines business and account', () {
      expect(
        PayeeIdentifier.paybill('Test Power', ' 0000-1111 ')!.value,
        'TEST POWER#00001111',
      );
      expect(PayeeIdentifier.paybill('Test Power')!.isWholeBusiness, isTrue);
    });

    test('a whole-business paybill covers every account there', () {
      final whole = PayeeIdentifier.paybill('Test Power')!;
      final one = PayeeIdentifier.paybill('Test Power', '1111')!;
      final other = PayeeIdentifier.paybill('Test Power', '2222')!;
      expect(whole.matches(one), isTrue);
      expect(one.matches(whole), isTrue);
      expect(one.matches(other), isFalse);
      expect(
        whole.matches(PayeeIdentifier.paybill('Test Water', '1111')!),
        isFalse,
      );
    });
  });

  test('bank accounts keep masks and drop separators', () {
    final masked = PayeeIdentifier.account('01-XXXX-0001')!;
    expect(masked.value, '01****0001');
    expect(masked.matches(PayeeIdentifier.account('0100000001')!), isTrue);
  });
}
