import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/activity_lines.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

void main() {
  test('collapses each noise kind to one line per day', () {
    final lines = collapseNoise([
      inflow(
        kind: TransactionKind.fulizaDraw,
        at: eat(2026, 10, 5, 8),
        amount: kes(200),
      ),
      inflow(
        kind: TransactionKind.fulizaDraw,
        at: eat(2026, 10, 5, 13),
        amount: kes(150),
      ),
      entry(
        kind: TransactionKind.fulizaRepayment,
        at: eat(2026, 10, 5, 18),
        amount: kes(355),
      ),
      entry(
        kind: TransactionKind.airtime,
        at: eat(2026, 10, 5, 9),
        amount: kes(50),
      ),
      entry(
        kind: TransactionKind.airtime,
        at: eat(2026, 10, 5, 19),
        amount: kes(20),
      ),
      entry(
        kind: TransactionKind.roundUp,
        at: eat(2026, 10, 5, 10),
        amount: kes(3),
      ),
      entry(
        kind: TransactionKind.charge,
        at: eat(2026, 10, 5, 11),
        amount: kes(30),
      ),
    ]);

    final noise = lines.whereType<DailyNoiseLine>().toList();
    expect(noise.map((l) => l.group).toSet(), NoiseGroup.values.toSet());
    final draws = noise.singleWhere((l) => l.group == NoiseGroup.fulizaDraws);
    expect(draws.count, 2);
    expect(draws.totalMinor, kes(350));
    expect(draws.date, CalendarDate(2026, 10, 5));
    expect(draws.direction, TransactionDirection.inflow);
    final airtime = noise.singleWhere((l) => l.group == NoiseGroup.airtime);
    expect(airtime.totalMinor, kes(70));
  });

  test('splits days at midnight in Nairobi, not UTC', () {
    final lines = collapseNoise([
      entry(
        kind: TransactionKind.charge,
        at: DateTime.utc(2026, 10, 5, 20, 30),
        amount: 100,
      ),
      entry(
        kind: TransactionKind.charge,
        at: DateTime.utc(2026, 10, 5, 21, 30),
        amount: 100,
      ),
    ]);
    expect(lines.cast<DailyNoiseLine>().map((l) => l.date), [
      CalendarDate(2026, 10, 6),
      CalendarDate(2026, 10, 5),
    ]);
  });

  test('keeps accounts and directions apart', () {
    final lines = collapseNoise([
      entry(kind: TransactionKind.charge, at: eat(2026, 10, 5, 9), amount: 100),
      entry(
        kind: TransactionKind.charge,
        at: eat(2026, 10, 5, 10),
        amount: 100,
        accountId: 2,
      ),
      inflow(
        kind: TransactionKind.charge,
        at: eat(2026, 10, 5, 11),
        amount: 100,
      ),
    ]);
    expect(lines, hasLength(3));
  });

  test('shows other entries on their own, newest first', () {
    final till = entry(id: 1, at: eat(2026, 10, 5, 13), amount: kes(400));
    final early = entry(
      id: 2,
      kind: TransactionKind.airtime,
      at: eat(2026, 10, 5, 9),
      amount: kes(50),
    );
    final late = entry(
      id: 3,
      kind: TransactionKind.airtime,
      at: eat(2026, 10, 5, 15),
      amount: kes(20),
    );
    final sent = entry(
      id: 4,
      kind: TransactionKind.sent,
      at: eat(2026, 10, 4, 15),
      amount: kes(1000),
    );

    final lines = collapseNoise([sent, early, till, late]);

    expect(lines, hasLength(3));
    final group = lines[0] as DailyNoiseLine;
    expect(group.occurredAt, late.occurredAt);
    expect(group.entries.map((e) => e.id), [3, 2]);
    expect((lines[1] as EntryLine).entry, till);
    expect((lines[2] as EntryLine).entry, sent);
    expect(() => group.entries.add(till), throwsUnsupportedError);
  });

  test('handles an empty ledger', () {
    expect(collapseNoise([]), isEmpty);
  });
}
