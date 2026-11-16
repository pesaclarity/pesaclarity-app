import 'answer.dart';

/// Every placeholder a reply sentence may use.
const replyPlaceholders = {
  'amount',
  'category',
  'period',
  'prev_period',
  'change',
  'payee',
  'count',
  'date',
  'item',
  'account',
  'percent',
  // Used by the trained writer (pesaclarity-ml docs/ASK.md).
  'prev_amount',
  'target',
  'days',
  'goal',
  'name',
  'list',
  'number',
  // The biggest sorted category's amount, beside what is not sorted yet.
  'top_amount',
};

/// Placeholders whose facts are money in minor units.
const moneyPlaceholders = {
  'amount',
  'change',
  'prev_amount',
  'target',
  'top_amount',
};

final _placeholder = RegExp(r'\{([a-z_]+)\}');

/// The placeholders [template] uses.
Set<String> placeholdersIn(String template) => {
  for (final m in _placeholder.allMatches(template)) m.group(1)!,
};

/// Whether [template] is safe to show with [provided] facts: it names only
/// placeholders that were given, and carries no digits of its own, so every
/// number shown comes from the records.
bool checkTemplate(String template, Set<String> provided) {
  if (template.trim().isEmpty) return false;
  final used = placeholdersIn(template);
  if (!used.every(
    (p) => provided.contains(p) && replyPlaceholders.contains(p),
  )) {
    return false;
  }
  final bare = template.replaceAll(_placeholder, '');
  if (RegExp('[0-9]').hasMatch(bare)) return false;
  return !bare.contains('{') && !bare.contains('}');
}

/// [template] with each placeholder replaced: money through [money], the
/// rest as given. A sentence that starts with a filled word ("last month,
/// ...") starts with a capital.
String fillTemplate(
  String template,
  Map<String, Object> facts, {
  required String Function(int minor) money,
}) => capitalise(
  template.replaceAllMapped(_placeholder, (m) {
    final key = m.group(1)!;
    final value = facts[key];
    if (value == null) return '';
    if (moneyPlaceholders.contains(key) && value is int) return money(value);
    return '$value';
  }),
);

/// Upper-cases the first letter of [text] and of each sentence after `.`,
/// `!` or `?`. A sentence that starts with a digit or a sign stays as is.
String capitalise(String text) {
  final out = StringBuffer();
  var capital = true;
  for (final c in text.split('')) {
    if (capital && c != ' ') {
      out.write(c.toUpperCase());
      capital = false;
    } else {
      out.write(c);
      if (c == '.' || c == '!' || c == '?') capital = true;
    }
  }
  return out.toString();
}

/// Writes the sentence for a reply from its kind and the facts it has. Every
/// answer gets one; the trained writer ([ModelReplyWriter] in
/// model_reply_writer.dart) may word it instead, and this one stays when it
/// cannot.
abstract interface class ReplyWriter {
  /// A template using only [facts]' placeholders. [seed] picks among
  /// sentences so replies vary.
  String write(ReplyKind kind, Set<String> facts, {int seed = 0});

  void close();
}

/// A model writer, falling back to [fallback] whenever its sentence fails
/// [checkTemplate].
class CheckedReplyWriter implements ReplyWriter {
  CheckedReplyWriter(this.model, {this.fallback = const TemplateReplyWriter()});

  final ReplyWriter model;
  final ReplyWriter fallback;

  @override
  String write(ReplyKind kind, Set<String> facts, {int seed = 0}) {
    try {
      final text = model.write(kind, facts, seed: seed);
      if (checkTemplate(text, facts)) return text;
    } on Object {
      // Fall through to the fixed sentences.
    }
    return fallback.write(kind, facts, seed: seed);
  }

  @override
  void close() {
    model.close();
    fallback.close();
  }
}

/// Fixed sentences, a few for each kind of reply.
class TemplateReplyWriter implements ReplyWriter {
  const TemplateReplyWriter();

