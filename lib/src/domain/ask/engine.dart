import '../../core/money/money.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import '../spaces/space.dart';
import '../time/calendar.dart';
import 'answer.dart';
import 'context.dart';
import 'data_source.dart';
import 'matcher.dart';
import 'model_reply_writer.dart';
import 'periods.dart';
import 'reply_writer.dart';
import 'understanding.dart';

/// One question and what came of it.
class AskTurn {
  const AskTurn(this.understanding, this.context, this.answer);

  final Understanding understanding;
  final AskContext context;
  final AskAnswer answer;
}

/// Rows shown under an answer before "See all".
const askRowsShown = 3;

/// Names a reply lists at most; with more, the writer is not asked to list.
const _listMax = 5;

/// Turns questions into lookups on one space's records and the lookups
/// into answers. Reads only through [source], so it never sees another
/// space.
class AskEngine {
  AskEngine({
    required this.source,
    required this.reader,
    this.writer = const TemplateReplyWriter(),
    this.wording,
    this.spaceKind = SpaceKind.personal,
  });

  final AskDataSource source;
  final QuestionReader reader;

  /// The template sentences, always there.
  final ReplyWriter writer;

  /// The trained writer, when it loaded. It words a reply from the same
  /// facts; when it cannot, [writer]'s sentence stays.
  final ModelReplyWriter? wording;
  final SpaceKind spaceKind;

  bool get _sells =>
      spaceKind == SpaceKind.business || spaceKind == SpaceKind.farm;

  /// Questions to try on an empty conversation.
  List<String> get starters => _sells
      ? const [
          'What sold most this week?',
          'How much did I sell today?',
          'Profit this month',
          'Who owes me?',
        ]
      : const [
          'How much did I spend on food last month?',
          'How much came in this week?',
          'What is safe to spend?',
          'How much do I still owe?',
        ];

  /// Reads [question], merges it into [context] and answers it.
  Future<AskTurn> ask(
    String question, {
    required AskContext context,
    required DateTime now,
  }) async {
    final today = CalendarDate.local(now);
    final understanding = reader.read(question);
    final seed = question.hashCode;
    final intent = understanding.intent;

    if (!intent.isLookup && intent != AskIntent.refine) {
      return AskTurn(
        understanding,
        context,
        await _plain(_plainKind(intent), now, seed),
      );
    }
    if (intent == AskIntent.refine &&
        (context.isEmpty || context.expired(now))) {
      // Nothing to refine: answer the words as a fresh spending question.
      return ask(
        question,
        context: AskContext(intent: AskIntent.spent, at: now),
        now: now,
      );
    }

    final entities = await source.entities();
    final matcher = EntityMatcher(
      entities,
      shortcuts: await source.shortcuts(),
    );
    final named = <SlotKind, AskEntity>{};
    String? missing;
    for (final span in understanding.spans) {
      if (span.kind == SlotKind.period || span.kind == SlotKind.amount) {
        continue;
      }
      // "How much did KCB send me?": money from one of the person's own
      // accounts, named exactly, is that account, not a payee.
      final own = intent == AskIntent.receivedFrom
          ? _ownAccount(entities, span.text)
          : null;
      final result = own != null
          ? Matched(own)
          : matcher.match(span.text, _kindsFor(span.kind, intent));
      switch (result) {
        case Matched(:final entity):
          named.putIfAbsent(entity.kind, () => entity);
        case Ambiguous(:final candidates):
          final period = understanding.span(SlotKind.period);
          final merged = context.merge(
            intent: intent,
            named: named,
            period: period == null ? null : parsePeriod(period.text, today),
            now: now,
          );
          return AskTurn(
            understanding,
            merged,
            await _clarify(span.text, candidates, merged, now, seed),
          );
        case NoMatch():
          missing ??= span.text;
      }
    }

    final periodSpan = understanding.span(SlotKind.period);
    final merged = context.merge(
      intent: intent,
      named: named,
      period: periodSpan == null ? null : parsePeriod(periodSpan.text, today),
      now: now,
    );
    if (missing != null &&
        named.isEmpty &&
        _namesSomething(merged.intent ?? AskIntent.spent)) {
      final facts = <String, Object>{'category': _title(missing)};
      return AskTurn(
        understanding,
        merged,
        AskAnswer(
          kind: ReplyKind.notFound,
          template: writer.write(
            ReplyKind.notFound,
            facts.keys.toSet(),
            seed: seed,
          ),
          facts: facts,
          asOf: now,
          suggestions: starters.take(3).toList(),
        ),
      );
    }
    return AskTurn(understanding, merged, await run(merged, now, seed: seed));
  }

  /// Answers [clarify] with the person's [choice], or all its choices
  /// together when null, for [period] when given.
  Future<AskTurn> resolve(
    AskAnswer clarify, {
    required AskEntity? choice,
    AskPeriod? period,
    required DateTime now,
  }) async {
    final entity = choice ?? both(clarify.choices);
    var context = clarify.context.withEntity(entity, now);
    if (period != null) context = context.withPeriod(period, now);
    final answer = await run(context, now, seed: entity.key.hashCode);
    return AskTurn(
      Understanding(context.intent ?? AskIntent.spent),
      context,
      answer,
    );
  }

  /// [choices] as one, added together.
  static AskEntity both(List<AskEntity> choices) => AskEntity(
    choices.first.kind,
    [for (final c in choices) c.key].join('|'),
    _joinNames([for (final c in choices) c.name]),
  );

  /// Works out [context]'s numbers afresh.
  Future<AskAnswer> run(
    AskContext context,
    DateTime now, {
    int seed = 0,
  }) async {
    final today = CalendarDate.local(now);
    final intent = context.intent ?? AskIntent.spent;
    final q = _Query(context, today, now, seed);
    return switch (intent) {
      AskIntent.spent => _total(q, _Flow.spent),
      AskIntent.receivedFrom
          when context.entities.containsKey(SlotKind.account) &&
              !context.entities.containsKey(SlotKind.payee) =>
        _fromOwnAccount(q),
      AskIntent.received || AskIntent.receivedFrom => _total(q, _Flow.received),
      AskIntent.sentTo => _total(q, _Flow.sent),
      AskIntent.countPayments => _count(q),
      AskIntent.biggestPayment => _biggest(q),
      AskIntent.topPayees => _topPayees(q),
      AskIntent.topCategories => _topCategories(q),
      AskIntent.trend => _trend(q),
      AskIntent.compare => _compare(q),
      AskIntent.billsDue => _bills(q),
      AskIntent.subscriptions => _subscriptions(q),
      AskIntent.debts => _debts(q),
      AskIntent.lent => _lent(q),
      AskIntent.whoOwesMe => _owesMe(q),
      AskIntent.safeToSpend => _safe(q),
      AskIntent.balance => _balance(q),
      AskIntent.goals => _goals(q),
      AskIntent.incomeSources => _incomeSources(q),
      AskIntent.sales => _sales(q),
      AskIntent.topItems => _topItems(q),
      AskIntent.profit => _profit(q),
      AskIntent.lowStock => _lowStock(q),
      AskIntent.fees => _fees(q),
      _ => _plain(ReplyKind.cant, now, seed),
    };
  }

