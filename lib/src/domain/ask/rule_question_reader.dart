import '../time/calendar.dart';
import 'matcher.dart';
import 'periods.dart';
import 'understanding.dart';

/// Reads questions with keyword rules: English first, with some Swahili and
/// Sheng. Good enough to work alone; a trained reader can replace it behind
/// [QuestionReader].
class RuleQuestionReader implements QuestionReader {
  RuleQuestionReader({CalendarDate Function()? today})
    : _today = today ?? CalendarDate.today;

  final CalendarDate Function() _today;

  // Order matters: the first rule that fits wins.
  static final _intents = <(RegExp, AskIntent)>[
    (
      RegExp(
        r'^(?:hi|hello|hey|habari|niaje|sasa|mambo|good (?:morning|afternoon|evening))\b',
      ),
      AskIntent.hi,
    ),
    (
      RegExp(r'^(?:thanks|thank you|asante|thx|cheers|nice|great|ok thanks)\b'),
      AskIntent.thanks,
    ),
    (
      RegExp(r'^(?:bye|goodbye|see you|kwaheri|later|that is all|done)\b'),
      AskIntent.bye,
    ),
    (
      RegExp(
        r'^(?:help|what can (?:i|you) ask|what can you do|how does this work|saidia)\b',
      ),
      AskIntent.help,
    ),
    (
      RegExp(
        r'\bshould i\b|\bwould you\b|\badvi[cs]e\b|\binvest\b|\bweather\b|'
        r'\bjoke\b|\bpresident\b|\bnews\b|\bbuy a (?:car|house|plot)\b|'
        r'\bbest bank\b|\brecommend\b|\bstock market\b|\bcrypto\b',
      ),
      AskIntent.outOfScope,
    ),
    (
      RegExp(
        r'\bsafe to spend\b|\bcan i (?:still )?spend\b|\bhow much can i\b|'
        r'\bleft (?:to spend|for today)\b|\bdaily limit\b|\bnaweza kutumia\b',
      ),
      AskIntent.safeToSpend,
    ),
    (
      RegExp(
        r'\bowes? me\b|\bowe(?:s)? us\b|\bwho owes\b|\bcustomers? owe\b|'
        r'\bon credit\b|\bwananidai\b|\bnadai\b',
      ),
      AskIntent.whoOwesMe,
    ),
    (
      RegExp(r'\b(?:i )?lent\b|\bnilikopesha\b|\bborrowed from me\b'),
      AskIntent.lent,
    ),
    (
      RegExp(
        r'\bbalance\b|\bhow much (?:money )?do i have\b|\bsalio\b|'
        r'\bmoney (?:do i have|is left|i have)\b|\bin my accounts?\b',
      ),
      AskIntent.balance,
    ),
    (
      RegExp(
        r'\bi (?:still )?owe\b|\bdebts?\b|\bdeni\b|\bloans?\b|'
        r'\bfuliza\b|\bnadaiwa\b|\bowe\b',
      ),
      AskIntent.debts,
    ),
    (
      RegExp(r'\bbills?\b|\bdue\b|\bcoming up\b|\bto pay next\b|\bupcoming\b'),
      AskIntent.billsDue,
    ),
    (
      RegExp(r'\bsubscriptions?\b|\brecurring\b|\brepeats?\b|\bsubscribed\b'),
      AskIntent.subscriptions,
    ),
    (
      RegExp(r'\bgoals?\b|\bsaving for\b|\btarget\b|\bnear (?:my )?goal\b'),
      AskIntent.goals,
    ),
    (
      RegExp(
        r'\blow stock\b|\brunning (?:low|out)\b|\brestock\b|'
        r'\bout of stock\b|\bstock is low\b|\bimeisha\b',
      ),
      AskIntent.lowStock,
    ),
    (
      RegExp(
        r'\bsold (?:the )?most\b|\bbest sell|\btop (?:items|products|sellers)\b|'
        r'\bwhat (?:sold|sells)\b|\bmost popular\b|\bselling best\b',
      ),
      AskIntent.topItems,
    ),
    (RegExp(r'\bprofits?\b|\bfaida\b|\bmake a profit\b'), AskIntent.profit),
    (
      RegExp(r'\bsales\b|\bsold\b|\bmauzo\b|\btakings\b|\bnimeuza\b'),
      AskIntent.sales,
    ),
    (
      RegExp(
        r'\bincome (?:come|comes) from\b|\bsources? of (?:income|money)\b|'
        r'\bincome sources?\b|\bwho pays me\b|\bwhere does my (?:money|income) come from\b',
      ),
      AskIntent.incomeSources,
    ),
    (
      RegExp(
        r'\bwhere does my money go\b|\btop categories\b|'
        r'\bspend (?:the )?most on\b|\bbiggest categor|\bwhat do i spend on\b|'
        r'\bwhere did (?:my )?money go\b|\bpesa inaenda wapi\b',
      ),
      AskIntent.topCategories,
    ),
    (
      RegExp(
        r'\bwho do i (?:pay|send)\b|\btop payees\b|\bwho did i (?:pay|send)\b|'
        r'\b(?:pay|send|sent|paid) (?:to )?the most\b|\bwho gets most\b',
      ),
      AskIntent.topPayees,
    ),
    (
      RegExp(r'\bbiggest\b|\blargest\b|\bmost expensive\b|\bhighest payment\b'),
      AskIntent.biggestPayment,
    ),
    (
      RegExp(r'\bhow many\b|\bhow often\b|\bmara ngapi\b|\bnumber of\b'),
      AskIntent.countPayments,
    ),
    (
      RegExp(
        r'\bchang(?:ed|e|ing)\b|\btrend\b|\bover time\b|\beach month\b|'
        r'\bevery month\b|\bmonth by month\b|\bby month\b|\bgoing (?:up|down)\b|'
        r'\bper month\b|\bmonthly\b',
      ),
      AskIntent.trend,
    ),
    (
      RegExp(
        r'\bcompare\b|\bcompared\b|\bvs\b|\bversus\b|\bthan (?:last|the)\b|'
        r'\bmore or less\b',
      ),
      AskIntent.compare,
    ),
    (
      RegExp(
        r'\bsent to\b|\bsend to\b|\bsent\b|\bnimetuma\b|\bnilituma\b|'
        r'\btransfer(?:red)? to\b|\bgave\b',
      ),
      AskIntent.sentTo,
    ),
    (
      RegExp(
        r'\breceived from\b|\bgot from\b|\bpaid me\b|\bsent me\b|'
        r'\bnimepokea kutoka\b',
      ),
      AskIntent.receivedFrom,
    ),
    (
      RegExp(
        r'\breceived?\b|\bcame in\b|\bcome in\b|\bgot paid\b|\bearn(?:ed)?\b|'
        r'\bincome\b|\bnimepokea\b|\bmoney in\b|\bpaid in\b|\bsalary\b|\bmshahara\b',
      ),
      AskIntent.received,
    ),
    (
      RegExp(
        r'\bspen[dt]\b|\bspending\b|\bpa(?:y|id)\b|\bnimetumia\b|'
        r'\bnilitumia\b|\bcost\b|\bbought\b|\bbuy\b|\bused\b|\bdoh\b|'
        r'\bpesa\b|\bexpenses?\b|\bpayments?\b|\bhow much\b|\bngapi\b|\bout\b',
      ),
      AskIntent.spent,
    ),
  ];