  static const templates = <ReplyKind, List<String>>{
    ReplyKind.total: [
      'Across {count}.',
      'That came to {count}.',
      'Spread over {count}.',
    ],
    ReplyKind.totalUp: [
      'Across {count}. That is {change} more than {prev_period}.',
      '{count}, {change} more than {prev_period}.',
      'Across {count}, up {change} on {prev_period}.',
    ],
    ReplyKind.totalDown: [
      'Across {count}. That is {change} less than {prev_period}.',
      '{count}, {change} less than {prev_period}.',
      'Across {count}, down {change} on {prev_period}.',
    ],
    ReplyKind.nothing: [
      'Nothing here {period}.',
      'No payments like this {period}.',
      'Your records show none {period}.',
    ],
    ReplyKind.count: [
      '{count} {period}, {amount} in all.',
      'That is {count} {period}, adding up to {amount}.',
    ],
    ReplyKind.biggest: [
      'The biggest was to {payee} on {date}.',
      '{payee} on {date} was the largest.',
    ],
    ReplyKind.topPayees: [
      '{payee} got the most {period}.',
      'Most went to {payee} {period}.',
    ],
    ReplyKind.topCategories: [
      '{category} took the most {period}.',
      'Most went on {category} {period}.',
    ],
    ReplyKind.unsortedMost: [
      "Most of your spending {period}, {amount}, isn't sorted yet. Of what "
          'is sorted, {category} is the biggest at {top_amount}.',
    ],
    ReplyKind.unsortedTop: [
      "{amount} of your spending {period} isn't sorted yet, more than any "
          'one category. Of what is sorted, {category} is the biggest at '
          '{top_amount}.',
    ],
    ReplyKind.unsortedAll: [
      'None of your spending {period}, {amount}, is sorted yet. Once it '
          'is, I can tell you where it goes.',
    ],
    ReplyKind.trend: [
      'Highest in {date}. {period} so far: {change}.',
      'The top month was {date}. {period} so far: {change}.',
      'It peaked in {date}. {period} so far: {change}.',
    ],
    ReplyKind.compareUp: [
      'That is {change} more than {prev_period}.',
      'Up {change} on {prev_period}.',
    ],
    ReplyKind.compareDown: [
      'That is {change} less than {prev_period}.',
      'Down {change} on {prev_period}.',
    ],
    ReplyKind.compareSame: [
      'About the same as {prev_period}.',
      'Much like {prev_period}.',
    ],
    ReplyKind.spentFromNothing: [
      'You spent {amount} {period} and nothing in {prev_period}.',
    ],
    ReplyKind.spentToNothing: [
      'You spent nothing {period}, and {prev_amount} in {prev_period}.',
    ],
    ReplyKind.share: [
      '{count}, close to {percent} of your {category} spending.',
      '{count}, about {percent} of all {category}.',
    ],
    ReplyKind.safeToSpend: [
      'Safe to spend today, from your plan.',
      'What your plan leaves for today.',
      'Today, you can spend this and stay on plan.',
    ],
    ReplyKind.safeOver: [
      'Today is past the plan by {change}. Tomorrow starts fresh.',
      'Today has gone {change} past the plan. Tomorrow starts fresh.',
    ],
    ReplyKind.noBudget: [
      'Safe to spend shows once your plan has a day-to-day budget.',
      'Set a day-to-day budget in Plan, and this shows what is safe each day.',
    ],
    ReplyKind.balance: [
      'Across {count}, as your records show.',
      'What your {count} hold, from your records.',
    ],
    ReplyKind.accountBelow: ['{account} is {amount} below zero.'],
    ReplyKind.accountBelowFuliza: [
      '{account} is {amount} below zero once Fuliza is counted.',
    ],
    ReplyKind.accountOwesFuliza: [
      "{account} is {amount} below zero: that's what you owe Fuliza.",
    ],
    ReplyKind.accountEmpty: ['You have nothing left on {account}.'],
    ReplyKind.totalBelow: ["You're {amount} below zero across {count}."],
    ReplyKind.totalBelowFuliza: [
      "You're {amount} below zero once Fuliza is counted.",
    ],
    ReplyKind.totalEmpty: ['You have nothing left across {count}.'],
    ReplyKind.debts: [
      'Left to pay across {count}.',
      'Still to pay, across {count}.',
    ],
    ReplyKind.noDebts: [
      'No debts in your records. Well done.',
      'Your records show nothing left to pay.',
    ],
    ReplyKind.lent: [
      'Still to come back to you, from {count}.',
      'Owed back to you by {count}.',
    ],
    ReplyKind.owesMe: [
      'Owed to you by {count}.',
      'Waiting to come in from {count}.',
    ],
    ReplyKind.nobodyOwes: [
      'Nobody owes you money in your records.',
      'All paid up: nothing is owed to you.',
    ],
    ReplyKind.bills: [
      'Coming up: {count}. The next is {payee} on {date}.',
      '{count} to pay. {payee} is next, on {date}.',
    ],
    ReplyKind.noBills: [
      'No bills coming up in your plan.',
      'Your plan shows no bills ahead.',
    ],
    ReplyKind.subscriptions: [
      'A month across {count}.',
      'What {count} cost you each month.',
    ],
    ReplyKind.noSubscriptions: [
      'No subscriptions tracked yet.',
      'Nothing repeats that you track yet.',
    ],
    ReplyKind.goals: [
      'Saved so far across {count}.',
      'Put aside for {count} so far.',
    ],
    ReplyKind.noGoals: [
      'No goals yet. Add one in Goals.',
      'You have not set a goal yet.',
    ],
    ReplyKind.incomeSources: [
      'Most came from {payee} {period}.',
      '{payee} paid in the most {period}.',
    ],
    ReplyKind.ownTransfers: [
      '{account} sent {amount} to your other accounts {period}. That is your '
          'own money moving, so it is not counted as money in.',
    ],
    ReplyKind.noOwnTransfers: [
      '{account} sent nothing to your other accounts {period}, and money '
          'between your own accounts is not counted as money in.',
    ],
    ReplyKind.sales: [
      'From {count} {period}.',
      'Sales {period}, across {count}.',
    ],
    ReplyKind.topItems: [
      '{amount} from {count}.',
      'It brought in {amount} from {count}.',
    ],
    ReplyKind.fees: [
      'Paid in charges {period}, Fuliza included.',
      'What charges took {period}, with Fuliza.',
    ],
    ReplyKind.profit: [
      'Profit {period}, after costs.',
      'What is left {period} once costs are paid.',
    ],
    ReplyKind.loss: [
      'Costs ran past sales {period}.',
      'Costs were more than sales {period}.',
    ],
    ReplyKind.lowStock: [
      '{count} running low. {item} first.',
      '{count} to restock, starting with {item}.',
    ],
    ReplyKind.noLowStock: [
      'Nothing is running low.',
      'Stock looks good: nothing is low.',
    ],
    ReplyKind.notFound: [
      'I could not find {category} in this space. Try another name.',
      'Nothing in this space is called {category}. Try another word.',
    ],
    ReplyKind.clarify: ['Which {payee} do you mean?'],
    ReplyKind.cant: [
      'I can only answer from your records: what came in, what went out, '
          'bills, debts and goals.',
    ],
    ReplyKind.hi: [
      'Hello. Ask me about your money.',
      'Hi. What would you like to know about your money?',
    ],
    ReplyKind.thanks: ['You are welcome.', 'Glad to help.'],
    ReplyKind.bye: ['Bye for now.', 'See you soon.'],
    ReplyKind.help: [
      'Ask about spending, money in, people you pay, bills, debts, goals '
          'or what is safe to spend.',
    ],
  };

  @override
  String write(ReplyKind kind, Set<String> facts, {int seed = 0}) {
    final options = [
      for (final t in templates[kind] ?? const <String>[])
        if (checkTemplate(t, facts)) t,
    ];
    if (options.isEmpty) return '';
    return options[seed.abs() % options.length];
  }

  @override
  void close() {}
}