  // ---- Small talk and limits ----

  ReplyKind _plainKind(AskIntent intent) => switch (intent) {
    AskIntent.hi => ReplyKind.hi,
    AskIntent.thanks => ReplyKind.thanks,
    AskIntent.bye => ReplyKind.bye,
    AskIntent.help => ReplyKind.help,
    _ => ReplyKind.cant,
  };

  Future<AskAnswer> _plain(ReplyKind kind, DateTime now, int seed) => _word(
    AskAnswer(
      kind: kind,
      template: writer.write(kind, const {}, seed: seed),
      asOf: now,
      suggestions: kind == ReplyKind.cant
          ? (_sells
                ? const ['Profit this week', 'Who owes me?', 'Low stock']
                : const [
                    'How much do I save a month?',
                    'What is safe to spend?',
                    'How much do I owe?',
                  ])
          : starters.take(3).toList(),
    ),
    switch (kind) {
      ReplyKind.hi => const WriterFacts('hi'),
      ReplyKind.thanks => const WriterFacts('thanks'),
      ReplyKind.bye => const WriterFacts('bye'),
      ReplyKind.help => const WriterFacts('help'),
      ReplyKind.cant => const WriterFacts('out_of_scope'),
      _ => null,
    },
    seed,
  );

  /// [answer] worded by the trained writer from [words], when it can.
  Future<AskAnswer> _word(
    AskAnswer answer,
    WriterFacts? words,
    int seed,
  ) async {
    final model = wording;
    if (model == null || words == null) return answer;
    final template = await model.word(words, answer.facts, seed: seed);
    return template == null ? answer : answer.withTemplate(template);
  }

  Future<AskAnswer> _clarify(
    String word,
    List<AskEntity> candidates,
    AskContext context,
    DateTime now,
    int seed,
  ) async {
    final today = CalendarDate.local(now);
    final period = context.period ?? _defaultPeriod(context.intent, today);
    final entries = await source.entries(
      today.addDays(-365).startInstant,
      today.addDays(1).startInstant,
    );
    final sent =
        context.intent == AskIntent.received ||
            context.intent == AskIntent.receivedFrom
        ? 'Received'
        : 'Sent';
    final choices = [
      for (final c in candidates.take(5))
        AskEntity(
          c.kind,
          c.key,
          c.name,
          detail: c.kind == SlotKind.payee
              ? '$sent ${_times(entries.where((e) => _isPayee(e, c.key)).length)}'
              : null,
        ),
    ];
    final facts = <String, Object>{'payee': _title(word)};
    return AskAnswer(
      kind: ReplyKind.clarify,
      template: writer.write(ReplyKind.clarify, facts.keys.toSet(), seed: seed),
      facts: facts,
      asOf: now,
      choices: choices,
      clarifyWord: word,
      askPeriod: context.period == null,
      context: context.period == null
          ? context.withPeriod(period, now)
          : context,
    );
  }

  // ---- Money moving ----

  Future<AskAnswer> _total(_Query q, _Flow flow) async {
    final period = q.period(AskPeriod.thisMonth(q.today));
    final prev = period.previous();
    final all = await source.entries(prev.fromInstant, period.toInstant);
    final now = _filter(all, q.context, flow, period);
    final before = _filter(all, q.context, flow, prev);
    final amount = _sum(now);
    final headline = _headline(q.context, period, q.today, flow);
    final named = _named(q.context);
    if (now.isEmpty) {
      return _answer(
        q,
        ReplyKind.nothing,
        {'period': period.phrase(q.today), ...named},
        words: _nodata(named),
        headline: headline,
        figure: 0,
        suggestions: _followUps(q, period),
      );
    }
    final change = amount - _sum(before);
    final kind = before.isEmpty || change == 0
        ? ReplyKind.total
        : (change > 0 ? ReplyKind.totalUp : ReplyKind.totalDown);
    final byWho = q.context.entities.containsKey(SlotKind.payee)
        ? _byCategory(now, await _names(SlotKind.category))
        : _byPayee(now);
    final share = await _share(q, now, period, flow);
    return _answer(
      q,
      share != null ? ReplyKind.share : kind,
      {
        ...named,
        'count': _payments(now.length),
        'number': '${now.length}',
        'amount': amount,
        'period': period.phrase(q.today),
        if (kind != ReplyKind.total) 'change': change.abs(),
        if (kind != ReplyKind.total)
          'prev_period': _prevPhrase(period, q.today),
        if (kind != ReplyKind.total) 'prev_amount': _sum(before),
        if (share != null) ...{
          'percent': _percentWord(share.partPercent),
          'category': q.context.entities[SlotKind.category]!.name.toLowerCase(),
        },
      },
      // A payee's share of a category has no writer kind; its chart says it.
      words: share != null ? null : _totalWords(flow, kind, named, now.length),
      headline: headline,
      figure: amount,
      rows: share == null ? byWho.take(askRowsShown).toList() : const [],
      totalRows: share == null ? byWho.length : now.length,
      chart: share,
      link: AskLink.activity,
      suggestions: _followUps(q, period, only: byWho.firstOrNull?.title),
    );
  }

  /// What one of the person's own accounts moved into their others. That
  /// is never money in, so the reply says which it is.
  Future<AskAnswer> _fromOwnAccount(_Query q) async {
    final period = q.period(AskPeriod.thisMonth(q.today));
    final account = q.context.entities[SlotKind.account]!;
    final all = await source.entries(period.fromInstant, period.toInstant);
    final moved = [
      for (final e in all)
        if (e.currency == BaseCurrency.code &&
            period.contains(e.date) &&
            e.isOutflow &&
            roleOf(e) == LedgerRole.ownTransfer &&
            _isKey(account.key, 'a', e.accountId))
          e,
    ];
    final names = await _names(SlotKind.account);
    final byId = {for (final e in all) e.id: e};
    final into = <String, (int, int)>{};
    for (final e in moved) {
      final to = e.transferAccountId ?? byId[e.transferPairId]?.accountId;
      final name = names[to] ?? 'Your other accounts';
      final (sum, n) = into[name] ?? (0, 0);
      into[name] = (sum + e.amountMinor, n + 1);
    }
    final rows = [
      for (final MapEntry(:key, value: (sum, n)) in into.entries)
        AskRow(key, detail: _plural(n, 'transfer'), amountMinor: sum),
    ]..sort((a, b) => b.amountMinor!.compareTo(a.amountMinor!));
    final amount = _sum(moved);
    return _answer(
      q,
      moved.isEmpty ? ReplyKind.noOwnTransfers : ReplyKind.ownTransfers,
      {
        'account': account.name,
        'amount': amount,
        'period': period.phrase(q.today),
        'count': _plural(moved.length, 'transfer'),
      },
      headline:
          '${account.name} to your other accounts · '
          '${period.label(q.today)}',
      figure: amount,
      rows: rows.take(askRowsShown).toList(),
      totalRows: rows.length,
      link: AskLink.activity,
      suggestions: _followUps(q, period),
    );
  }

