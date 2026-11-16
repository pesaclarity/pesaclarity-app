import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/not_yet_sorted.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

var _id = 1;

/// Money in from someone not named, from the number [phone].
LedgerEntry _unnamed(
  int amount, {
  String? phone = '0700000000',
  String? name,
  int day = 10,
  String currency = 'KES',
  int? payeeId,
}) => LedgerEntry(
  id: _id++,
  accountId: 1,
  occurredAt: eat(2026, 11, day),
  amountMinor: amount,
  direction: TransactionDirection.inflow,
  kind: TransactionKind.received,
  currency: currency,
  payeeId: payeeId,
  counterpartyName: name,
  counterpartyKind: phone == null ? null : PayeeIdentifierKind.phone,
  counterpartyValue: phone,
);

void main() {
  test('nothing waiting is empty', () {
    final sorted = NotYetSorted.of([
      inflow(at: eat(2026, 11, 3), amount: kes(500), payeeId: 4),
      entry(at: eat(2026, 11, 3), amount: kes(200)),
    ], const []);
    expect(sorted.isEmpty, isTrue);
    expect(sorted.hasAmount, isFalse);
    expect(sorted.parts, isEmpty);
  });

  test('adds money in from people not named, counting each person once', () {
    final sorted = NotYetSorted.of([
      _unnamed(kes(3000), day: 12),
      _unnamed(kes(1000), day: 9),
      _unnamed(kes(400), phone: '0711000000'),
      // Named: sorted already.
      _unnamed(kes(9000), payeeId: 2),
    ], const []);
    expect(sorted.amountMinor, kes(4400));
    expect(sorted.peopleNotNamed, 2);
    expect(sorted.messagesToCheck, 0);
    expect(sorted.firstNotNamed, CalendarDate(2026, 11, 9));
    expect(sorted.parts, ['2 people not named']);
  });

  test('tells people apart by name when the message gave no number', () {
    final sorted = NotYetSorted.of([
      _unnamed(kes(100), phone: null, name: 'Test Wanjiku'),
      _unnamed(kes(100), phone: null, name: 'test wanjiku '),
      _unnamed(kes(100), phone: null, name: 'Test Otieno'),
    ], const []);
    expect(sorted.peopleNotNamed, 2);
    expect(sorted.parts, ['2 people not named']);
  });

  test('adds a message only when its amount was read', () {
    final sorted = NotYetSorted.of(const [], const [
      (amountMinor: 120000, currency: 'KES'),
      (amountMinor: null, currency: null),
      (amountMinor: 50000, currency: null),
    ]);
    expect(sorted.amountMinor, 170000);
    expect(sorted.messagesToCheck, 3);
    expect(sorted.parts, ['3 messages to check']);
  });

  test('unread messages alone have no amount', () {
    final sorted = NotYetSorted.of(const [], const [
      (amountMinor: null, currency: null),
    ]);
    expect(sorted.isEmpty, isFalse);
    expect(sorted.hasAmount, isFalse);
    expect(sorted.parts, ['1 message to check']);
  });

  test('both parts, singular, messages first', () {
    final sorted = NotYetSorted.of(
      [_unnamed(kes(2000))],
      const [(amountMinor: 30000, currency: 'KES')],
    );
    expect(sorted.amountMinor, kes(2300));
    expect(sorted.parts, ['1 message to check', '1 person not named']);
  });

  test('counts money in another currency but adds only the base', () {
    final sorted = NotYetSorted.of(
      [_unnamed(2500, currency: 'USD', phone: '0722000000')],
      const [(amountMinor: 4000, currency: 'USD')],
    );
    expect(sorted.amountMinor, 0);
    expect(sorted.peopleNotNamed, 1);
    expect(sorted.messagesToCheck, 1);
  });
}
