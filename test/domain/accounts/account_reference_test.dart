import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/accounts/account_reference.dart';

void main() {
  AccountReference ref(String printed) => AccountReference.tryParse(printed)!;

  test('reads the digits shown at each end', () {
    final r = ref('0170*****4321');
    expect((r.start, r.end, r.masked), ('0170', '4321', true));
    expect(r.label, '0170…4321');
    expect(r.lastDigits, '4321');
    expect(ref('****0001').label, '…0001');
    expect(AccountReference.tryParse('*****'), isNull);
    expect(AccountReference.tryParse(null), isNull);
  });

  test('the same account, masked two ways', () {
    expect(ref('***4321').sameAs(ref('0170*****4321')), isTrue);
    expect(ref('0170****4321').sameAs(ref('0170****4321')), isTrue);
    expect(ref('01704321').sameAs(ref('0170**4321')), isTrue);
    expect(ref('***4321').showsLessThan(ref('0170*****4321')), isTrue);
  });

  test('two accounts at the same bank', () {
    expect(ref('0170****4321').sameAs(ref('0170****8765')), isFalse);
    expect(ref('0170****4321').sameAs(ref('0299****4321')), isFalse);
    // Nothing shown in common: not the same.
    expect(ref('0170****').sameAs(ref('****4321')), isFalse);
  });
}