  /// The account in [entities] whose name is exactly [text], if any.
  static AskEntity? _ownAccount(List<AskEntity> entities, String text) {
    final name = normaliseName(text);
    if (name.isEmpty) return null;
    for (final e in entities) {
      if (e.kind == SlotKind.account && normaliseName(e.name) == name) {
        return e;
      }
    }
    return null;
  }

  /// The payee's part of the category, when both are asked.
  Future<AskChart?> _share(
    _Query q,
    List<LedgerEntry> part,
    AskPeriod period,
    _Flow flow,
  ) async {
    final category = q.context.entities[SlotKind.category];
    final payee = q.context.entities[SlotKind.payee];
    if (category == null || payee == null) return null;
    final whole = _filter(
      await source.entries(period.fromInstant, period.toInstant),
      q.context.without(SlotKind.payee, q.now),
      flow,
      period,
    );
    final wholeMinor = _sum(whole);
    if (wholeMinor <= 0) return null;
    return AskChart.share(
      partMinor: _sum(part),
      wholeMinor: wholeMinor,
      partLabel: payee.name,
      restLabel: 'Other ${category.name.toLowerCase()}',
    );
  }

  Future<AskAnswer> _count(_Query q) async {
    final period = q.period(AskPeriod.thisMonth(q.today));
    final flow = _flowOf(q.context);
    final entries = _filter(
      await source.entries(period.fromInstant, period.toInstant),
      q.context,
      flow,
      period,
    );
    final named = _named(q.context);
    return _answer(
      q,
      entries.isEmpty ? ReplyKind.nothing : ReplyKind.count,
      {
        ...named,
        'count': _times(entries.length),
        'number': '${entries.length}',
        'period': period.phrase(q.today),
        'amount': _sum(entries),
      },
      words: entries.isEmpty
          ? _nodata(named)
          // "You paid Naivas 3 times": money out only.
          : flow == _Flow.received
          ? null
          : WriterFacts(
              'count_payments',
              flags: {if (entries.length == 1) 'count=one'},
              given: {'count', 'period', 'amount', ...named.keys},
            ),
      headline: _headline(q.context, period, q.today, flow),
      figureText: _times(entries.length, capital: true),
      rows: _byPayee(entries).take(askRowsShown).toList(),
      totalRows: _byPayee(entries).length,
      link: AskLink.activity,
      suggestions: _followUps(q, period),
    );
  }

  Future<AskAnswer> _biggest(_Query q) async {
    final period = q.period(AskPeriod.thisMonth(q.today));
    final flow = _flowOf(q.context);
    final entries = _filter(
      await source.entries(period.fromInstant, period.toInstant),
      q.context,
      flow,
      period,
    )..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    final named = _named(q.context);
    if (entries.isEmpty) {
      return _answer(
        q,
        ReplyKind.nothing,
        {'period': period.phrase(q.today), ...named},
        words: _nodata(named),
        headline: _headline(q.context, period, q.today, flow),
      );
    }
    final top = entries.first;
    final date = _day(top.date, q.today);
    return _answer(
      q,
      ReplyKind.biggest,
      {
        ...named,
        'payee': _payeeName(top),
        'date': date,
        'amount': top.amountMinor,
        'period': period.phrase(q.today),
      },
      // "Your biggest payment was ... to Naivas": money out only.
      words: flow == _Flow.received
          ? null
          : WriterFacts(
              'biggest_payment',
              given: {
                'amount',
                'payee',
                'period',
                if (named.containsKey('category')) 'category',
                // "on 14 Nov", not "on today".
                if (_startsWithDigit(date)) 'date',
              },
            ),
      headline: _headline(q.context, period, q.today, flow),
      figure: top.amountMinor,
      rows: [
        for (final e in entries.skip(1).take(askRowsShown))
          AskRow(
            _payeeName(e),
            detail: _day(e.date, q.today),
            amountMinor: e.amountMinor,
          ),
      ],
      totalRows: entries.length - 1,
      link: AskLink.activity,
      suggestions: _followUps(q, period),
    );
  }

  Future<AskAnswer> _topPayees(_Query q) async {
    final period = q.period(AskPeriod.thisMonth(q.today));
    final flow = _flowOf(q.context);
    final entries = _filter(
      await source.entries(period.fromInstant, period.toInstant),
      q.context,
      flow,
      period,
    );
    final rows = _byPayee(entries);
    if (rows.isEmpty) {
      return _answer(q, ReplyKind.nothing, {
        'period': period.phrase(q.today),
      }, words: _nodata(const {}));
    }
    final top = rows.take(askRowsShown).toList();
    return _answer(
      q,
      ReplyKind.topPayees,
      {
        'payee': rows.first.title,
        'period': period.phrase(q.today),
        'list': _joinNames([for (final r in top) r.title]),
      },
      words: WriterFacts(
        flow == _Flow.received ? 'income_sources' : 'top_payees',
        flags: {if (top.length == 1) 'count=one'},
        given: const {'list', 'payee', 'period'},
      ),
      headline: _headline(q.context, period, q.today, flow),
      figure: rows.first.amountMinor,
      rows: rows.take(askRowsShown + 2).toList(),
      totalRows: rows.length,
      link: AskLink.activity,
      suggestions: _followUps(q, period),
    );
  }

  Future<AskAnswer> _topCategories(_Query q) async {
    final period = q.period(AskPeriod.thisMonth(q.today));
    final entries = _filter(
      await source.entries(period.fromInstant, period.toInstant),
      q.context,
      _Flow.spent,
      period,
    );
    final rows = _byCategory(entries, await _names(SlotKind.category));
    if (rows.isEmpty) {
      return _answer(q, ReplyKind.nothing, {
        'period': period.phrase(q.today),
      }, words: _nodata(const {}));
    }
    final total = _sum(entries);
    final sorted = [
      for (final r in rows)
        if (r.title != _notSorted) r,
    ];
    final unsorted = rows.first.title == _notSorted ? rows.first : null;
    if (unsorted != null) {
      // "Not sorted yet" is no category: say how much is waiting, and name
      // the biggest one there is. The writer would name it as a category.
      final top = sorted.firstOrNull;
      return _answer(
        q,
        top == null
            ? ReplyKind.unsortedAll
            : unsorted.amountMinor! * 2 > total
            ? ReplyKind.unsortedMost
            : ReplyKind.unsortedTop,
        {
          'amount': unsorted.amountMinor!,
          'period': period.phrase(q.today),
          'category': ?top?.title,
          'top_amount': ?top?.amountMinor,
        },
        headline: 'Spending · ${period.label(q.today)}',
        figure: total,
        rows: rows.take(askRowsShown + 2).toList(),
        totalRows: rows.length,
        link: AskLink.insights,
        suggestions: _followUps(q, period),
      );
    }
    final top = sorted.take(askRowsShown).toList();
    return _answer(
      q,
      ReplyKind.topCategories,
      {
        'category': rows.first.title,
        'period': period.phrase(q.today),
        // Real categories only: "Not sorted yet" is not one to list.
        'list': _joinNames([for (final r in top) r.title]),
      },
      words: WriterFacts(
        'top_categories',
        flags: {if (top.length == 1) 'count=one'},
        given: const {'list', 'category', 'period'},
      ),
      headline: 'Spending · ${period.label(q.today)}',
      figure: total,
      rows: rows.take(askRowsShown + 2).toList(),
      totalRows: rows.length,
      link: AskLink.insights,
      suggestions: _followUps(q, period),
    );
  }

