import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/statements/statement_dedupe.dart';

DedupeFields _fields({
  int amount = 150000,
  TransactionDirection direction = TransactionDirection.outflow,
  DateTime? at,
  String? receipt,
  String? counterparty,
  String? key,
}) => DedupeFields(
  amountMinor: amount,
  direction: direction,
  occurredAt: at ?? DateTime.utc(2026, 10, 26, 6, 15),
  receipt: receipt,
  counterparty: counterparty,
  dedupeKey: key,
);

void main() {
  test('matches the same dedupe key', () {
    expect(
      matchStatementLines(
        [_fields(key: 'TJA0000001|150000|2026-10-26T06:15Z')],
        [
          LedgerCandidate(
            7,
            _fields(key: 'TJA0000001|150000|2026-10-26T06:15Z'),
          ),
        ],
      ),
      [7],
    );
  });

  test('matches the same receipt and amount at a different time', () {
    expect(
      matchStatementLines(
        [_fields(receipt: 'TJA0000001')],
        [
          LedgerCandidate(
            3,
            _fields(
              receipt: 'tja0000001',
              at: DateTime.utc(2026, 10, 26, 7, 40),
            ),
          ),
        ],
      ),
      [3],
    );
  });

  test('keeps a Fuliza draw that shares its payment receipt', () {
    expect(
      matchStatementLines(
        [
          _fields(receipt: 'TJA0000002', amount: 50000),
          _fields(
            receipt: 'TJA0000002',
            amount: 30000,
            direction: TransactionDirection.inflow,
          ),
        ],
        [LedgerCandidate(1, _fields(receipt: 'TJA0000002', amount: 50000))],
      ),
      [1, null],
    );
  });

  test('matches amount and counterparty within the window', () {
    final sms = LedgerCandidate(
      5,
      _fields(counterparty: 'Jane Doe', at: DateTime.utc(2026, 10, 26, 6, 20)),
    );
    expect(
      matchStatementLines(
        [_fields(receipt: 'TJA0000001', counterparty: 'JANE DOE')],
        [sms],
      ),
      [5],
    );
    expect(
      matchStatementLines(
        [_fields(counterparty: 'JANE DOE', at: DateTime.utc(2026, 10, 26, 7))],
        [sms],
      ),
      [null],
      reason: 'outside the window',
    );
  });

  test('different receipts are different transactions', () {
    expect(
      matchStatementLines(
        [_fields(receipt: 'TJA0000001', counterparty: 'JANE DOE')],
        [
          LedgerCandidate(
            2,
            _fields(receipt: 'TJA0000009', counterparty: 'JANE DOE'),
          ),
        ],
      ),
      [null],
    );
  });

  test('two identical lines need two ledger rows to both match', () {
    final line = _fields(counterparty: 'EXAMPLE GROCERS', amount: 35000);
    expect(matchStatementLines([line, line], [LedgerCandidate(9, line)]), [
      9,
      null,
    ]);
  });
}
