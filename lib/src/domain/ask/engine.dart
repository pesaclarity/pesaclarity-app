import '../../core/money/money.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import '../spaces/space.dart';
import '../time/calendar.dart';
import 'answer.dart';
import 'context.dart';
import 'data_source.dart';
import 'matcher.dart';
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

/// Turns questions into lookups on one space's records and the lookups
/// into answers. Reads only through [source], so it never sees another
/// space.
class AskEngine {
  AskEngine({
    required this.source,
    required this.reader,
    this.writer = const TemplateReplyWriter(),
    this.spaceKind = SpaceKind.personal,
  });

  final AskDataSource source;
  final QuestionReader reader;
  final ReplyWriter writer;
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
        _plain(_plainKind(intent), now, seed),
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

    final matcher = EntityMatcher(
      await source.entities(),
      shortcuts: await source.shortcuts(),
    );
    final named = <SlotKind, AskEntity>{};
    String? missing;
    for (final span in understanding.spans) {
      if (span.kind == SlotKind.period || span.kind == SlotKind.amount) {
        continue;
      }
      final result = matcher.match(span.text, _kindsFor(span.kind, intent));
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
      _ => Future.value(_plain(ReplyKind.cant, now, seed)),
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

  AskAnswer _plain(ReplyKind kind, DateTime now, int seed) => AskAnswer(
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
  );

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
    if (now.isEmpty) {
      return _answer(
        q,
        ReplyKind.nothing,
        {'period': period.phrase(q.today)},
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
        'count': _payments(now.length),
        'period': period.phrase(q.today),
        if (kind != ReplyKind.total) 'change': change.abs(),
        if (kind != ReplyKind.total)
          'prev_period': _prevPhrase(period, q.today),
        if (share != null) ...{
          'percent': _percentWord(share.partPercent),
          'category': q.context.entities[SlotKind.category]!.name.toLowerCase(),
        },
      },
      headline: headline,
      figure: amount,
      rows: share == null ? byWho.take(askRowsShown).toList() : const [],
      totalRows: share == null ? byWho.length : now.length,
      chart: share,
      link: AskLink.activity,
      suggestions: _followUps(q, period, only: byWho.firstOrNull?.title),
    );
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
    return _answer(
      q,
      entries.isEmpty ? ReplyKind.nothing : ReplyKind.count,
      {
        'count': _times(entries.length),
        'period': period.phrase(q.today),
        'amount': _sum(entries),
      },
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
    if (entries.isEmpty) {
      return _answer(q, ReplyKind.nothing, {
        'period': period.phrase(q.today),
      }, headline: _headline(q.context, period, q.today, flow));
    }
    final top = entries.first;
    return _answer(
      q,
      ReplyKind.biggest,
      {'payee': _payeeName(top), 'date': _day(top.date, q.today)},
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
      return _answer(q, ReplyKind.nothing, {'period': period.phrase(q.today)});
    }
    return _answer(
      q,
      ReplyKind.topPayees,
      {'payee': rows.first.title, 'period': period.phrase(q.today)},
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
      return _answer(q, ReplyKind.nothing, {'period': period.phrase(q.today)});
    }
    return _answer(
      q,
      ReplyKind.topCategories,
      {'category': rows.first.title, 'period': period.phrase(q.today)},
      headline: 'Spending · ${period.label(q.today)}',
      figure: _sum(entries),
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
        headline: headline,
        figure: 0,
      );
    }
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
    final named = q.context.period != null;
    // "Compare with last year": the period named is the one to compare
    // against, measured against the one after it.
    final current = named && !period.contains(q.today)
        ? _next(period, q.today)
        : period;
    final prev = named && !period.contains(q.today)
        ? period
        : period.previous();
    final flow = _flowOf(q.context);
    final all = await source.entries(prev.fromInstant, current.toInstant);
    final now = _filter(all, q.context, flow, current);
    final before = _filter(all, q.context, flow, prev);
    final change = _sum(now) - _sum(before);
    final kind = change.abs() * 20 <= _sum(before)
        ? ReplyKind.compareSame
        : (change > 0 ? ReplyKind.compareUp : ReplyKind.compareDown);
    return _answer(
      q,
      kind,
      {'change': change.abs(), 'prev_period': _prevPhrase(current, q.today)},
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
      return _answer(q, ReplyKind.nothing, {'period': period.phrase(q.today)});
    }
    return _answer(
      q,
      ReplyKind.incomeSources,
      {'payee': rows.first.title, 'period': period.phrase(q.today)},
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
        {'change': safe.overMinor},
        headline: 'Safe to spend · Today',
        figure: 0,
      );
    }
    return _answer(
      q,
      ReplyKind.safeToSpend,
      const {},
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
    String Function(AskLine l)? detail,
    Map<String, Object> Function(List<AskLine> lines)? extra,
    AskLink? link,
    List<String> suggestions = const [],
  }) async {
    if (lines.isEmpty) return _answer(q, none, const {}, link: link);
    final total = lines.fold(0, (s, l) => s + l.amountMinor);
    return _answer(
      q,
      some,
      {'count': count(lines.length), ...?extra?.call(lines)},
      headline: headline,
      figure: total,
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
  );

  Future<AskAnswer> _debts(_Query q) async => _lines(
    q,
    await source.debts(),
    some: ReplyKind.debts,
    none: ReplyKind.noDebts,
    headline: 'Debts · left to pay',
    count: (n) => _plural(n, 'debt'),
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
    return _lines(
      q,
      lines,
      some: ReplyKind.balance,
      none: ReplyKind.nothing,
      headline: 'Balance · now',
      count: (n) => _plural(n, 'account'),
    );
  }

  Future<AskAnswer> _goals(_Query q) async => _lines(
    q,
    await source.goals(),
    some: ReplyKind.goals,
    none: ReplyKind.noGoals,
    headline: 'Goals · saved so far',
    count: (n) => _plural(n, 'goal'),
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
        'period': period.phrase(q.today),
      },
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
      return _answer(q, ReplyKind.nothing, {
        'period': period.phrase(q.today),
      }, headline: 'Sales · ${period.label(q.today)}');
    }
    final top = items.first;
    return _answer(
      q,
      ReplyKind.topItems,
      {'amount': top.amountMinor, 'count': _plural(top.count ?? 0, 'sale')},
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
      {'period': period.phrase(q.today)},
      headline: 'Profit · ${period.label(q.today)}',
      figure: profit.abs(),
      link: AskLink.businessInsights,
      suggestions: const ['What sold most this week?', 'Low stock'],
    );
  }

  Future<AskAnswer> _lowStock(_Query q) async {
    final items = await source.lowStock();
    if (items.isEmpty) return _answer(q, ReplyKind.noLowStock, const {});
    return _answer(
      q,
      ReplyKind.lowStock,
      {'count': _plural(items.length, 'item'), 'item': items.first.name},
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

  AskAnswer _answer(
    _Query q,
    ReplyKind kind,
    Map<String, Object> facts, {
    String? headline,
    int? figure,
    String? figureText,
    List<AskRow> rows = const [],
    int totalRows = 0,
    AskChart? chart,
    AskLink? link,
    List<String> suggestions = const [],
  }) => AskAnswer(
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
  );

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
          names[key] ?? 'Not sorted yet',
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
    _ => payee != null ? 'Money sent to $payee' : 'New conversation',
  };
  return text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
}