  Future<AskAnswer> _trend(_Query q) async {
    final period = q.period(AskPeriod.thisYear(q.today));
    final flow = _flowOf(q.context);
    final entries = _filter(
      await source.entries(period.fromInstant, period.toInstant),
      q.context,
      flow,
      period,
    );
    final months = period.months;
    final totals = {for (final m in months) m: 0};
    for (final e in entries) {
      final m = e.date.yearMonth;
      if (totals.containsKey(m)) totals[m] = totals[m]! + e.amountMinor;
    }
    final ranked = [...months]
      ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
    final peaks = ranked.take(2).where((m) => totals[m]! > 0).toSet();
    final latest = months.last;
    final headline =
        '${_headline(q.context, period, q.today, flow)}'
        ' · thousands of ${BaseCurrency.code}';
    if (entries.isEmpty) {
      return _answer(
        q,
        ReplyKind.nothing,
        {'period': period.phrase(q.today)},
        words: _nodata(const {}),
        headline: headline,
        figure: 0,
      );
    }
    // The trend's sentence names its peak months, which the writer's trend
    // kind does not take: it keeps its template.
    return _answer(
      q,
      ReplyKind.trend,
      {
        'date': _joinNames(
          [
            for (final m in months)
              if (peaks.contains(m) && m != latest) _monthNames[m.month - 1],
          ].ifEmpty(_monthNames[ranked.first.month - 1]),
        ),
        'period': _monthNames[latest.month - 1],
        'change': totals[latest]!,
      },
      headline: headline,
      figure: _sum(entries),
      chart: AskChart.bars([
        for (final m in months)
          AskBar(
            _monthNames[m.month - 1].substring(0, 1),
            totals[m]!,
            highlight: peaks.contains(m),
          ),
      ]),
      totalRows: entries.length,
      link: AskLink.activity,
      suggestions: ['Compare with last year'],
    );
  }

  Future<AskAnswer> _compare(_Query q) async {
    final period = q.period(AskPeriod.thisMonth(q.today));
    final namedPeriod = q.context.period != null;
    // "Compare with last year": the period named is the one to compare
    // against, measured against the one after it.
    final current = namedPeriod && !period.contains(q.today)
        ? _next(period, q.today)
        : period;
    final prev = namedPeriod && !period.contains(q.today)
        ? period
        : period.previous();
    final flow = _flowOf(q.context);
    final all = await source.entries(prev.fromInstant, current.toInstant);
    final now = _filter(all, q.context, flow, current);
    final before = _filter(all, q.context, flow, prev);
    final change = _sum(now) - _sum(before);
    // A period with nothing in it is "nothing in October", never "the 0 of
    // October". The writer has no words for that, so these keep templates.
    final kind = switch ((_sum(now), _sum(before))) {
      (0, 0) => ReplyKind.nothing,
      (_, 0) => ReplyKind.spentFromNothing,
      (0, _) => ReplyKind.spentToNothing,
      _ when change.abs() * 20 <= _sum(before) => ReplyKind.compareSame,
      _ => change > 0 ? ReplyKind.compareUp : ReplyKind.compareDown,
    };
    final fromNothing = _sum(now) == 0 || _sum(before) == 0;
    final named = _named(q.context);
    return _answer(
      q,
      kind,
      {
        ...named,
        'change': change.abs(),
        'prev_period': _prevPhrase(current, q.today),
        'amount': _sum(now),
        'prev_amount': _sum(before),
        'period': current.phrase(q.today),
      },
      // "You spent ... more than ...": money out only.
      words: flow == _Flow.received || fromNothing
          ? null
          : WriterFacts(
              'compare',
              flags: {
                switch (kind) {
                  ReplyKind.compareUp => 'cmp=more',
                  ReplyKind.compareDown => 'cmp=less',
                  _ => 'cmp=same',
                },
              },
              given: {
                'amount',
                'prev_amount',
                'period',
                'prev_period',
                if (kind != ReplyKind.compareSame) 'change',
                ...named.keys,
              },
            ),
      headline: _headline(q.context, current, q.today, flow),
      figure: _sum(now),
      rows: [
        AskRow(current.label(q.today), amountMinor: _sum(now)),
        AskRow(prev.label(q.today), amountMinor: _sum(before)),
      ],
      link: AskLink.activity,
      suggestions: _followUps(q, current),
    );
  }

  Future<AskAnswer> _incomeSources(_Query q) async {
    final period = q.period(AskPeriod.thisMonth(q.today));
    final entries = _filter(
      await source.entries(period.fromInstant, period.toInstant),
      q.context,
      _Flow.received,
      period,
    );
    final rows = _byPayee(entries);
    if (rows.isEmpty) {
      return _answer(q, ReplyKind.nothing, {
        'period': period.phrase(q.today),
      }, words: _nodata(const {}));
    }
    final top = rows.take(askRowsShown).toList();
    return _answer(
      q,
      ReplyKind.incomeSources,
      {
        'payee': rows.first.title,
        'period': period.phrase(q.today),
        'list': _joinNames([for (final r in top) r.title]),
      },
      words: WriterFacts(
        'income_sources',
        flags: {if (top.length == 1) 'count=one'},
        given: const {'list', 'payee', 'period'},
      ),
      headline: 'Money in · ${period.label(q.today)}',
      figure: _sum(entries),
      rows: rows.take(askRowsShown + 2).toList(),
      totalRows: rows.length,
      link: AskLink.activity,
    );
  }

  // ---- Plans, debts and goals ----