  static final _refineStart = RegExp(
    r'^(?:and|but|what about|how about|only|just|na|then|also|ok and|same for)\b',
  );

  static const _stop = {
    'this',
    'last',
    'in',
    'on',
    'for',
    'and',
    'did',
    'do',
    'i',
    'my',
    'the',
    'how',
    'much',
    'many',
    'what',
    'was',
    'is',
    'are',
    'so',
    'far',
    'me',
    'to',
    'from',
    'at',
    'with',
    'of',
    'a',
    'an',
    'times',
    'payments',
    'spend',
    'spent',
    'spending',
    'pay',
    'paid',
    'send',
    'sent',
    'only',
    'just',
    'since',
    'over',
    'past',
    'month',
    'week',
    'year',
    'today',
    'it',
    'has',
    'have',
    'been',
    'changed',
    'change',
    'compare',
    'compared',
    'vs',
    'than',
    'total',
    'all',
    'money',
    'pesa',
    'doh',
    'by',
    'each',
    'every',
    'nimetumia',
    'nimetuma',
    'kwa',
    'ya',
    'za',
    'la',
    'wa',
    'about',
    'there',
    'that',
    'those',
    'these',
    'when',
    'where',
    'who',
    'which',
    'any',
    'buy',
    'bought',
    'got',
    'get',
    'received',
    'receive',
    'came',
    'come',
    'mpesa',
    'please',
    'tell',
    'show',
    'give',
    'between',
    'before',
    'after',
  };

  static final _entityAfter = <(RegExp, SlotKind)>[
    (
      RegExp(r"\b(?:to|pay|paid|sent|send|tuma|gave)\s+([a-z0-9' &.-]+)"),
      SlotKind.payee,
    ),
    (
      RegExp(r"\b(?:from|kutoka|at|with|kwa)\s+([a-z0-9' &.-]+)"),
      SlotKind.payee,
    ),
    (RegExp(r"\b(?:on|for|kwa)\s+([a-z0-9' &.-]+)"), SlotKind.category),
    (RegExp(r"\b(?:of|sold|sell|uza)\s+([a-z0-9' &.-]+)"), SlotKind.item),
    (
      RegExp(r"\b([a-z0-9' &.-]+?)\s+(?:spending|expenses|costs|bills?)\b"),
      SlotKind.category,
    ),
  ];

