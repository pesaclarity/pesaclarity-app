import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/reader/field_values.dart';
import 'package:pesaclarity/src/domain/reader/message_reading.dart';
import 'package:pesaclarity/src/domain/reader/reader_tokens.dart';
import 'package:pesaclarity/src/domain/reader/reading_template.dart';
import 'package:pesaclarity/src/domain/reader/rule_reader.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

// Synthetic messages from invented institutions.
const _debit =
    'Sample Sacco: Your a/c ***1234 debited KES 1,250.00 to EXAMPLE GROCERS '
    'on 29/10/26 14:05. Avl bal KES 8,400.00. Ref SK29XY7AB.';
const _credit =
    'Demo Bank: You have received Ksh.3,400 from JOHN DOE 0712***678 on '
    '28 Oct 2026 at 2:05 PM. Ref 123456789.';

List<double> _onehot(int index, int size, [double p = 0.9]) => [
  for (var i = 0; i < size; i++) i == index ? p : (1 - p) / (size - 1),
];

void main() {
  group('field values', () {
    test('amounts in minor units', () {
      expect(amountMinorFrom('KES 1,250.00'), 125000);
      expect(amountMinorFrom('Ksh.500'), 50000);
      expect(amountMinorFrom('1250.5 Kshs'), 125050);
      expect(amountMinorFrom('KES'), isNull);
    });

    test('dates read day first', () {
      expect(dateFrom('29/10/26'), CalendarDate(2026, 10, 29));
      expect(dateFrom('29-10-2026'), CalendarDate(2026, 10, 29));
      expect(dateFrom('2026-10-29'), CalendarDate(2026, 10, 29));
      expect(dateFrom('28 Oct 2026'), CalendarDate(2026, 10, 28));
      expect(dateFrom('09-NOV-26'), CalendarDate(2026, 11, 9));
      expect(dateFrom('31/02/26'), isNull);
    });

    test('times in minutes after midnight', () {
      expect(minutesFrom('14:05'), 14 * 60 + 5);
      expect(minutesFrom('14:05:33'), 14 * 60 + 5);
      expect(minutesFrom('2:05 PM'), 14 * 60 + 5);
      expect(minutesFrom('12:10 AM'), 10);
      expect(minutesFrom('25:00'), isNull);
    });

    test('payees lose masked numbers and shouting', () {
      expect(counterpartyFrom('JOHN DOE 0712***678'), 'John Doe');
      expect(counterpartyFrom('Example Grocers'), 'Example Grocers');
      expect(
        counterpartyFrom('Till 123456 CORNER CAFE'),
        'Till 123456 Corner Cafe',
      );
    });
  });

  test('decoding keeps the most confident run of each field', () {
    const message = 'Paid KES 50 to DEMO CAFE. Bal KES 10';
    final tokens = tokenise(message);
    // Paid KES 50 to DEMO CAFE . Bal KES 10
    final labels = [0, 1, 1, 0, 2, 2, 0, 0, 5, 5];
    final probs = [
      for (final l in labels) _onehot(l, ReaderField.values.length),
    ];
    final reading = decodeReading(message, tokens, probs, [0.8, 0.1, 0.1]);
    expect(reading.kind, MessageKind.moneyOut);
    expect(reading.fields[ReaderField.amount]!.text, 'KES 50');
    expect(reading.fields[ReaderField.counterparty]!.text, 'DEMO CAFE');
    expect(reading.fields[ReaderField.balance]!.text, 'KES 10');
    expect(reading.fields[ReaderField.amount]!.confidence, closeTo(0.9, 1e-9));
  });

  group('rules reader', () {
    const reader = RuleMessageReader();

    test('reads an account debit', () {
      final r = reader.read(_debit);
      expect(r.kind, MessageKind.moneyOut);
      expect(r.fields[ReaderField.amount]!.text, 'KES 1,250.00');
      expect(r.fields[ReaderField.counterparty]!.text, 'EXAMPLE GROCERS');
      expect(r.fields[ReaderField.date]!.text, '29/10/26');
      expect(r.fields[ReaderField.time]!.text, '14:05');
      expect(r.fields[ReaderField.balance]!.text, 'KES 8,400.00');
      expect(r.fields[ReaderField.reference]!.text, 'SK29XY7AB');
    });

    test('reads money in', () {
      final r = reader.read(_credit);
      expect(r.kind, MessageKind.moneyIn);
      expect(r.fields[ReaderField.amount]!.text, 'Ksh.3,400');
      expect(r.fields[ReaderField.counterparty]!.text, 'JOHN DOE 0712***678');
      expect(r.fields[ReaderField.time]!.text, '2:05 PM');
    });

    test('a code is not a transaction', () {
      final r = reader.read('Your verification code is 482913. Do not share.');
      expect(r.kind, MessageKind.notTransaction);
    });
  });

  group('templates', () {
    ReadingTemplate learnDebit() {
      final reading = const RuleMessageReader().read(_debit);
      final tokens = tokenise(_debit);
      return ReadingTemplate.learn(_debit, reading.kind, {
        for (final f in reading.fields.values)
          f.field: tokenRange(tokens, f.start, f.end)!,
      })!;
    }

    test('read the next message in the same layout', () {
      final template = learnDebit();
      const next =
          'Sample Sacco: Your a/c ***1234 debited KES 75.50 to SUNRISE '
          'BAKERY LTD on 30/10/26 08:15. Avl bal KES 8,324.50. Ref QW12ER34TY.';
      final r = template.read(next)!;
      expect(r.kind, MessageKind.moneyOut);
      expect(r.fields[ReaderField.amount]!.text, 'KES 75.50');
      expect(r.fields[ReaderField.counterparty]!.text, 'SUNRISE BAKERY LTD');
      expect(r.fields[ReaderField.date]!.text, '30/10/26');
      expect(r.fields[ReaderField.reference]!.text, 'QW12ER34TY');
    });

    test('other layouts do not fit', () {
      expect(learnDebit().read(_credit), isNull);
    });

    test('round-trips through JSON', () {
      final template = learnDebit();
      final copy = ReadingTemplate.fromJson(template.toJson());
      expect(copy.parts.length, template.parts.length);
      expect(copy.read(_debit), isNotNull);
    });

    test('needs an amount', () {
      expect(
        ReadingTemplate.learn(_debit, MessageKind.moneyOut, {
          ReaderField.date: (14, 14),
        }),
        isNull,
      );
    });
  });
}