  Future<AskAnswer> _safe(_Query q) async {
    final safe = await source.safeToSpend();
    if (safe == null) return _answer(q, ReplyKind.noBudget, const {});
    if (safe.overMinor > 0) {
      return _answer(
        q,
        ReplyKind.safeOver,
        // The writer's amount for state=over is how far past the plan.
        {'change': safe.overMinor, 'amount': safe.overMinor, 'period': 'today'},
        words: const WriterFacts(
          'safe_to_spend',
          flags: {'state=over'},
          given: {'amount', 'period'},
        ),
        headline: 'Safe to spend · Today',
        figure: 0,
      );
    }
    return _answer(
      q,
      ReplyKind.safeToSpend,
      {'amount': safe.leftTodayMinor, 'period': 'today'},
      words: const WriterFacts(
        'safe_to_spend',
        flags: {'state=ok'},
        given: {'amount', 'period'},
      ),
      headline: 'Safe to spend · Today',
      figure: safe.leftTodayMinor,
      suggestions: const ['How much did I spend today?', 'Bills coming up'],
    );
  }

  Future<AskAnswer> _lines(
    _Query q,
    List<AskLine> lines, {
    required ReplyKind some,
    required ReplyKind none,
    required String headline,
    required String Function(int n) count,
    String? Function(AskLine l)? detail,
    Map<String, Object> Function(List<AskLine> lines)? extra,
    int Function(List<AskLine> lines)? total,
    WriterFacts? Function(List<AskLine> lines)? words,
    AskLink? link,
    List<String> suggestions = const [],
  }) async {
    if (lines.isEmpty) return _answer(q, none, const {}, link: link);
    final figure =
        total?.call(lines) ?? lines.fold<int>(0, (s, l) => s + l.amountMinor);
    return _answer(
      q,
      some,
      {
        'count': count(lines.length),
        'number': '${lines.length}',
        'amount': figure,
        // Every name, so a reply that lists them leaves none out.
        if (lines.length <= _listMax)
          'list': _joinNames([for (final l in lines) l.name]),
        if (lines.length == 1) 'payee': lines.single.name,
        ...?extra?.call(lines),
      },
      words: words?.call(lines),
      headline: headline,
      figure: figure,
      rows: [
        for (final l in lines.take(askRowsShown))
          AskRow(l.name, detail: detail?.call(l), amountMinor: l.amountMinor),
      ],
      totalRows: lines.length,
      link: link,
      suggestions: suggestions,
    );
  }

  Future<AskAnswer> _bills(_Query q) async {
    final bills = [...await source.billsDue()]
      ..sort((a, b) => (a.date ?? q.today).compareTo(b.date ?? q.today));
    return _lines(
      q,
      bills,
      some: ReplyKind.bills,
      none: ReplyKind.noBills,
      headline: 'Bills · coming up',
      count: (n) => _plural(n, 'bill'),
      detail: (l) =>
          l.date == null ? 'No date set' : 'Due ${_day(l.date!, q.today)}',
      extra: (lines) => {
        'payee': lines.first.name,
        'date': lines.first.date == null
            ? 'no date yet'
            : _day(lines.first.date!, q.today),
      },
      words: (lines) => WriterFacts(
        'bills_due',
        flags: {if (lines.length == 1) 'count=one'},
        given: {
          'list',
          'count',
          // The first bill is the next due, so its date is "the next one".
          if (lines.first.date != null &&
              _startsWithDigit(_day(lines.first.date!, q.today)))
            'date',
        },
      ),
      link: AskLink.bills,
      suggestions: const ['What is safe to spend?'],
    );
  }

  Future<AskAnswer> _subscriptions(_Query q) async => _lines(
    q,
    await source.subscriptions(),
    some: ReplyKind.subscriptions,
    none: ReplyKind.noSubscriptions,
    headline: 'Subscriptions · a month',
    count: (n) => _plural(n, 'subscription'),
    words: (lines) => WriterFacts(
      'subscriptions',
      flags: {if (lines.length == 1) 'count=one'},
      given: const {'list', 'count', 'amount'},
    ),
  );

  Future<AskAnswer> _debts(_Query q) async => _lines(
    q,
    await source.debts(),
    some: ReplyKind.debts,
    none: ReplyKind.noDebts,
    headline: 'Debts · left to pay',
    count: (n) => _plural(n, 'debt'),
    words: (lines) => _owedWords('debts', lines),
    link: AskLink.debts,
    suggestions: const ['Bills coming up', 'Who owes me?'],
  );

  Future<AskAnswer> _lent(_Query q) async => _lines(
    q,
    await source.lent(),
    some: ReplyKind.lent,
    none: ReplyKind.nobodyOwes,
    headline: 'Money lent · still to come back',
    count: (n) => _plural(n, 'person', 'people'),
    words: (lines) => _owedWords('lent', lines),
    detail: (l) =>
        l.date == null ? 'No date set' : 'Due ${_day(l.date!, q.today)}',
    link: AskLink.goals,
  );

  Future<AskAnswer> _owesMe(_Query q) async {
    final lines = [...await source.owedToMe(), ...await source.lent()]
      ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    return _lines(
      q,
      lines,
      some: ReplyKind.owesMe,
      none: ReplyKind.nobodyOwes,
      headline: 'Owed to you',
      count: (n) => _plural(n, 'person', 'people'),
      // Largest first, so the list starts with who owes most.
      words: (lines) => WriterFacts(
        'who_owes_me',
        flags: {if (lines.length == 1) 'count=one'},
        given: const {'list', 'amount', 'count'},
      ),
    );
  }

  Future<AskAnswer> _balance(_Query q) async {
    var lines = await source.balances();
    final account = q.context.entities[SlotKind.account];
    if (account != null) {
      lines = [
        for (final l in lines)
          if (normaliseName(l.name) == normaliseName(account.name)) l,
      ];
    }
    final one = account != null && lines.length == 1 ? lines.single : null;
    // As the Balances total: savings are left out unless asked about.
    final counted = account != null || lines.every((l) => l.savings)
        ? lines
        : [
            for (final l in lines)
              if (!l.savings) l,
          ];
    final figure = counted.fold(0, (s, l) => s + l.amountMinor);
    final fuliza = counted.any((l) => l.fulizaOwedMinor > 0);
    // At or below zero, the words say so and the amount shows without a
    // sign. The writer has no words for it, so these keep their templates.
    final kind = switch (figure) {
      > 0 => ReplyKind.balance,
      0 => one != null ? ReplyKind.accountEmpty : ReplyKind.totalEmpty,
      _ when one != null && one.fulizaOwedMinor == -figure =>
        ReplyKind.accountOwesFuliza,
      _ when one != null && fuliza => ReplyKind.accountBelowFuliza,
      _ when one != null => ReplyKind.accountBelow,
      _ when fuliza => ReplyKind.totalBelowFuliza,
      _ => ReplyKind.totalBelow,
    };
    return _lines(
      q,
      lines,
      some: kind,
      none: ReplyKind.nothing,
      headline: 'Balance · now',
      count: (n) => _plural(n, 'account'),
      detail: (l) => l.savings ? 'Savings' : null,
      extra: (lines) => {
        'account': ?one?.name,
        if (figure < 0) 'amount': -figure,
      },
      words: (lines) => kind != ReplyKind.balance
          ? null
          : WriterFacts(
              'balance',
              given: {'amount', if (one != null) 'account'},
            ),
      total: (_) => figure,
    );
  }

