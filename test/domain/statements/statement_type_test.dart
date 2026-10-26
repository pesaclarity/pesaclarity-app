import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/statements/statement_type.dart';

import '../../helpers/statement_samples.dart';

void main() {
  test('recognises an M-Pesa statement', () {
    expect(
      detectStatementType(mpesaStatementText()),
      isA<MpesaStatementType>(),
    );
  });

  test('recognises M-Pesa by its columns when the title is missing', () {
    final text = mpesaStatementText().replaceFirst('M-PESA STATEMENT', '');
    expect(detectStatementType(text), isA<MpesaStatementType>());
  });

  test('names the bank of a bank statement', () {
    final type = detectStatementType(kcbStatementText);
    expect(type, isA<BankStatementType>());
    expect((type as BankStatementType).bankName, 'KCB');
  });

  test('bank names in M-Pesa details do not make it a bank statement', () {
    final text = mpesaStatementText(
      rows: [
        (
          receipt: 'TJA0000009',
          time: '2026-10-02 10:00:00',
          details: 'Pay Bill Online to 522522 - KCB Acc. 0000000001',
          amount: -10000,
        ),
      ],
    );
    expect(detectStatementType(text), isA<MpesaStatementType>());
  });

  test('anything else is unknown', () {
    expect(
      detectStatementType('Invoice 001\nTotal due 1,000.00'),
      isA<UnknownStatementType>(),
    );
  });
}