  static final _account = RegExp(
    r'\b(?:my |the |on |in |from )?([a-z0-9-]+(?: [a-z0-9]+)?) account\b',
  );

  static final _amount = RegExp(
    r'\b(?:over|above|more than|bigger than|at least)\s+(?:kes\s*|ksh\s*)?([0-9][0-9,]*)',
  );

  @override
  Understanding read(String question) {
    final raw = question.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final spans = <AskSpan>[];
    var text = raw;

    final period = findPeriod(raw, _today());
    if (period != null) {
      spans.add(
        AskSpan(SlotKind.period, period.text.trim(), period.start, period.end),
      );
      text = text.replaceRange(
        period.start,
        period.end,
        ' ' * (period.end - period.start),
      );
    }
    final amount = _amount.firstMatch(text);
    if (amount != null) {
      spans.add(
        AskSpan(SlotKind.amount, amount.group(1)!, amount.start, amount.end),
      );
      text = text.replaceRange(
        amount.start,
        amount.end,
        ' ' * (amount.end - amount.start),
      );
    }
    final clean = text
        .replaceAll(RegExp(r"[^a-z0-9' &.-]"), ' ')
        .replaceAll(RegExp(' +'), ' ')
        .trim();

    var intent = AskIntent.outOfScope;
    var confidence = 0.4;
    for (final (pattern, i) in _intents) {
      if (pattern.hasMatch(clean)) {
        intent = i;
        confidence = 0.85;
        break;
      }
    }
    // Small talk only when it is all the question says.
    if (intent.isSmallTalk && clean.split(' ').length > 4) {
      intent = AskIntent.outOfScope;
      for (final (pattern, i) in _intents.skip(4)) {
        if (pattern.hasMatch(clean)) {
          intent = i;
          break;
        }
      }
    }

    if (!intent.isSmallTalk && intent != AskIntent.help) {
      spans.addAll(_entities(clean, raw, intent));
    }

    final refines = _refineStart.hasMatch(clean);
    final words = clean.isEmpty ? 0 : clean.split(' ').length;
    final onlySlots =
        intent == AskIntent.spent &&
        !RegExp(
          r'\b(?:spen[dt]|spending|pa(?:y|id)|cost|bought|how much|'
          r'nimetumia|ngapi)\b',
        ).hasMatch(clean);
    if ((refines && (intent == AskIntent.outOfScope || onlySlots)) ||
        (intent == AskIntent.outOfScope && words <= 3 && spans.isNotEmpty) ||
        (clean.isEmpty && period != null)) {
      intent = AskIntent.refine;
      confidence = 0.8;
    }
    return Understanding(intent, confidence: confidence, spans: spans);
  }

  List<AskSpan> _entities(String clean, String raw, AskIntent intent) {
    final found = <AskSpan>[];
    final taken = <String>{};
    void add(SlotKind kind, String words) {
      final name = _trim(words);
      if (name.isEmpty || taken.contains(name)) return;
      taken.add(name);
      final at = raw.indexOf(name);
      found.add(
        AskSpan(kind, name, at < 0 ? 0 : at, at < 0 ? 0 : at + name.length),
      );
    }

    final account = _account.firstMatch(clean);
    if (account != null) add(SlotKind.account, account.group(1)!);

    for (final (pattern, kind) in _entityAfter) {
      for (final m in pattern.allMatches(clean)) {
        var k = kind;
        if (intent == AskIntent.sales ||
            intent == AskIntent.topItems ||
            intent == AskIntent.lowStock) {
          k = SlotKind.item;
        }
        add(k, m.group(1)!);
      }
    }
    // A known category word anywhere: "fare", "chakula".
    for (final word in clean.split(' ')) {
      if (!categorySynonyms.containsKey(word)) continue;
      final at = found.indexWhere((s) => s.text == word);
      if (at >= 0) {
        final s = found[at];
        found[at] = AskSpan(SlotKind.category, s.text, s.start, s.end);
      } else if (!found.any((s) => s.text.split(' ').contains(word))) {
        add(SlotKind.category, word);
      }
    }
    // "and only Naivas?": what is left is the name.
    if (found.isEmpty && _refineStart.hasMatch(clean)) {
      final rest = clean.replaceFirst(_refineStart, '');
      add(SlotKind.payee, rest);
    }
    return found;
  }

  /// The name part of [words]: from the first word that is not a stop word
  /// up to the next stop word.
  static String _trim(String words) {
    final out = <String>[];
    for (final w in words.trim().split(' ')) {
      final word = w.replaceAll(RegExp(r"^[.'&-]+|[.'&-]+$"), '');
      if (word.isEmpty) continue;
      if (_stop.contains(word)) {
        if (out.isEmpty) continue;
        break;
      }
      out.add(word);
      if (out.length == 4) break;
    }
    return out.join(' ');
  }

  @override
  void close() {}
}