  Future<AskAnswer> _goals(_Query q) async => _lines(
    q,
    await source.goals(),
    some: ReplyKind.goals,
    none: ReplyKind.noGoals,
    headline: 'Goals · saved so far',
    count: (n) => _plural(n, 'goal'),
    extra: (lines) => {
      if (lines.length == 1) 'goal': lines.single.name,
      if (lines.length == 1 && (lines.single.extraMinor ?? 0) > 0)
        'target': lines.single.extraMinor!,
    },
    // Only a reached goal: whether one is on track is not in the records.
    words: (lines) =>
        lines.length == 1 &&
            (lines.single.extraMinor ?? 0) > 0 &&
            lines.single.amountMinor >= lines.single.extraMinor!
        ? const WriterFacts(
            'goals',
            flags: {'state=done'},
            given: {'goal', 'amount', 'target'},
          )
        : null,
    detail: (l) => l.extraMinor == null || l.extraMinor! <= 0
        ? 'Saving'
        : '${_percentWord((l.amountMinor * 100 / l.extraMinor!).round())} '
              'of the target',
    link: AskLink.goals,
  );

  // ---- Business ----

  Future<AskAnswer> _sales(_Query q) async {
    final period = q.period(AskPeriod.today(q.today));
    final item = q.context.entities[SlotKind.item];
    if (item != null) return _topItems(q, only: item);
    final sales = await source.sales(period);
    if (sales.amountMinor == 0) {
      return _answer(
        q,
        ReplyKind.nothing,
        {'period': period.phrase(q.today)},
        words: _nodata(const {}),
        headline: 'Sales · ${period.label(q.today)}',
        figure: 0,
      );
    }
    final items = await source.itemsSold(period);
    return _answer(
      q,
      ReplyKind.sales,
      {
        'count': _plural(sales.count ?? 0, 'sale'),
        'number': '${sales.count ?? 0}',
        'amount': sales.amountMinor,
        'period': period.phrase(q.today),
      },
      words: WriterFacts(
        'sales',
        given: {
          'amount',
          'period',
          // "from 1 sales": the writer's sales kind has no count=one.
          if ((sales.count ?? 0) > 1) 'count',
        },
      ),
      headline: 'Sales · ${period.label(q.today)}',
      figure: sales.amountMinor,
      rows: [
        for (final l in items.take(askRowsShown))
          AskRow(
            l.name,
            detail: _plural(l.count ?? 0, 'sale'),
            amountMinor: l.amountMinor,
          ),
      ],
      totalRows: items.length,
      link: AskLink.businessInsights,
      suggestions: const ['Profit this week', 'What sold most this week?'],
    );
  }

  Future<AskAnswer> _topItems(_Query q, {AskEntity? only}) async {
    final period = q.period(AskPeriod.thisWeek(q.today));
    var items = [...await source.itemsSold(period)]
      ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    if (only != null) {
      items = [
        for (final i in items)
          if (normaliseName(i.name) == normaliseName(only.name)) i,
      ];
    }
    if (items.isEmpty) {
      return _answer(
        q,
        ReplyKind.nothing,
        {'period': period.phrase(q.today), 'item': ?only?.name},
        words: _nodata({'item': ?only?.name}),
        headline: 'Sales · ${period.label(q.today)}',
      );
    }
    final top = items.first;
    final shown = items.take(askRowsShown).toList();
    return _answer(
      q,
      ReplyKind.topItems,
      {
        'amount': top.amountMinor,
        'count': _plural(top.count ?? 0, 'sale'),
        'item': top.name,
        'period': period.phrase(q.today),
        'list': _joinNames([for (final l in shown) l.name]),
      },
      // One item asked about is its sales; else the best sellers.
      words: only != null
          ? const WriterFacts('sales', given: {'amount', 'item', 'period'})
          : WriterFacts(
              'top_items',
              flags: {if (shown.length == 1) 'count=one'},
              given: const {'list', 'item', 'period'},
            ),
      headline: 'Sales · ${period.label(q.today)}',
      figureText: top.name,
      rows: [
        for (final l in items.take(askRowsShown))
          AskRow(
            l.name,
            detail: _plural(l.count ?? 0, 'sale'),
            amountMinor: l.amountMinor,
          ),
      ],
      totalRows: items.length,
      link: AskLink.businessInsights,
      suggestions: const ['Profit this week', 'Who owes me?', 'Low stock'],
    );
  }

  Future<AskAnswer> _profit(_Query q) async {
    final period = q.period(AskPeriod.thisMonth(q.today));
    final profit = await source.profit(period);
    if (profit == null) return _plain(ReplyKind.cant, q.now, q.seed);
    return _answer(
      q,
      profit >= 0 ? ReplyKind.profit : ReplyKind.loss,
      {'period': period.phrase(q.today), 'amount': profit.abs()},
      words: WriterFacts(
        'profit',
        flags: {if (profit < 0) 'result=loss'},
        given: const {'amount', 'period'},
      ),
      headline: 'Profit · ${period.label(q.today)}',
      figure: profit.abs(),
      link: AskLink.businessInsights,
      suggestions: const ['What sold most this week?', 'Low stock'],
    );
  }

  Future<AskAnswer> _fees(_Query q) async {
    final period = q.period(AskPeriod.thisMonth(q.today));
    final fees = await source.fees(period);
    return _answer(
      q,
      fees == 0 ? ReplyKind.nothing : ReplyKind.fees,
      {'period': period.phrase(q.today), if (fees != 0) 'amount': fees},
      words: fees == 0
          ? null
          : const WriterFacts('fees', given: {'amount', 'period'}),
      headline: 'Charges · ${period.label(q.today)}',
      figure: fees,
      link: AskLink.insights,
    );
  }

  Future<AskAnswer> _lowStock(_Query q) async {
    final items = await source.lowStock();
    if (items.isEmpty) return _answer(q, ReplyKind.noLowStock, const {});
    return _answer(
      q,
      ReplyKind.lowStock,
      {
        'count': _plural(items.length, 'item'),
        'number': '${items.length}',
        'item': items.first.name,
        if (items.length <= _listMax)
          'list': _joinNames([for (final l in items) l.name]),
      },
      words: WriterFacts(
        'low_stock',
        flags: {if (items.length == 1) 'count=one'},
        given: const {'list', 'item', 'count'},
      ),
      headline: 'Stock · running low',
      figureText: items.first.name,
      rows: [
        for (final l in items.take(askRowsShown + 2))
          AskRow(
            l.name,
            detail: l.count == null ? null : '${_qty(l.count!)} left',
          ),
      ],
      totalRows: items.length,
      link: AskLink.stock,
    );
  }

  // ---- Helpers ----

