import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/domain/payees/payee_identifier.dart';
import 'package:pesaclarity/src/features/sms/application/transaction_mapping.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../helpers/sms_samples.dart';

ParsedTransaction _parse(SmsMessage message) =>
    SmsParser(loadBundledPacks()).parse(message) as ParsedTransaction;

ParsedTransaction _parsed(
  TransactionType type, {
  String? counterparty,
  String? account,
}) => ParsedTransaction(
  packId: 'test',
  packVersion: '0.1.0',
  ruleId: type.code,
  type: type,
  direction: Direction.outgoing,
  amountMinor: 10000,
  currency: 'KES',
  time: DateTime.utc(2026, 10, 1, 8),
  timeFromMessage: true,
  rawHash: 'hash',
  counterparty: counterparty,
  account: account,
);

void main() {
  test('every parser type has a ledger kind', () {
    expect(
      {for (final t in TransactionType.values) t: transactionKindFor(t)},
      {
        TransactionType.sent: TransactionKind.sent,
        TransactionType.received: TransactionKind.received,
        TransactionType.paybill: TransactionKind.paybill,
        TransactionType.till: TransactionKind.till,
        TransactionType.withdrawal: TransactionKind.withdrawal,
        TransactionType.airtime: TransactionKind.airtime,
        TransactionType.fuliza: TransactionKind.fulizaDraw,
        TransactionType.fulizaRepayment: TransactionKind.fulizaRepayment,
        TransactionType.reversal: TransactionKind.reversal,
        TransactionType.bank: TransactionKind.bank,
      },
    );
  });

  test('maps a sent message to a row with fields, hash and no text', () {
    final parsed = _parse(mpesaSent());
    final row = transactionFromParsed(parsed, accountId: 7);

    expect(row.accountId.value, 7);
    expect(row.occurredAt.value, DateTime.utc(2026, 10, 26, 6, 15));
    expect(row.amountMinor.value, 150000);
    expect(row.direction.value, TransactionDirection.outflow);
    expect(row.kind.value, TransactionKind.sent);
    expect(row.feeMinor.value, 1500);
    expect(row.currency.value, 'KES');
    expect(row.balanceAfterMinor.value, 325000);
    expect(row.receiptNo.value, 'TJA0000001');
    expect(row.source.value, TransactionSource.sms);
    expect(row.messageHash.value, hashMessageBody(mpesaSent().body));
    expect(row.dedupeKey.value, parsed.dedupeKey);
    expect(row.counterpartyName.value, 'JANE DOE');
    expect(row.counterpartyKind.value, PayeeIdentifierKind.phone);
    expect(row.counterpartyValue.value, '0700***001');
    expect(
      row.toColumns(false).values.map((e) => '$e'),
      everyElement(isNot(contains('Confirmed'))),
    );
  });

  test('normalises counterparties so payees apply', () {
    expect(
      counterpartyIdentifier(_parse(mpesaTill())),
      PayeeIdentifier.till('EXAMPLE GROCERS'),
    );
    expect(
      counterpartyIdentifier(
        _parsed(
          TransactionType.paybill,
          counterparty: 'Example Power Ltd',
          account: '12345-67890',
        ),
      ),
      PayeeIdentifier.paybill('EXAMPLE POWER LTD', '1234567890'),
    );
    expect(
      counterpartyIdentifier(
        _parsed(TransactionType.received, account: '254700***002'),
      ),
      PayeeIdentifier.phone('0700***002'),
    );
  });

  test('own accounts and reversed receipts are not counterparties', () {
    expect(
      counterpartyIdentifier(
        _parsed(TransactionType.bank, account: '0000****001'),
      ),
      isNull,
    );
    expect(
      counterpartyIdentifier(
        _parsed(TransactionType.reversal, account: 'TJA0000001'),
      ),
      isNull,
    );
    expect(counterpartyIdentifier(_parsed(TransactionType.received)), isNull);
    expect(counterpartyIdentifier(_parsed(TransactionType.fuliza)), isNull);
  });

  test('a message without a fee stores a zero fee', () {
    final row = transactionFromParsed(
      _parsed(TransactionType.airtime),
      accountId: 1,
    );
    expect(row.feeMinor.value, 0);
    expect(row.kind.value, TransactionKind.airtime);
  });
}
