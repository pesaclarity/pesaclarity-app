import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/payees/payee_identifier.dart';
import 'package:pesaclarity/src/domain/savings/savings_product.dart';

// The paybill's name is public; the account codes are made up.

SavingsMove? _paid(
  String name, {
  String? account = 'CH12345',
  TransactionKind kind = TransactionKind.paybill,
  TransactionDirection direction = TransactionDirection.outflow,
  bool printsName = true,
}) {
  final paybill = PayeeIdentifier.paybill(name, account);
  return savingsMoveOf(
    kind: kind,
    direction: direction,
    counterpartyKind: paybill?.kind,
    counterpartyValue: paybill?.value,
    counterpartyName: printsName ? name : null,
  );
}

SavingsMove? _received(String? from) => savingsMoveOf(
  kind: TransactionKind.received,
  direction: TransactionDirection.inflow,
  counterpartyName: from,
);

void main() {
  group('savingsPayeeKey', () {
    test('reads a name whatever its case, spacing, dots or channel', () {
      for (final printed in [
        'NABO CAPITAL LTD C2B',
        'Nabo Capital Ltd C2B',
        'nabo  capital   ltd',
        ' NABO CAPITAL LTD. ',
        'NABO CAPITAL LTD C2B.',
        'NABO CAPITAL LTD. B2C',
        'Nabo Capital Ltd B2B',
      ]) {
        expect(savingsPayeeKey(printed), 'NABO CAPITAL LTD', reason: printed);
      }
    });

    test('keeps a name that is only a channel word, and empty text', () {
      expect(savingsPayeeKey('C2B'), 'C2B');
      expect(savingsPayeeKey('  '), '');
      // A channel word inside a name is part of the name.
      expect(savingsPayeeKey('C2B TRADERS LTD'), 'C2B TRADERS LTD');
    });
  });

  group('the registry', () {
    test('knows Chumz by its paybill, as a savings account', () {
      expect(savingsProducts, contains(chumz));
      expect(savingsProductById('chumz'), same(chumz));
      expect(savingsProductById('mshwari'), isNull);
      expect(savingsProductById(null), isNull);
      expect(chumz.name, 'Chumz');
      expect(chumz.provider, 'Nabo Capital');
      expect(chumz.paidThrough, 'M-Pesa paybill NABO CAPITAL LTD');
      expect(chumz.type, AccountType.moneyMarket);
      expect(chumz.currency, 'KES');
    });

    test('a name fits when it is the product name or starts with it', () {
      for (final printed in [
        'NABO CAPITAL',
        'NABO CAPITAL LTD',
        'Nabo Capital Limited C2B',
      ]) {
        expect(chumz.takesPayIn(printed), isTrue, reason: printed);
        expect(chumz.paysBack(printed), isTrue, reason: printed);
      }
      for (final printed in [
        'NABO',
        'NABO CAPITALS LTD',
        'NABOCAPITAL LTD',
        'THE NABO CAPITAL LTD',
        'EXAMPLE POWER LTD',
        '',
      ]) {
        expect(chumz.takesPayIn(printed), isFalse, reason: printed);
        expect(chumz.paysBack(printed), isFalse, reason: printed);
      }
      expect(chumz.takesPayIn(null), isFalse);
    });

    test('money back can go by other names than paying in', () {
      const fund = SavingsProduct(
        id: 'example',
        name: 'Example fund',
        provider: 'Example Asset Managers',
        payeeNames: ['EXAMPLE FUND'],
        moneyBackNames: ['EXAMPLE PAYOUTS'],
        paidThrough: 'M-Pesa paybill EXAMPLE FUND',
      );
      expect(fund.takesPayIn('EXAMPLE FUND LTD'), isTrue);
      expect(fund.paysBack('EXAMPLE FUND LTD'), isFalse);
      expect(fund.paysBack('Example Payouts B2C'), isTrue);
      expect(fund.takesPayIn('Example Payouts B2C'), isFalse);
    });
  });

  group('savingsMoveOf', () {
    test('paying the paybill is paying in, under the code after the #', () {
      final move = _paid('NABO CAPITAL LTD C2B');
      expect(move, isA<SavingsPayIn>());
      expect(move!.product, same(chumz));
      expect((move as SavingsPayIn).code, 'CH12345');

      // The code is kept as the parsers normalise it.
      expect(
        (_paid('Nabo Capital Ltd', account: 'ch-67890') as SavingsPayIn).code,
        'CH67890',
      );
      // A payment that names no account has no code.
      expect(
        (_paid('NABO CAPITAL LTD', account: null) as SavingsPayIn).code,
        '',
      );
    });

    test('the paybill alone is enough when no name was printed', () {
      final move = _paid('NABO CAPITAL LTD C2B', printsName: false);
      expect(move, isA<SavingsPayIn>());
      expect((move! as SavingsPayIn).code, 'CH12345');
    });

    test('money received from the provider is money back', () {
      expect(_received('NABO CAPITAL LTD'), isA<SavingsMoneyBack>());
      expect(_received('Nabo Capital Ltd B2C'), isA<SavingsMoneyBack>());
      expect(_received('NABO CAPITAL LTD')!.product, same(chumz));
    });

    test('anything else has nothing to do with a savings product', () {
      // Another paybill, a similar name, and a name that only contains it.
      expect(_paid('EXAMPLE POWER LTD'), isNull);
      expect(_paid('NABO CAPITALS LTD'), isNull);
      expect(_paid('FRIENDS OF NABO CAPITAL'), isNull);
      // The right name the wrong way round, or as another kind of payment.
      expect(
        _paid('NABO CAPITAL LTD', direction: TransactionDirection.inflow),
        isNull,
      );
      expect(_paid('NABO CAPITAL LTD', kind: TransactionKind.till), isNull);
      expect(_paid('NABO CAPITAL LTD', kind: TransactionKind.sent), isNull);
      expect(_received('JANE DOE'), isNull);
      expect(_received(null), isNull);
      expect(
        savingsMoveOf(
          kind: TransactionKind.received,
          direction: TransactionDirection.outflow,
          counterpartyName: 'NABO CAPITAL LTD',
        ),
        isNull,
      );
      // Typed by hand: no kind, so never read as a paybill payment.
      expect(
        savingsMoveOf(
          kind: null,
          direction: TransactionDirection.outflow,
          counterpartyName: 'NABO CAPITAL LTD',
        ),
        isNull,
      );
    });

    test('only the products given are looked for', () {
      expect(
        savingsMoveOf(
          kind: TransactionKind.received,
          direction: TransactionDirection.inflow,
          counterpartyName: 'NABO CAPITAL LTD',
          products: const [],
        ),
        isNull,
      );
    });
  });
}