  Future<AskAnswer> _answer(
    _Query q,
    ReplyKind kind,
    Map<String, Object> facts, {
    WriterFacts? words,
    String? headline,
    int? figure,
    String? figureText,
    List<AskRow> rows = const [],
    int totalRows = 0,
    AskChart? chart,
    AskLink? link,
    List<String> suggestions = const [],
  }) => _word(
    AskAnswer(
      kind: kind,
      template: writer.write(kind, facts.keys.toSet(), seed: q.seed),
      facts: facts,
      asOf: q.now,
      headline: headline,
      figureMinor: figure,
      figureText: figureText,
      rows: rows,
      totalRows: totalRows,
      chart: chart,
      link: link,
      suggestions: suggestions,
      context: q.context,
    ),
    words,
    q.seed,
  );

  /// The category and payee the question names, for the writer.
  static Map<String, Object> _named(AskContext context) => {
    if (context.entities[SlotKind.category] case final c?)
      'category': c.name.toLowerCase(),
    if (context.entities[SlotKind.payee] case final p?) 'payee': p.name,
  };

  /// Nothing found for a name the question gave. With no name, the
  /// writer's "no records" would say more than the records do: there may be
  /// records, just none like this, so the template says that.
  static WriterFacts? _nodata(Map<String, Object> named) => named.isEmpty
      ? null
      : WriterFacts(
          'nodata',
          given: {'period', ...named.keys},
          anyOf: named.keys.toSet(),
        );

  static WriterFacts _totalWords(
    _Flow flow,
    ReplyKind kind,
    Map<String, Object> named,
    int payments,
  ) {
    final payee = named.containsKey('payee');
    final writerKind = switch (flow) {
      _Flow.received => payee ? 'received_from' : 'received',
      _Flow.sent => payee ? 'sent_to' : 'spent',
      _Flow.spent => 'spent',
    };
    // Only these kinds know count=one; the others would say "1 payments".
    final countsOne = writerKind == 'sent_to' || writerKind == 'received_from';
    final compared = kind != ReplyKind.total;
    return WriterFacts(
      writerKind,
      flags: {
        if (kind == ReplyKind.totalUp) 'cmp=more',
        if (kind == ReplyKind.totalDown) 'cmp=less',
        if (countsOne && payments == 1) 'count=one',
      },
      given: {
        'amount',
        'period',
        ...named.keys,
        if (payments > 1 || countsOne) 'count',
        if (compared) ...{'prev_period', 'prev_amount', 'change'},
      },
    );
  }

  /// Debts or money lent: the total, how many, and who when only one.
  static WriterFacts _owedWords(String kind, List<AskLine> lines) =>
      WriterFacts(
        kind,
        flags: {if (lines.length == 1) 'count=one'},
        given: {'amount', 'count', if (lines.length == 1) 'payee'},
      );

  static bool _startsWithDigit(String s) =>
      s.isNotEmpty && s.codeUnitAt(0) >= 48 && s.codeUnitAt(0) <= 57;

  List<String> _followUps(_Query q, AskPeriod period, {String? only}) {
    final out = <String>[];
    if (period.kind == PeriodKind.month) {
      final prev = period.previous().from.yearMonth;
      out.add('Compare with ${_monthNames[prev.month - 1]}');
    } else if (period.kind == PeriodKind.year) {
      out.add('Compare with last year');
    } else {
      out.add('Compare with before');
    }
    if (only != null &&
        q.context.entities[SlotKind.category] != null &&
        q.context.entities[SlotKind.payee] == null) {
      out.add('Only $only');
    }
    if (!period.contains(q.today)) out.add('This month so far');
    return out;
  }

  Future<Map<int, String>> _names(SlotKind kind) async => {
    for (final e in await source.entities())
      if (e.kind == kind) ?int.tryParse(e.key.substring(2)): e.name,
  };

  List<AskRow> _byPayee(List<LedgerEntry> entries) {
    final totals = <String, (String, int, int)>{};
    for (final e in entries) {
      final key = _payeeKey(e);
      final (name, sum, n) = totals[key] ?? (_payeeName(e), 0, 0);
      totals[key] = (name, sum + e.amountMinor, n + 1);
    }
    final rows = totals.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
    return [
      for (final (name, sum, n) in rows)
        AskRow(name, detail: _payments(n), amountMinor: sum),
    ];
  }

  List<AskRow> _byCategory(List<LedgerEntry> entries, Map<int, String> names) {
    final totals = <int?, (int, int)>{};
    for (final e in entries) {
      final (sum, n) = totals[e.categoryId] ?? (0, 0);
      totals[e.categoryId] = (sum + e.amountMinor, n + 1);
    }
    final rows = totals.entries.toList()
      ..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    return [
      for (final MapEntry(:key, :value) in rows)
        AskRow(
          names[key] ?? _notSorted,
          detail: _payments(value.$2),
          amountMinor: value.$1,
        ),
    ];
  }

  String _headline(
    AskContext context,
    AskPeriod period,
    CalendarDate today,
    _Flow flow,
  ) {
    final parts = [
      for (final kind in [SlotKind.category, SlotKind.payee, SlotKind.account])
        ?context.entities[kind]?.name,
    ];
    if (parts.isEmpty) {
      parts.add(switch (flow) {
        _Flow.spent => 'Spending',
        _Flow.received => 'Money in',
        _Flow.sent => 'Money out',
      });
    }
    return [...parts, period.label(today)].join(' · ');
  }

  AskPeriod _defaultPeriod(AskIntent? intent, CalendarDate today) =>
      switch (intent) {
        AskIntent.trend => AskPeriod.thisYear(today),
        AskIntent.topItems => AskPeriod.thisWeek(today),
        AskIntent.sales => AskPeriod.today(today),
        _ => AskPeriod.thisMonth(today),
      };

  static List<SlotKind> _kindsFor(SlotKind guess, AskIntent intent) {
    final order = [
      guess,
      if (intent == AskIntent.sales || intent == AskIntent.topItems)
        SlotKind.item,
      SlotKind.category,
      SlotKind.payee,
      SlotKind.account,
      SlotKind.item,
    ];
    return {...order}.toList();
  }

  static bool _namesSomething(AskIntent intent) => const {
    AskIntent.spent,
    AskIntent.received,
    AskIntent.sentTo,
    AskIntent.receivedFrom,
    AskIntent.countPayments,
    AskIntent.trend,
    AskIntent.compare,
    AskIntent.refine,
  }.contains(intent);

  static _Flow _flowOf(AskContext context) => switch (context.intent) {
    AskIntent.received ||
    AskIntent.receivedFrom ||
    AskIntent.incomeSources => _Flow.received,
    AskIntent.sentTo => _Flow.sent,
    _ =>
      context.entities.containsKey(SlotKind.payee) &&
              !context.entities.containsKey(SlotKind.category)
          ? _Flow.sent
          : _Flow.spent,
  };

