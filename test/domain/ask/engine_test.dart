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

/// KCB sending M-Pesa [shillings]: the two halves of one own transfer.
List<LedgerEntry> _kcbToMpesa(DateTime at, int shillings) {
  final out = _id++;
  final into = _id++;
  return [
    LedgerEntry(
      id: out,
      accountId: 2,
      occurredAt: at,
      amountMinor: kes(shillings),
      direction: TransactionDirection.outflow,
      kind: TransactionKind.bank,
      transferPairId: into,
    ),
    LedgerEntry(
      id: into,
      accountId: 1,
      occurredAt: at,
      amountMinor: kes(shillings),
      direction: TransactionDirection.inflow,
      kind: TransactionKind.received,
      counterpartyName: 'KCB',
      transferPairId: out,
    ),
  ];
}

class _Source implements AskDataSource {
  _Source(this.all, {this.items = const [], List<AskLine>? accounts})
    : accounts = accounts ?? [AskLine('M-Pesa', kes(5000))];

  final List<LedgerEntry> all;
  final List<AskLine> items;
  List<AskLine> accounts;
  final learned = <AskShortcut>[];

  @override
  Future<List<AskEntity>> entities() async => const [
    AskEntity(SlotKind.category, 'c:1', 'Food'),
    AskEntity(SlotKind.category, 'c:2', 'Transport'),
    AskEntity(SlotKind.payee, 'p:1', 'Naivas'),
    AskEntity(SlotKind.payee, 'p:2', 'Mama Mboga'),
    AskEntity(SlotKind.payee, 'p:3', 'John Kamau'),
    AskEntity(SlotKind.payee, 'p:4', 'John Otieno'),
    // A name printed on a message, not a payee yet.
    AskEntity(SlotKind.payee, 'n:acme', 'Acme'),
    AskEntity(SlotKind.item, 'i:1', 'Tomatoes'),
    AskEntity(SlotKind.account, 'a:1', 'M-Pesa'),
    AskEntity(SlotKind.account, 'a:2', 'KCB'),
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
  Future<List<AskLine>> balances() async => accounts;

  @override
  Future<AskLine> sales(AskPeriod period) async =>
      AskLine('Sales', kes(8400), count: 42);

  @override
  Future<List<AskLine>> itemsSold(AskPeriod period) async => items;

  @override
  Future<int?> profit(AskPeriod period) async => kes(3000);

  @override
  Future<List<AskLine>> lowStock() async => const [];

  @override
  Future<int> fees(AskPeriod period) async => kes(120);
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
    final fees = await ask('How much did I pay in charges last month?');
    expect(fees.kind, ReplyKind.fees);
    expect(fees.figureMinor, kes(120));
    expect(fees.headline, 'Charges · October 2026');
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

  group('balances at or below zero', () {
    Future<String> balance(List<AskLine> accounts, String q) async {
      source.accounts = accounts;
      final a = (await engine.ask(
        q,
        context: AskContext.empty,
        now: now,
      )).answer;
      final t = text(a);
      // Never a minus sign in the words.
      expect(t.contains(RegExp('-[0-9]')), isFalse, reason: t);
      expect(checkTemplate(a.template, a.facts.keys.toSet()), isTrue);
      return t;
    }

    test('an account at zero has nothing left', () async {
      expect(
        await balance([
          const AskLine('M-Pesa', 0),
        ], "What's my M-Pesa balance?"),
        'You have nothing left on M-Pesa.',
      );
    });

    test('below zero with no Fuliza says only below zero', () async {
      expect(
        await balance([AskLine('KCB', kes(-2000))], 'KCB balance'),
        'KCB is 2000 below zero.',
      );
    });

    test('Fuliza is named only when the account owes it', () async {
      // Wallet at 0, 1,300 owed: what it owes Fuliza.
      expect(
        await balance([
          AskLine('M-Pesa', kes(-1300), fulizaOwedMinor: kes(1300)),
        ], "What's my M-Pesa balance?"),
        "M-Pesa is 1300 below zero: that's what you owe Fuliza.",
      );
      // Wallet at 200, 1,500 owed.
      expect(
        await balance([
          AskLine('M-Pesa', kes(-1300), fulizaOwedMinor: kes(1500)),
        ], "What's my M-Pesa balance?"),
        'M-Pesa is 1300 below zero once Fuliza is counted.',
      );
    });

    test('the total below zero or at zero', () async {
      expect(
        await balance([
          AskLine('M-Pesa', kes(-1300), fulizaOwedMinor: kes(1300)),
          AskLine('Cash', kes(150)),
        ], 'How much money do I have?'),
        "You're 1150 below zero once Fuliza is counted.",
      );
      expect(
        await balance([
          AskLine('KCB', kes(-700)),
          AskLine('Cash', kes(200)),
          // Savings are left out of the total, as on Balances.
          AskLine('Sacco', kes(9000), savings: true),
        ], 'How much money do I have?'),
        "You're 500 below zero across 3 accounts.",
      );
      expect(
        await balance([
          AskLine('KCB', kes(-200)),
          AskLine('Cash', kes(200)),
        ], 'How much money do I have?'),
        'You have nothing left across 2 accounts.',
      );
    });

    test('above zero is worded as before', () async {
      final a = (await engine.ask(
        "What's my balance?",
        context: AskContext.empty,
        now: now,
      )).answer;
      expect(a.kind, ReplyKind.balance);
      expect(a.facts['amount'], kes(5000));
    });
  });

  group('comparing with an empty period', () {
    Future<AskAnswer> ask(String q) async =>
        (await engine.ask(q, context: AskContext.empty, now: now)).answer;

    test('nothing before: "and nothing in October"', () async {
      final a = await ask(
        'How much did I pay John Otieno this month compared to last month?',
      );
      expect(a.kind, ReplyKind.spentFromNothing);
      expect(text(a), 'You spent 800 this month and nothing in October.');
      expect(a.figureMinor, kes(800));
    });

    test('nothing now: "nothing this month, and 600 in October"', () async {
      final a = await ask(
        'Did I spend more on transport this month than last month?',
      );
      expect(a.kind, ReplyKind.spentToNothing);
      expect(text(a), 'You spent nothing this month, and 600 in October.');
      expect(a.figureMinor, 0);
    });

    test('never "the 0 of"', () async {
      for (final q in [
        'How much did I pay John Otieno this month compared to last month?',
        'Did I spend more on transport this month than last month?',
        'Compare transport with last month',
      ]) {
        final t = text(await ask(q));
        expect(t, isNot(contains(' 0 ')), reason: t);
        expect(t, isNot(contains('the 0')), reason: t);
      }
    });
  });

  group('spending not sorted yet', () {
    AskEngine over(List<LedgerEntry> entries) => AskEngine(
      source: _Source(entries),
      reader: RuleQuestionReader(today: () => today),
    );

    Future<AskAnswer> where(AskEngine e) async => (await e.ask(
      'Where does my money go?',
      context: AskContext.empty,
      now: now,
    )).answer;

    test('most of it: says how much, names the biggest sorted', () async {
      final a = await where(
        over([
          _out(eat(2026, 11, 3), 5000, name: 'Example Landlord'),
          _out(eat(2026, 11, 4), 2000, category: 1, name: 'Naivas'),
          _out(eat(2026, 11, 5), 500, category: 2, name: 'Matatu'),
        ]),
      );
      expect(a.kind, ReplyKind.unsortedMost);
      expect(
        text(a),
        "Most of your spending this month, 5000, isn't sorted yet. Of what "
        'is sorted, Food is the biggest at 2000.',
      );
      expect(a.figureMinor, kes(7500));
      // The way to sort them: Insights, whose "Not sorted yet" opens them.
      expect(a.link, AskLink.insights);
    });

    test('the biggest part, but not most', () async {
      final a = await where(
        over([
          _out(eat(2026, 11, 3), 3000, name: 'Example Landlord'),
          _out(eat(2026, 11, 4), 2000, category: 1, name: 'Naivas'),
          _out(eat(2026, 11, 5), 1500, category: 2, name: 'Matatu'),
        ]),
      );
      expect(a.kind, ReplyKind.unsortedTop);
      expect(
        text(a),
        "3000 of your spending this month isn't sorted yet, more than any "
        'one category. Of what is sorted, Food is the biggest at 2000.',
      );
    });

    test('none of it sorted', () async {
      final a = await where(
        over([_out(eat(2026, 11, 3), 3000, name: 'Example Landlord')]),
      );
      expect(a.kind, ReplyKind.unsortedAll);
      expect(text(a), startsWith('None of your spending this month, 3000,'));
    });

    test('never named as a category, nor listed as one', () async {
      final a = await where(engine);
      expect(a.kind, ReplyKind.topCategories);
      expect(a.facts['category'], 'Food');
      expect(a.facts['list'], 'Food');
    });
  });

  group('money in from someone', () {
    Future<AskAnswer> ask(String q) async =>
        (await engine.ask(q, context: AskContext.empty, now: now)).answer;

    test('a payee who sent money: what came in from them', () async {
      for (final q in [
        'How much did Acme send me?',
        'How much has Acme sent me this month?',
        'What did Acme pay me this month?',
        'How much did I receive from Acme?',
        'Money I got from Acme',
      ]) {
        final a = await ask(q);
        expect(a.figureMinor, kes(2500), reason: q);
        expect(a.headline, 'Acme · November 2026', reason: q);
        expect(a.context.intent, AskIntent.receivedFrom, reason: q);
      }
    });

    test('an own account: what it moved into the others, said so', () async {
      source.all.addAll(_kcbToMpesa(eat(2026, 11, 6), 3920));
      for (final q in [
        'How much did KCB send me?',
        'How much has KCB sent me?',
        'How much did I receive from KCB?',
      ]) {
        final a = await ask(q);
        expect(a.kind, ReplyKind.ownTransfers, reason: q);
        expect(a.figureMinor, kes(3920), reason: q);
        expect(
          text(a),
          'KCB sent 3920 to your other accounts this month. That is your own '
          'money moving, so it is not counted as money in.',
        );
        expect(a.rows.single.title, 'M-Pesa');
      }
    });

    test('an own account that moved nothing says so', () async {
      final a = await ask('How much did KCB send me last month?');
      expect(a.kind, ReplyKind.noOwnTransfers);
      expect(a.figureMinor, 0);
      expect(text(a), startsWith('KCB sent nothing to your other accounts'));
    });
  });

  group('money in, as Home and Insights count it', () {
    Future<AskAnswer> ask(String q) async =>
        (await engine.ask(q, context: AskContext.empty, now: now)).answer;

    const phrasings = [
      'How much came in this month?',
      'money in this month',
      'How much did I receive this month?',
      'income this month',
      'How much did I get this month?',
    ];

    test(
      'every phrasing is money in, own transfers left out and said so',
      () async {
        source.all.addAll(_kcbToMpesa(eat(2026, 11, 6), 3920));
        for (final q in phrasings) {
          final a = await ask(q);
          expect(a.context.intent, AskIntent.received, reason: q);
          expect(a.figureMinor, kes(2500), reason: q);
          expect(
            text(a),
            endsWith(
              "The 3920 that moved between your own accounts isn't counted "
              'as money in.',
            ),
            reason: q,
          );
        }
      },
    );

    test('money waiting for a name is not income until it is named', () async {
      source.all.add(
        LedgerEntry(
          id: _id++,
          accountId: 1,
          occurredAt: eat(2026, 11, 11),
          amountMinor: kes(700),
          direction: TransactionDirection.inflow,
          kind: TransactionKind.received,
          // Acme again, this time with nothing to say it was income.
          counterpartyName: 'Acme',
        ),
      );
      final a = await ask('How much came in this month?');
      expect(a.figureMinor, kes(2500));
      expect(text(a), contains("The 700 from people you haven't named yet"));
      // Asked about by name, all they sent is counted.
      final from = await ask('How much did Acme send me?');
      expect(from.figureMinor, kes(3200));
    });

    test('with none, it says nothing came in', () async {
      source.all.removeWhere((e) => e.isInflow);
      source.all.addAll(_kcbToMpesa(eat(2026, 11, 6), 3920));
      for (final q in phrasings) {
        final a = await ask(q);
        expect(a.kind, ReplyKind.nothingIn, reason: q);
        expect(a.figureMinor, 0, reason: q);
        expect(
          text(a),
          'Nothing came in this month. The 3920 that moved between your own '
          "accounts isn't counted as money in.",
          reason: q,
        );
      }
      source.all.removeWhere((e) => e.isInflow);
      expect(
        text(await ask('How much came in this month?')),
        'Nothing came in this month.',
      );
    });
  });

  group('a name the answer cannot use is said, never a wider total', () {
    Future<AskAnswer> ask(String q) async =>
        (await engine.ask(q, context: AskContext.empty, now: now)).answer;

    // One question per intent that takes a name or a period, each naming
    // something the records do not have or the answer cannot narrow by.
    final cases = <(String, AskIntent, ReplyKind, String)>[
      (
        'How much did I spend at Example Nowhere this month?',
        AskIntent.spent,
        ReplyKind.noPaymentsTo,
        "I couldn't find payments to Example Nowhere this month.",
      ),
      (
        'How much did I spend on food at Example Nowhere?',
        AskIntent.spent,
        ReplyKind.noPaymentsTo,
        "I couldn't find payments to Example Nowhere this month.",
      ),
      (
        'How much did I send to Example Nowhere?',
        AskIntent.sentTo,
        ReplyKind.noPaymentsTo,
        "I couldn't find payments to Example Nowhere this month.",
      ),
      (
        'How much did I receive from Example Nowhere?',
        AskIntent.receivedFrom,
        ReplyKind.nothingFrom,
        "I couldn't find money from Example Nowhere this month.",
      ),
      (
        'How many times did I pay Example Nowhere this month?',
        AskIntent.countPayments,
        ReplyKind.noPaymentsTo,
        "I couldn't find payments to Example Nowhere this month.",
      ),
      (
        'What was my biggest payment to Example Nowhere?',
        AskIntent.biggestPayment,
        ReplyKind.noPaymentsTo,
        "I couldn't find payments to Example Nowhere this month.",
      ),
      (
        'Who did I pay the most for zebras?',
        AskIntent.topPayees,
        ReplyKind.noPaymentsTo,
        "I couldn't find payments to Zebras this month.",
      ),
      (
        'Where did my money go at Example Nowhere?',
        AskIntent.topCategories,
        ReplyKind.noPaymentsTo,
        "I couldn't find payments to Example Nowhere this month.",
      ),
      (
        'How has my spending at Example Nowhere changed?',
        AskIntent.trend,
        ReplyKind.noPaymentsTo,
        "I couldn't find payments to Example Nowhere this year.",
      ),
      (
        'Compare my spending at Example Nowhere with last month',
        AskIntent.compare,
        ReplyKind.noPaymentsTo,
        "I couldn't find payments to Example Nowhere last month.",
      ),
      (
        'income sources from Example Nowhere',
        AskIntent.incomeSources,
        ReplyKind.nothingFrom,
        "I couldn't find money from Example Nowhere this month.",
      ),
      (
        "What's my Equity balance?",
        AskIntent.balance,
        ReplyKind.noAccount,
        "I couldn't find an account called Equity.",
      ),
      (
        'How much do I owe to Example Lender?',
        AskIntent.debts,
        ReplyKind.notAmong,
        "I couldn't find Example Lender among your debts.",
      ),
      (
        'What bills are due for Example Water?',
        AskIntent.billsDue,
        ReplyKind.notAmong,
        "I couldn't find Example Water among your bills.",
      ),
      (
        'What bills were due last month?',
        AskIntent.billsDue,
        ReplyKind.onlyNow,
        'I can only tell you about your bills as things stand now, not '
            'last month.',
      ),
      (
        'How much did I pay in charges on KCB this month?',
        AskIntent.fees,
        ReplyKind.notNarrowed,
        "I couldn't find charges for KCB alone, so I haven't given you the "
            'total for everything.',
      ),
      (
        'What was safe to spend last week?',
        AskIntent.safeToSpend,
        ReplyKind.onlyNow,
        'I can only tell you about safe to spend as things stand now, not '
            'last week.',
      ),
      (
        'Sales of zebras this week',
        AskIntent.sales,
        ReplyKind.noSalesOf,
        "I couldn't find sales of Zebras this week.",
      ),
      (
        'How many payments over 1000 this month?',
        AskIntent.countPayments,
        ReplyKind.cantBySize,
        "I can't pick out payments by their size yet, so I haven't given you "
            'a figure for all of them.',
      ),
    ];
    for (final (q, intent, kind, says) in cases) {
      test('${intent.label}: $q', () async {
        final turn = await engine.ask(q, context: AskContext.empty, now: now);
        expect(turn.context.intent, intent, reason: q);
        expect(turn.answer.kind, kind, reason: q);
        expect(turn.answer.figureMinor, isNull, reason: q);
        expect(turn.answer.rows, isEmpty, reason: q);
        expect(text(turn.answer), says);
      });
    }

    test('a name the answer can use still narrows it', () async {
      final bank = await ask('How much do I owe to Test Bank?');
      expect(bank.kind, ReplyKind.debts);
      expect(bank.figureMinor, kes(30000));
      final bills = await ask('What bills are due this month?');
      expect(bills.kind, ReplyKind.bills);
      expect(bills.rows.single.title, 'Kenya Power');
      final naivas = await ask('How many times did I pay Naivas last month?');
      expect(naivas.kind, ReplyKind.count);
      expect(naivas.figureText, 'Twice');
      expect(naivas.facts['amount'], kes(5920));
    });
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
