import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/ask/rule_question_reader.dart';
import 'package:pesaclarity/src/domain/ask/understanding.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

void main() {
  final reader = RuleQuestionReader(today: () => CalendarDate(2026, 11, 13));

  // Question, intent, and the slots it should find (kind: text).
  final cases = <(String, AskIntent, Map<SlotKind, String>)>[
    (
      'How much did I spend on food last month?',
      AskIntent.spent,
      {SlotKind.category: 'food', SlotKind.period: 'last month'},
    ),
    (
      'What did I pay Kenya Power this year?',
      AskIntent.spent,
      {SlotKind.payee: 'kenya power', SlotKind.period: 'this year'},
    ),
    (
      'How much came in this week?',
      AskIntent.received,
      {SlotKind.period: 'this week'},
    ),
    ('How much do I still owe?', AskIntent.debts, {}),
    ('how much to john', AskIntent.spent, {SlotKind.payee: 'john'}),
    (
      'How has my food spending changed this year?',
      AskIntent.trend,
      {SlotKind.category: 'food', SlotKind.period: 'this year'},
    ),
    ('and only Naivas?', AskIntent.refine, {SlotKind.payee: 'naivas'}),
    ('Should I buy a car?', AskIntent.outOfScope, {}),
    (
      'What sold most this week?',
      AskIntent.topItems,
      {SlotKind.period: 'this week'},
    ),
    ('What is safe to spend?', AskIntent.safeToSpend, {}),
    ('How much can I spend today?', AskIntent.safeToSpend, {}),
    ('Who owes me?', AskIntent.whoOwesMe, {}),
    ('Profit this week', AskIntent.profit, {SlotKind.period: 'this week'}),
    ('Low stock', AskIntent.lowStock, {}),
    ('What bills are coming up?', AskIntent.billsDue, {}),
    ('Show my subscriptions', AskIntent.subscriptions, {}),
    ('How are my goals?', AskIntent.goals, {}),
    ('How much have I lent out?', AskIntent.lent, {}),
    (
      "What's my M-Pesa balance?",
      AskIntent.balance,
      {SlotKind.account: 'm-pesa'},
    ),
    ("What's my balance?", AskIntent.balance, {}),
    ('What is my total balance?', AskIntent.balance, {}),
    ('KCB account balance', AskIntent.balance, {SlotKind.account: 'kcb'}),
    ('How much money do I have?', AskIntent.balance, {}),
    (
      'How much have I paid in transaction charges this month?',
      AskIntent.fees,
      {SlotKind.period: 'this month'},
    ),
    (
      'Fuliza charges last month',
      AskIntent.fees,
      {SlotKind.period: 'last month'},
    ),
    (
      'How many times did I pay Naivas in October?',
      AskIntent.countPayments,
      {SlotKind.payee: 'naivas', SlotKind.period: 'in october'},
    ),
    (
      'What was my biggest payment last week?',
      AskIntent.biggestPayment,
      {SlotKind.period: 'last week'},
    ),
    ('Who do I pay the most?', AskIntent.topPayees, {}),
    ('Where does my money go?', AskIntent.topCategories, {}),
    ('Where does my income come from?', AskIntent.incomeSources, {}),
    (
      'Compare transport with last month',
      AskIntent.compare,
      {SlotKind.category: 'transport', SlotKind.period: 'last month'},
    ),
    (
      'How much did I send to Mama Mboga since June?',
      AskIntent.sentTo,
      {SlotKind.payee: 'mama mboga', SlotKind.period: 'since june'},
    ),
    (
      'Money received from Acme in 2025',
      AskIntent.receivedFrom,
      {SlotKind.payee: 'acme', SlotKind.period: 'in 2025'},
    ),
    // Money in from someone or an own account, however it is put.
    (
      'How much did KCB send me?',
      AskIntent.receivedFrom,
      {SlotKind.payee: 'kcb'},
    ),
    (
      'How much has John Kamau sent me this month?',
      AskIntent.receivedFrom,
      {SlotKind.payee: 'john kamau', SlotKind.period: 'this month'},
    ),
    (
      'Did Acme pay me last month?',
      AskIntent.receivedFrom,
      {SlotKind.payee: 'acme'},
    ),
    (
      'What has Example Sacco paid me?',
      AskIntent.receivedFrom,
      {SlotKind.payee: 'example sacco'},
    ),
    (
      'How much did I receive from Acme?',
      AskIntent.receivedFrom,
      {SlotKind.payee: 'acme'},
    ),
    (
      'How much I got from Mama Mboga',
      AskIntent.receivedFrom,
      {SlotKind.payee: 'mama mboga'},
    ),
    (
      'Money received from KCB',
      AskIntent.receivedFrom,
      {SlotKind.payee: 'kcb'},
    ),
    (
      'How much did I send to John?',
      AskIntent.sentTo,
      {SlotKind.payee: 'john'},
    ),
    ('Sales today', AskIntent.sales, {SlotKind.period: 'today'}),
    ('How many tomatoes sold this month?', AskIntent.sales, {}),
    (
      'nimetumia pesa ngapi kwa chakula mwezi huu',
      AskIntent.spent,
      {SlotKind.category: 'chakula', SlotKind.period: 'mwezi huu'},
    ),
    (
      'fare last 3 months',
      AskIntent.refine,
      {SlotKind.category: 'fare', SlotKind.period: 'last 3 months'},
    ),
    ('doh ngapi nimetumia leo', AskIntent.spent, {SlotKind.period: 'leo'}),
    ('hi', AskIntent.hi, {}),
    ('Habari', AskIntent.hi, {}),
    ('thanks!', AskIntent.thanks, {}),
    ('asante sana', AskIntent.thanks, {}),
    ('bye', AskIntent.bye, {}),
    ('help', AskIntent.help, {}),
    ('What can I ask?', AskIntent.help, {}),
    ("What's the weather?", AskIntent.outOfScope, {}),
    ('last month?', AskIntent.refine, {SlotKind.period: 'last month'}),
    ('what about September?', AskIntent.refine, {SlotKind.period: 'september'}),
    (
      'Spending on rent in the last 6 months',
      AskIntent.spent,
      {SlotKind.category: 'rent', SlotKind.period: 'in the last 6 months'},
    ),
    (
      'Payments over 5,000 this month',
      AskIntent.spent,
      {SlotKind.amount: '5,000', SlotKind.period: 'this month'},
    ),
    (
      'How much do I spend on airtime each month?',
      AskIntent.trend,
      {SlotKind.category: 'airtime'},
    ),
    (
      'How much salary did I get last month?',
      AskIntent.received,
      {SlotKind.period: 'last month'},
    ),
    ('My fuliza', AskIntent.debts, {}),
    (
      'Spent at Naivas yesterday',
      AskIntent.spent,
      {SlotKind.payee: 'naivas', SlotKind.period: 'yesterday'},
    ),
  ];

  test(
    'has at least 40 questions',
    () => expect(cases.length, greaterThan(40)),
  );

  for (final (question, intent, slots) in cases) {
    test(question, () {
      final u = reader.read(question);
      expect(u.intent, intent, reason: 'intent');
      for (final MapEntry(:key, :value) in slots.entries) {
        expect(
          u.spans.where((s) => s.kind == key).map((s) => s.text),
          contains(value),
          reason: '${key.name} in ${u.spans}',
        );
      }
    });
  }

  test('money in from someone is the rules\' to read', () {
    for (final q in [
      'How much did KCB send me?',
      'KCB sent me how much',
      'received from Acme',
      'what I got from Acme',
    ]) {
      expect(RuleQuestionReader.readsMoneyInFrom(q), isTrue, reason: q);
    }
    for (final q in [
      'How much did I send to John?',
      "What's my M-Pesa balance?",
      'How much did I spend this month?',
    ]) {
      expect(RuleQuestionReader.readsMoneyInFrom(q), isFalse, reason: q);
    }
  });

  test('a charge is never a payee, and what it is taken on is an account', () {
    for (final (q, account) in [
      (
        'How much did I pay in charges on Example Bank this month?',
        'example bank',
      ),
      ('fees on my Example Wallet last month', 'example wallet'),
      ('What did I pay in transaction charges on Examplepay?', 'examplepay'),
      ('How much did I pay in charges this month?', null),
      ('How much was I charged in fees this week?', null),
    ]) {
      final u = reader.read(q);
      expect(u.intent, AskIntent.fees, reason: q);
      expect(u.span(SlotKind.payee), isNull, reason: '$q: ${u.spans}');
      expect(u.span(SlotKind.category), isNull, reason: '$q: ${u.spans}');
      expect(u.span(SlotKind.account)?.text, account, reason: q);
    }
  });

  test('round-trips as JSON', () {
    final u = reader.read('How much did I spend on food last month?');
    final back = Understanding.fromJson(u.toJson());
    expect(back.intent, u.intent);
    expect(back.spans, u.spans);
  });
}
