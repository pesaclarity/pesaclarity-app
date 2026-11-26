import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/slm_experiment/domain/slm_facts.dart';

var _id = 0;

LedgerEntry _out(
  CalendarDate day,
  int minor, {
  int? category,
  String? payee,
  int fee = 0,
}) => LedgerEntry(
  id: ++_id,
  accountId: 1,
  occurredAt: day.startInstant.add(const Duration(hours: 12)),
  amountMinor: minor,
  direction: TransactionDirection.outflow,
  kind: TransactionKind.paybill,
  categoryId: category,
  categoryType: CategoryType.expense,
  payeeName: payee,
  feeMinor: fee,
);

LedgerEntry _in(CalendarDate day, int minor) => LedgerEntry(
  id: ++_id,
  accountId: 1,
  occurredAt: day.startInstant.add(const Duration(hours: 9)),
  amountMinor: minor,
  direction: TransactionDirection.inflow,
  kind: TransactionKind.received,
  categoryType: CategoryType.income,
  payeeId: 9,
);

void main() {
  final today = CalendarDate(2026, 11, 20);
  final input = SlmFactsInput(
    today: today,
    lastPayday: CalendarDate(2026, 11, 15),
    categoryNames: const {1: 'Food', 2: 'Rent', 3: 'Transport'},
    entries: [
      _in(CalendarDate(2026, 8, 28), 5000000),
      _out(CalendarDate(2026, 9, 3), 1500000, category: 2),
      _in(CalendarDate(2026, 10, 28), 6000000),
      _out(CalendarDate(2026, 10, 4), 310000, category: 3),
      _out(CalendarDate(2026, 11, 2), 1500000, category: 2, payee: 'Landlord'),
      _out(CalendarDate(2026, 11, 5), 840000, category: 1, payee: 'Naivas'),
      _out(CalendarDate(2026, 11, 16), 400000, category: 1, payee: 'Naivas'),
      _out(CalendarDate(2026, 11, 17), 420000, category: 3, fee: 3800),
      _in(CalendarDate(2026, 11, 15), 8000000),
    ],
    balances: const [
      SlmLine('M-Pesa', 1250000),
      SlmLine('M-Shwari', 3000000, savings: true),
    ],
    bills: [
      SlmLine('Internet', 300000, date: CalendarDate(2026, 11, 25)),
      SlmLine('Old bill', 100000, date: CalendarDate(2026, 11, 1)),
    ],
    budgets: const [SlmBudget('Food', 1000000, 1240000)],
  );

  test('works out every number from the records', () {
    final text = SlmFacts.of(input).text;
    expect(text, contains('- 20 Nov 2026'));
    expect(
      text,
      contains(
        'This month so far (Nov 2026): money in KES 80,000, '
        'spent KES 31,600, left KES 48,400',
      ),
    );
    expect(
      text,
      contains(
        'Since payday (15 Nov 2026): money in KES 80,000, '
        'spent KES 8,200, left KES 71,800',
      ),
    );
    // Categories biggest first, then payees.
    expect(
      text,
      contains(
        'Top spending this month:\n- Rent: KES 15,000\n'
        '- Food: KES 12,400\n- Transport: KES 4,200',
      ),
    );
    expect(
      text,
      contains(
        'Top payees this month:\n- Landlord: KES 15,000\n'
        '- Naivas: KES 12,400',
      ),
    );
    expect(text, contains('Fees this month:\n- KES 38'));
    expect(
      text,
      contains('Food: planned KES 10,000, spent KES 12,400, over by KES 2,400'),
    );
    expect(text, contains('Internet: KES 3,000, due 25 Nov 2026'));
    expect(text, isNot(contains('Old bill')));
    expect(text, contains('Day-to-day accounts: KES 12,500'));
    expect(text, contains('Savings accounts: KES 30,000'));
    expect(
      text,
      contains(
        'Last 3 months:\n- Aug 2026: money in KES 50,000, spent KES 0\n'
        '- Sep 2026: money in KES 0, spent KES 15,000\n'
        '- Oct 2026: money in KES 60,000, spent KES 3,100',
      ),
    );
  });

  test('uses the fees Insights counts when given', () {
    final facts = SlmFacts.of(
      SlmFactsInput(
        today: today,
        entries: input.entries,
        feesThisMonthMinor: 51000,
      ),
    );
    expect(facts.text, contains('Fees this month:\n- KES 510'));
  });

  test('leaves out what there is none of, and says so in numbers', () {
    final text = SlmFacts.of(SlmFactsInput(today: today, entries: const []))
        .text;
    expect(text, contains('money in KES 0, spent KES 0, left KES 0'));
    expect(text, isNot(contains('Top spending')));
    expect(text, isNot(contains('Budgets')));
    expect(text, isNot(contains('Balances')));
  });

  test('stays within the prompt budget with many records', () {
    final many = SlmFactsInput(
      today: today,
      entries: [
        for (var i = 0; i < 400; i++)
          _out(
            CalendarDate(2026, 11, 1 + i % 19),
            1000 + i,
            category: i % 40,
            payee: 'A payee with a rather long name number $i',
          ),
      ],
      categoryNames: {for (var i = 0; i < 40; i++) i: 'Category $i'},
      balances: [for (var i = 0; i < 30; i++) SlmLine('Account $i', i * 1000)],
      bills: [
        for (var i = 0; i < 30; i++)
          SlmLine('Bill $i', 1000, date: today.addDays(i)),
      ],
      budgets: [for (var i = 0; i < 30; i++) SlmBudget('Budget $i', 100, i)],
    );
    final facts = SlmFacts.of(many);
    expect(facts.text.length, lessThanOrEqualTo(SlmFacts.maxChars));
    expect(slmSystem(facts).length, lessThan(5200)); // ~1,500 tokens
    expect(facts.text, contains('Top spending this month'));
  });

  test('the rules tell the model not to work out numbers', () {
    expect(slmSystemPrompt, contains('Do not add'));
    expect(slmSystemPrompt, contains('not sure'));
  });
}
