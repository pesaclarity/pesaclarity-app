import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/activity_feed.dart';
import 'package:pesaclarity/src/domain/ledger/activity_lines.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

const mpesa = 1;
const bank = 2;

/// Monday 26 October 2026.
final today = CalendarDate(2026, 10, 26);

void main() {
  final groceries = entry(
    id: 1,
    at: eat(2026, 10, 26, 9),
    amount: kes(1440),
    categoryType: CategoryType.expense,
    isDailySpending: true,
  );
  final named = LedgerEntry(
    id: 2,
    accountId: mpesa,
    occurredAt: eat(2026, 10, 25, 18),
    amountMinor: kes(500),
    direction: TransactionDirection.outflow,
    kind: TransactionKind.paybill,
    payeeName: 'KPLC tokens',
    note: 'Prepaid meter',
  );
  final salary = inflow(
    id: 3,
    at: eat(2026, 10, 26, 8),
    amount: kes(2500),
    kind: TransactionKind.bank,
    accountId: bank,
    categoryType: CategoryType.income,
  );
  final transferOut = entry(
    id: 4,
    at: eat(2026, 10, 26, 10),
    amount: kes(2000),
    kind: TransactionKind.bank,
    accountId: bank,
    transferPairId: 5,
  );
  final transferIn = LedgerEntry(
    id: 5,
    accountId: mpesa,
    occurredAt: eat(2026, 10, 26, 10, 1),
    amountMinor: kes(2000),
    direction: TransactionDirection.inflow,
    kind: TransactionKind.received,
    transferPairId: 4,
  );
  final unknown = LedgerEntry(
    id: 6,
    accountId: mpesa,
    occurredAt: eat(2026, 10, 25),
    amountMinor: kes(350),
    direction: TransactionDirection.outflow,
    kind: TransactionKind.sent,
    counterpartyKind: PayeeIdentifierKind.phone,
    counterpartyValue: '0700***000',
  );
  final all = [groceries, named, salary, transferOut, transferIn, unknown];

  group('ActivityType', () {
    List<int> idsOf(ActivityType type) => [
      for (final e in all)
        if (type.matches(e)) e.id,
    ];

    test('spending leaves out income and own transfers', () {
      expect(idsOf(ActivityType.spending), [1, 2, 6]);
    });

    test('day-to-day is spending in day-to-day categories', () {
      expect(idsOf(ActivityType.dayToDay), [1]);
    });

    test('money in leaves out own transfers', () {
      expect(idsOf(ActivityType.moneyIn), [3]);
    });

    test('own transfers are both halves', () {
      expect(idsOf(ActivityType.transfers), [4, 5]);
    });
  });

  group('ActivityFilter', () {
    test('filters by account', () {
      const filter = ActivityFilter(accountId: bank);
      expect(all.where(filter.matches).map((e) => e.id), [3, 4]);
    });

    test('filters by date range, both ends included', () {
      final filter = ActivityFilter(from: today, to: today);
      expect(all.where(filter.matches).map((e) => e.id), [1, 3, 4, 5]);
    });

    test('searches payee, note, number and labels, ignoring case', () {
      bool search(LedgerEntry e, String q, [List<String> labels = const []]) =>
          ActivityFilter(query: q).matches(e, labels: labels);
      expect(search(named, 'kplc'), isTrue);
      expect(search(named, 'meter'), isTrue);
      expect(search(unknown, '0700'), isTrue);
      expect(search(groceries, 'groc', ['Groceries and household']), isTrue);
      expect(search(groceries, 'rent'), isFalse);
    });

    test('searches amounts with or without commas', () {
      expect(matchesSearch(groceries, '1,440'), isTrue);
      expect(matchesSearch(groceries, '1440'), isTrue);
      expect(matchesSearch(groceries, '144'), isTrue);
      expect(matchesSearch(groceries, '999'), isFalse);
    });

    test('round-trips through route query parameters', () {
      final filter = ActivityFilter(
        accountId: mpesa,
        type: ActivityType.dayToDay,
        from: CalendarDate(2026, 10, 1),
        to: today,
      );
      final back = ActivityFilter.fromQuery(filter.toQuery());
      expect(filter.toQuery(), {
        'account': '1',
        'type': 'dayToDay',
        'from': '2026-10-01',
        'to': '2026-10-26',
      });
      expect(back.accountId, mpesa);
      expect(back.type, ActivityType.dayToDay);
      expect(back.from, CalendarDate(2026, 10, 1));
      expect(back.to, today);
    });

    test('ignores malformed query parameters', () {
      final filter = ActivityFilter.fromQuery({
        'account': 'x',
        'type': 'everything',
        'from': '2026-02-30',
        'to': 'soon',
      });
      expect(filter.accountId, isNull);
      expect(filter.type, ActivityType.all);
      expect(filter.hasDateRange, isFalse);
    });
  });

  group('buildActivityFeed', () {
    test('groups by Nairobi day, newest first, with a transfer once', () {
      final days = buildActivityFeed(all);
      expect(days.map((d) => d.date), [today, today.addDays(-1)]);

      final todayLines = days.first.lines;
      expect(todayLines, hasLength(3));
      final transfer = todayLines.first as OwnTransferLine;
      expect(transfer.outflow, transferOut);
      expect(transfer.inflow, transferIn);
      expect((todayLines[1] as EntryLine).entry, groceries);
      expect((todayLines[2] as EntryLine).entry, salary);

      expect(days.last.lines.map((l) => (l as EntryLine).entry), [
        named,
        unknown,
      ]);
    });

    test('finds the other half of a transfer the filter left out', () {
      const filter = ActivityFilter(accountId: mpesa);
      final days = buildActivityFeed(all.where(filter.matches), all: all);
      final transfer = days.first.lines.first as OwnTransferLine;
      expect(transfer.shown, transferOut);
      expect(transfer.inflow, transferIn);
    });

    test('collapses noise to one line per day', () {
      final days = buildActivityFeed([
        entry(
          at: eat(2026, 10, 26, 9),
          amount: 100,
          kind: TransactionKind.charge,
        ),
        entry(
          at: eat(2026, 10, 26, 11),
          amount: 200,
          kind: TransactionKind.charge,
        ),
      ]);
      final noise = days.single.lines.single as DailyNoiseLine;
      expect(noise.count, 2);
      expect(noise.totalMinor, 300);
    });
  });

  group('weekInOut', () {
    test('counts income and spending since Monday, not transfers', () {
      final week = weekInOut([
        ...all,
        // Sunday, the week before.
        entry(at: eat(2026, 10, 25, 9), amount: kes(100), fee: kes(7)),
      ], today: today);
      expect(week.start, today);
      expect(week.inMinor, kes(2500));
      expect(week.outMinor, kes(1440));
    });

    test('starts on the Monday before', () {
      expect(startOfWeek(CalendarDate(2026, 11, 1)), today);
      expect(startOfWeek(CalendarDate(2026, 10, 28)), today);
    });
  });

  test('formats and parses calendar dates', () {
    expect(formatCalendarDate(CalendarDate(2026, 3, 5)), '2026-03-05');
    expect(parseCalendarDate('2026-03-05'), CalendarDate(2026, 3, 5));
    expect(parseCalendarDate('2026-13-01'), isNull);
    expect(parseCalendarDate(null), isNull);
  });
}
