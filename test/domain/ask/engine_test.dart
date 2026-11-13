import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/ask/answer.dart';
import 'package:pesaclarity/src/domain/ask/context.dart';
import 'package:pesaclarity/src/domain/ask/data_source.dart';
import 'package:pesaclarity/src/domain/ask/engine.dart';
import 'package:pesaclarity/src/domain/ask/matcher.dart';
import 'package:pesaclarity/src/domain/ask/periods.dart';
import 'package:pesaclarity/src/domain/ask/reply_writer.dart';
import 'package:pesaclarity/src/domain/ask/rule_question_reader.dart';
import 'package:pesaclarity/src/domain/ask/understanding.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

var _id = 1;

LedgerEntry _out(
  DateTime at,
  int shillings, {
  int? category,
  int? payee,
  String? name,
}) => LedgerEntry(
  id: _id++,
  accountId: 1,
  occurredAt: at,
  amountMinor: kes(shillings),
  direction: TransactionDirection.outflow,
  kind: TransactionKind.till,
  categoryId: category,
  categoryType: CategoryType.expense,
  payeeId: payee,
  payeeName: name,
  counterpartyName: name,
);

LedgerEntry _in(DateTime at, int shillings, {String? name}) => LedgerEntry(
  id: _id++,
  accountId: 1,
  occurredAt: at,
  amountMinor: kes(shillings),
  direction: TransactionDirection.inflow,
  kind: TransactionKind.received,
  categoryType: CategoryType.income,
  counterpartyName: name,
);

class _Source implements AskDataSource {
  _Source(this.all, {this.items = const []});

  final List<LedgerEntry> all;
  final List<AskLine> items;
  final learned = <AskShortcut>[];

  @override
  Future<List<AskEntity>> entities() async => const [
    AskEntity(SlotKind.category, 'c:1', 'Food'),
    AskEntity(SlotKind.category, 'c:2', 'Transport'),
    AskEntity(SlotKind.payee, 'p:1', 'Naivas'),
    AskEntity(SlotKind.payee, 'p:2', 'Mama Mboga'),
    AskEntity(SlotKind.payee, 'p:3', 'John Kamau'),
    AskEntity(SlotKind.payee, 'p:4', 'John Otieno'),
    AskEntity(SlotKind.item, 'i:1', 'Tomatoes'),
  ];

  @override
  Future<List<AskShortcut>> shortcuts() async => learned;

  @override
  Future<List<LedgerEntry>> entries(DateTime from, DateTime to) async => [
    for (final e in all)
      if (!e.occurredAt.isBefore(from) && e.occurredAt.isBefore(to)) e,
  ];

  @override
  Future<AskSafeToSpend?> safeToSpend() async =>
      const AskSafeToSpend(leftTodayMinor: 30000, overMinor: 0);

  @override
  Future<List<AskLine>> billsDue() async => [
    AskLine('Kenya Power', kes(2500), date: CalendarDate(2026, 11, 20)),
  ];

  @override
  Future<List<AskLine>> subscriptions() async => const [];

  @override
  Future<List<AskLine>> debts() async => [
    AskLine('Test Bank', kes(30000)),
    AskLine('Fuliza', kes(8500)),
  ];

  @override
  Future<List<AskLine>> lent() async => const [];

  @override
  Future<List<AskLine>> owedToMe() async => [AskLine('Customer A', kes(400))];

  @override
  Future<List<AskLine>> goals() async => const [];

  @override
  Future<List<AskLine>> balances() async => [AskLine('M-Pesa', kes(5000))];

  @override
  Future<AskLine> sales(AskPeriod period) async =>
      AskLine('Sales', kes(8400), count: 42);

  @override
  Future<List<AskLine>> itemsSold(AskPeriod period) async => items;

  @override
  Future<int?> profit(AskPeriod period) async => kes(3000);

  @override
  Future<List<AskLine>> lowStock() async => const [];
}

