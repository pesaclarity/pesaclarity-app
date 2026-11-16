import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/reader/message_reading.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/review/application/review_draft.dart';

import '../../domain/fixtures.dart';

void main() {
  test('a date read without a time on the day it arrived keeps the time it '
      'arrived, not midnight', () {
    final received = eat(2026, 11, 14, 8, 19);
    final draft = ReviewDraft(
      kind: MessageKind.moneyOut,
      amountMinor: 49007,
      date: CalendarDate(2026, 11, 14),
    );
    expect(draft.occurredAt(received), received.toUtc());
    final older = ReviewDraft(
      kind: MessageKind.moneyOut,
      amountMinor: 49007,
      date: CalendarDate(2026, 11, 12),
    );
    expect(older.occurredAt(received), CalendarDate(2026, 11, 12).startInstant);
  });
}
