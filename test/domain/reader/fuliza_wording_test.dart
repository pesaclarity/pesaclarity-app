import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/reader/fuliza_wording.dart';

void main() {
  test('repayment wordings the parser rule misses are still repayments', () {
    for (final body in [
      'TST0000001 Confirmed. Ksh 490.07 from your M-PESA has been used to '
          'fully pay your outstanding Fuliza M-Pesa. Available Fuliza M-Pesa '
          'limit is Ksh 500.00. M-PESA balance is Ksh6,843.73.',
      'TST0000002 Confirmed. Ksh490.07 from your M-PESA has been used to '
          'partially pay your outstanding Fuliza M-PESA amount. M-PESA '
          'balance is Ksh0.00.',
      'Your Fuliza M-PESA of Ksh 490.07 has been repaid. Thank you.',
    ]) {
      expect(fulizaKindIn(body), TransactionKind.fulizaRepayment, reason: body);
    }
  });

  test('a draw is a draw, and other messages are neither', () {
    expect(
      fulizaKindIn(
        'TST0000003 Confirmed. Fuliza M-Pesa amount is Ksh 150.00. Access '
        'Fee charged Ksh 1.50.',
      ),
      TransactionKind.fulizaDraw,
    );
    expect(
      fulizaKindIn('Dear Customer, KES 350.00 has been paid to EXAMPLE CAFE.'),
      isNull,
    );
  });
}