void main() {
  final now = eat(2026, 11, 13, 10);
  final today = CalendarDate(2026, 11, 13);
  late _Source source;
  late AskEngine engine;

  setUp(() {
    source = _Source(
      [
        // October food: 5,920 at Naivas, 4,310 to Mama Mboga.
        _out(eat(2026, 10, 3), 3000, category: 1, payee: 1, name: 'Naivas'),
        _out(eat(2026, 10, 18), 2920, category: 1, payee: 1, name: 'Naivas'),
        _out(
          eat(2026, 10, 20),
          4310,
          category: 1,
          payee: 2,
          name: 'Mama Mboga',
        ),
        // September food: 12,000.
        _out(eat(2026, 9, 10), 12000, category: 1, payee: 1, name: 'Naivas'),
        // March food peak.
        _out(eat(2026, 3, 5), 14200, category: 1, payee: 1, name: 'Naivas'),
        _out(eat(2026, 11, 2), 4100, category: 1, payee: 2, name: 'Mama Mboga'),
        _out(eat(2026, 10, 9), 600, category: 2, payee: 3, name: 'John Kamau'),
        _out(eat(2026, 11, 9), 800, payee: 4, name: 'John Otieno'),
        _in(eat(2026, 11, 10), 2500, name: 'Acme'),
      ],
      items: [
        AskLine('Tomatoes', kes(8400), count: 42),
        AskLine('Onions', kes(4050), count: 27),
      ],
    );
    engine = AskEngine(
      source: source,
      reader: RuleQuestionReader(today: () => today),
    );
  });

  String text(AskAnswer a) =>
      fillTemplate(a.template, a.facts, money: (m) => '${m ~/ 100}');

  test('food last month: total, rows, and the month before', () async {
    final turn = await engine.ask(
      'How much did I spend on food last month?',
      context: AskContext.empty,
      now: now,
    );
    final a = turn.answer;
    expect(a.figureMinor, kes(10230));
    expect(a.headline, 'Food · October 2026');
    expect(a.kind, ReplyKind.totalDown);
    expect(text(a), contains('1770'));
    expect(text(a), contains('September'));
    expect(a.rows.first.title, 'Naivas');
    expect(a.rows.first.amountMinor, kes(5920));
    expect(a.suggestions, contains('Compare with September'));
    expect(checkTemplate(a.template, a.facts.keys.toSet()), isTrue);
  });

  test('a follow-up keeps food and October and adds Naivas', () async {
    final first = await engine.ask(
      'How much did I spend on food last month?',
      context: AskContext.empty,
      now: now,
    );
    final next = await engine.ask(
      'and only Naivas?',
      context: first.context,
      now: now,
    );
    expect(
      next.context.entities.keys,
      containsAll([SlotKind.category, SlotKind.payee]),
    );
    expect(next.answer.figureMinor, kes(5920));
    expect(next.answer.chart!.isShare, isTrue);
    expect(next.answer.chart!.partPercent, 58);
  });

  test('a trend gets a month by month chart', () async {
    final a = (await engine.ask(
      'How has my food spending changed this year?',
      context: AskContext.empty,
      now: now,
    )).answer;
    expect(a.kind, ReplyKind.trend);
    expect(a.chart!.bars, hasLength(11));
    expect(a.chart!.bars[2].highlight, isTrue);
    expect(text(a), contains('March'));
  });

  test('two Johns: asks which, then answers the pick', () async {
    final turn = await engine.ask(
      'how much to john',
      context: AskContext.empty,
      now: now,
    );
    final a = turn.answer;
    expect(a.kind, ReplyKind.clarify);
    expect(a.choices.map((c) => c.name), ['John Kamau', 'John Otieno']);
    expect(a.askPeriod, isTrue);
    final picked = await engine.resolve(
      a,
      choice: a.choices.last,
      period: AskPeriod.thisMonth(today),
      now: now,
    );
    expect(picked.answer.figureMinor, kes(800));
    final both = await engine.resolve(
      a,
      choice: null,
      period: AskPeriod.lastMonths(3, today),
      now: now,
    );
    expect(both.answer.figureMinor, kes(1400));
  });

  test('a learned shortcut skips the question', () async {
    source.learned.add(const AskShortcut('john', SlotKind.payee, 'p:3'));
    final a = (await engine.ask(
      'how much to john last month',
      context: AskContext.empty,
      now: now,
    )).answer;
    expect(a.kind, isNot(ReplyKind.clarify));
    expect(a.figureMinor, kes(600));
  });

  test('outside the records: a plain reply and suggestions', () async {
    final a = (await engine.ask(
      'Should I buy a car?',
      context: AskContext.empty,
      now: now,
    )).answer;
    expect(a.kind, ReplyKind.cant);
    expect(a.suggestions, isNotEmpty);
    expect(a.canUpdate, isFalse);
  });

  test('a name not in the space says so', () async {
    final a = (await engine.ask(
      'how much on zebras',
      context: AskContext.empty,
      now: now,
    )).answer;
    expect(a.kind, ReplyKind.notFound);
  });

  test('money in, safe to spend, debts, bills, balance', () async {
    Future<AskAnswer> ask(String q) async =>
        (await engine.ask(q, context: AskContext.empty, now: now)).answer;
    expect((await ask('How much came in this week?')).figureMinor, kes(2500));
    expect((await ask('What is safe to spend?')).figureMinor, 30000);
    final debts = await ask('How much do I still owe?');
    expect(debts.figureMinor, kes(38500));
    expect(debts.rows, hasLength(2));
    final bills = await ask('What bills are coming up?');
    expect(text(bills), contains('Kenya Power'));
    expect((await ask("What's my balance?")).figureMinor, kes(5000));
  });

  test('business: what sold most, profit, who owes me', () async {
    final shop = AskEngine(
      source: source,
      reader: RuleQuestionReader(today: () => today),
      spaceKind: SpaceKind.business,
    );
    Future<AskAnswer> ask(String q) async =>
        (await shop.ask(q, context: AskContext.empty, now: now)).answer;
    final top = await ask('What sold most this week?');
    expect(top.figureText, 'Tomatoes');
    expect(top.headline, 'Sales · Mon 9 to Fri 13 Nov');
    expect((await ask('Profit this week')).figureMinor, kes(3000));
    expect((await ask('Who owes me?')).figureMinor, kes(400));
    expect(shop.starters.first, 'What sold most this week?');
  });

  test('Update works the numbers out again from the saved lookup', () async {
    final first = await engine.ask(
      'Food this month',
      context: AskContext.empty,
      now: now,
    );
    source.all.add(_out(eat(2026, 11, 12), 1000, category: 1, payee: 1));
    final fresh = await engine.run(first.answer.context, now);
    expect(fresh.figureMinor, first.answer.figureMinor! + kes(1000));
    final back = AskAnswer.fromJson(first.answer.toJson());
    expect(back.figureMinor, first.answer.figureMinor);
    expect(back.context.entities[SlotKind.category]?.name, 'Food');
  });

  test('titles come from the first question', () async {
    final food = await engine.ask(
      'How has my food spending changed this year?',
      context: AskContext.empty,
      now: now,
    );
    expect(conversationTitle(food.context, today), 'Food spending this year');
    final john = await engine.ask(
      'How much did I send to John Kamau?',
      context: AskContext.empty,
      now: now,
    );
    expect(conversationTitle(john.context, today), 'Money sent to John Kamau');
  });

  test('small talk needs no lookup', () async {
    final a = (await engine.ask(
      'hi',
      context: AskContext.empty,
      now: now,
    )).answer;
    expect(a.kind, ReplyKind.hi);
    expect(a.suggestions, isNotEmpty);
  });
}