  static AskPeriod _next(AskPeriod p, CalendarDate today) {
    final days = p.from.daysUntil(p.to);
    return switch (p.kind) {
      PeriodKind.year => AskPeriod.year(p.from.year + 1, today),
      PeriodKind.month => AskPeriod.month(p.from.yearMonth.next, today),
      _ => AskPeriod(p.kind, p.to, p.to.addDays(days), length: p.length),
    };
  }

  static List<LedgerEntry> _filter(
    List<LedgerEntry> entries,
    AskContext context,
    _Flow flow,
    AskPeriod period,
  ) {
    final category = context.entities[SlotKind.category]?.key;
    final payee = context.entities[SlotKind.payee]?.key;
    final account = context.entities[SlotKind.account]?.key;
    return [
      for (final e in entries)
        if (e.currency == BaseCurrency.code &&
            period.contains(e.date) &&
            _flows(e, flow) &&
            (category == null || _isKey(category, 'c', e.categoryId)) &&
            (payee == null || _isPayee(e, payee)) &&
            (account == null || _isKey(account, 'a', e.accountId)))
          e,
    ];
  }

  static bool _flows(LedgerEntry e, _Flow flow) {
    final role = roleOf(e);
    return switch (flow) {
      _Flow.spent => e.isOutflow && role == LedgerRole.spending,
      _Flow.sent => e.isOutflow && role != LedgerRole.ownTransfer,
      _Flow.received =>
        e.isInflow &&
            (role == LedgerRole.income || role == LedgerRole.awaitingPayee),
    };
  }

  static bool _isKey(String keys, String prefix, int? id) =>
      id != null && keys.split('|').contains('$prefix:$id');

  static bool _isPayee(LedgerEntry e, String keys) =>
      keys.split('|').contains(_payeeKey(e)) ||
      (e.payeeId != null && keys.split('|').contains('p:${e.payeeId}'));

  /// `p:<id>` for a named payee, else `n:<name as printed>`.
  static String _payeeKey(LedgerEntry e) => e.payeeId != null
      ? 'p:${e.payeeId}'
      : 'n:${normaliseName(e.counterpartyName ?? '')}';

  static String _payeeName(LedgerEntry e) =>
      e.payeeName ?? e.counterpartyName ?? 'Not named yet';

  static int _sum(Iterable<LedgerEntry> entries) =>
      entries.fold(0, (s, e) => s + e.amountMinor);

  static String _prevPhrase(AskPeriod period, CalendarDate today) {
    final prev = period.previous();
    return switch (period.kind) {
      PeriodKind.month =>
        '${_monthNames[prev.from.month - 1]}'
            '${prev.from.year == today.year ? '' : ' ${prev.from.year}'}',
      PeriodKind.year => '${prev.from.year}',
      PeriodKind.week => 'the week before',
      PeriodKind.day => 'the day before',
      _ => 'the same time before',
    };
  }

  static String _day(CalendarDate date, CalendarDate today) {
    if (date == today) return 'today';
    if (date == today.addDays(1)) return 'tomorrow';
    final month = _monthNames[date.month - 1].substring(0, 3);
    return '${date.day} $month${date.year == today.year ? '' : ' ${date.year}'}';
  }

  static String _plural(int n, String one, [String? many]) =>
      '$n ${n == 1 ? one : (many ?? '${one}s')}';

  static String _payments(int n) => _plural(n, 'payment');

  static String _times(int n, {bool capital = false}) {
    final text = switch (n) {
      1 => 'once',
      2 => 'twice',
      _ => '$n times',
    };
    return capital ? '${text[0].toUpperCase()}${text.substring(1)}' : text;
  }

  static String _percentWord(int percent) => switch (percent) {
    >= 48 && <= 52 => 'half',
    >= 23 && <= 27 => 'a quarter',
    >= 31 && <= 35 => 'a third',
    >= 73 && <= 77 => 'three quarters',
    _ => '$percent%',
  };

  static String _qty(int milli) {
    final whole = milli ~/ 1000;
    final part = (milli % 1000) ~/ 100;
    return part == 0 ? '$whole' : '$whole.$part';
  }

  static String _title(String word) =>
      word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}';

  static String _joinNames(List<String> names) => switch (names.length) {
    0 => '',
    1 => names.first,
    _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
  };
}

enum _Flow { spent, received, sent }

/// The row for spending with no category yet, as Insights calls it.
const _notSorted = 'Not sorted yet';

class _Query {
  _Query(this.context, this.today, this.now, this.seed);

  final AskContext context;
  final CalendarDate today;
  final DateTime now;
  final int seed;

  AskPeriod period(AskPeriod fallback) => context.period ?? fallback;
}

extension on List<String> {
  List<String> ifEmpty(String value) => isEmpty ? [value] : this;
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// A title for a conversation from its first understood question, such as
/// `Food spending this year` or `Money sent to John Kamau`.
String conversationTitle(AskContext context, CalendarDate today) {
  final intent = context.intent;
  final category = context.entities[SlotKind.category]?.name;
  final payee = context.entities[SlotKind.payee]?.name;
  final item = context.entities[SlotKind.item]?.name;
  final account = context.entities[SlotKind.account]?.name;
  final when = context.period?.phrase(today);
  String withWhen(String s) => when == null ? s : '$s $when';
  final text = switch (intent) {
    AskIntent.spent ||
    AskIntent.trend ||
    AskIntent.compare ||
    AskIntent.countPayments ||
    AskIntent.biggestPayment when category != null => withWhen(
      '$category spending',
    ),
    AskIntent.sentTo ||
    AskIntent.spent when payee != null => 'Money sent to $payee',
    AskIntent.received ||
    AskIntent.receivedFrom when payee != null => 'Money from $payee',
    AskIntent.receivedFrom when account != null =>
      'Moved from $account to my other accounts',
    AskIntent.received => withWhen('Money in'),
    AskIntent.spent || AskIntent.trend => withWhen('Spending'),
    AskIntent.safeToSpend => 'What is safe to spend',
    AskIntent.debts => 'Debts left to pay',
    AskIntent.lent => 'Money lent',
    AskIntent.whoOwesMe => 'Who owes me',
    AskIntent.billsDue => 'Bills coming up',
    AskIntent.subscriptions => 'Subscriptions',
    AskIntent.goals => 'Goals',
    AskIntent.balance => 'Balances',
    AskIntent.topPayees => withWhen('Who I pay most'),
    AskIntent.topCategories => withWhen('Where money goes'),
    AskIntent.incomeSources => withWhen('Where money comes from'),
    AskIntent.sales when item != null => withWhen('$item sales'),
    AskIntent.sales => withWhen('Sales'),
    AskIntent.topItems => withWhen('What sold most'),
    AskIntent.profit => withWhen('Profit'),
    AskIntent.lowStock => 'Low stock',
    AskIntent.fees => withWhen('Charges'),
    _ => payee != null ? 'Money sent to $payee' : 'New conversation',
  };
  return text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
}
