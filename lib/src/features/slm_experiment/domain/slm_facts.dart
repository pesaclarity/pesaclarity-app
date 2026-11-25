import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/ledger/ledger_role.dart';
import '../../../domain/time/calendar.dart';

/// A plan line for the month: what was planned and what is used so far.
class SlmBudget {
  const SlmBudget(this.name, this.plannedMinor, this.usedMinor);

  final String name;
  final int plannedMinor;
  final int usedMinor;
}

/// A named amount: an account's balance or a bill.
class SlmLine {
  const SlmLine(this.name, this.amountMinor, {this.date, this.savings = false});

  final String name;
  final int amountMinor;
  final CalendarDate? date;
  final bool savings;
}

/// Everything the facts are worked out from, read on the phone.
class SlmFactsInput {
  const SlmFactsInput({
    required this.today,
    required this.entries,
    this.lastPayday,
    this.categoryNames = const {},
    this.balances = const [],
    this.bills = const [],
    this.budgets = const [],
    this.feesThisMonthMinor,
  });

  final CalendarDate today;

  /// Ledger entries from the first day of three months ago to today.
  final List<LedgerEntry> entries;
  final CalendarDate? lastPayday;
  final Map<int, String> categoryNames;
  final List<SlmLine> balances;
  final List<SlmLine> bills;
  final List<SlmBudget> budgets;

  /// Charges this month as Insights counts them; null to add up the
  /// entries' own fees.
  final int? feesThisMonthMinor;
}

/// One heading and its lines.
class SlmFactSection {
  const SlmFactSection(this.title, this.lines);

  final String title;
  final List<String> lines;
}

/// The facts the model is given. Every number is worked out here, by the
/// app, never by the model, and the whole stays under [maxChars] so the
/// prompt is about 1,500 tokens at most.
class SlmFacts {
  const SlmFacts(this.sections);

  /// About 1,200 tokens of facts at roughly 3.5 characters a token.
  static const maxChars = 4200;

  /// How many categories, payees, bills and budgets are named.
  static const topCount = 5;

  final List<SlmFactSection> sections;

  int get lineCount => sections.fold(0, (n, s) => n + s.lines.length);

  /// The facts as the model reads them.
  String get text => [
    for (final s in sections) ...[
      '${s.title}:',
      for (final l in s.lines) '- $l',
    ],
  ].join('\n');

  static String _money(int minor) => formatMoney(Money(minor));

  static String _date(CalendarDate d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _monthName(YearMonth m) => '${_months[m.month - 1]} ${m.year}';

  /// Works out the facts from [input].
  static SlmFacts of(SlmFactsInput input) {
    final today = input.today;
    final month = today.yearMonth;
    final end = today.addDays(1);
    bool within(LedgerEntry e, CalendarDate from, CalendarDate to) {
      final d = CalendarDate.local(e.occurredAt);
      return !d.isBefore(from) && d.isBefore(to);
    }

    final thisMonth = [
      for (final e in input.entries)
        if (within(e, month.firstDay, end)) e,
    ];
    final sections = <SlmFactSection>[
      SlmFactSection('Today', [_date(today)]),
    ];

    // Money in and out.
    final flows = <String>[];
    void flow(String label, Iterable<LedgerEntry> list) {
      var inMinor = 0;
      var outMinor = 0;
      for (final e in list) {
        inMinor += incomeOf(e);
        outMinor += spendingOf(e);
      }
      flows.add(
        '$label: money in ${_money(inMinor)}, spent ${_money(outMinor)}, '
        'left ${_money(inMinor - outMinor)}',
      );
    }

    flow('This month so far (${_monthName(month)})', thisMonth);
    final payday = input.lastPayday;
    if (payday != null && !payday.isAfter(today)) {
      flow('Since payday (${_date(payday)})', [
        for (final e in input.entries)
          if (within(e, payday, end)) e,
      ]);
    }
    sections.add(SlmFactSection('Money in and out', flows));

    // Categories and payees this month.
    final byCategory = <String, int>{};
    final byPayee = <String, int>{};
    var feesMinor = 0;
    for (final e in thisMonth) {
      feesMinor += e.feeMinor;
      final spent = spendingOf(e);
      if (spent == 0) continue;
      final name = e.categoryId == null
          ? 'Not sorted'
          : input.categoryNames[e.categoryId] ?? 'Other';
      byCategory[name] = (byCategory[name] ?? 0) + spent;
      final payee = (e.payeeName ?? e.counterpartyName)?.trim();
      if (payee != null && payee.isNotEmpty) {
        byPayee[payee] = (byPayee[payee] ?? 0) + spent;
      }
    }
    List<String> top(Map<String, int> m) {
      final list = m.entries.where((e) => e.value > 0).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return [
        for (final e in list.take(topCount)) '${e.key}: ${_money(e.value)}',
      ];
    }

    final categories = top(byCategory);
    if (categories.isNotEmpty) {
      sections.add(SlmFactSection('Top spending this month', categories));
    }
    final payees = top(byPayee);
    if (payees.isNotEmpty) {
      sections.add(SlmFactSection('Top payees this month', payees));
    }
    sections.add(
      SlmFactSection('Fees this month', [
        _money(input.feesThisMonthMinor ?? feesMinor),
      ]),
    );

    // Budgets.
    if (input.budgets.isNotEmpty) {
      final budgets = [...input.budgets]
        ..sort(
          (a, b) => (b.usedMinor - b.plannedMinor).compareTo(
            a.usedMinor - a.plannedMinor,
          ),
        );
      sections.add(
        SlmFactSection('Budgets this month', [
          for (final b in budgets.take(topCount))
            '${b.name}: planned ${_money(b.plannedMinor)}, '
                'spent ${_money(b.usedMinor)}, '
                '${b.usedMinor > b.plannedMinor ? 'over by ${_money(b.usedMinor - b.plannedMinor)}' : 'left ${_money(b.plannedMinor - b.usedMinor)}'}',
        ]),
      );
    }

    // Bills.
    final bills = [
      for (final b in input.bills)
        if (b.date == null || !b.date!.isBefore(today)) b,
    ]..sort((a, b) => (a.date ?? today).compareTo(b.date ?? today));
    if (bills.isNotEmpty) {
      sections.add(
        SlmFactSection('Upcoming bills', [
          for (final b in bills.take(topCount))
            '${b.name}: ${_money(b.amountMinor)}'
                '${b.date == null ? '' : ', due ${_date(b.date!)}'}',
        ]),
      );
    }

    // Balances by account type.
    if (input.balances.isNotEmpty) {
      var dayToDay = 0;
      var savings = 0;
      for (final b in input.balances) {
        if (b.savings) {
          savings += b.amountMinor;
        } else {
          dayToDay += b.amountMinor;
        }
      }
      sections.add(
        SlmFactSection('Balances now', [
          'Day-to-day accounts: ${_money(dayToDay)}',
          if (input.balances.any((b) => b.savings))
            'Savings accounts: ${_money(savings)}',
          for (final b in input.balances.take(6))
            '${b.name}${b.savings ? ' (savings)' : ''}: ${_money(b.amountMinor)}',
        ]),
      );
    }

    // The last three whole months.
    final trend = <String>[];
    for (var i = 3; i >= 1; i--) {
      final m = month.addMonths(-i);
      var inMinor = 0;
      var outMinor = 0;
      for (final e in input.entries) {
        if (!m.contains(CalendarDate.local(e.occurredAt))) continue;
        inMinor += incomeOf(e);
        outMinor += spendingOf(e);
      }
      trend.add(
        '${_monthName(m)}: money in ${_money(inMinor)}, '
        'spent ${_money(outMinor)}',
      );
    }
    sections.add(SlmFactSection('Last 3 months', trend));

    return SlmFacts(sections)._capped();
  }

  /// Drops lines from the end of the longest sections until the text fits.
  SlmFacts _capped() {
    final kept = [
      for (final s in sections) SlmFactSection(s.title, [...s.lines]),
    ];
    var facts = SlmFacts(kept);
    while (facts.text.length > maxChars) {
      final longest = kept.reduce(
        (a, b) => a.lines.length >= b.lines.length ? a : b,
      );
      if (longest.lines.length <= 1) break;
      longest.lines.removeLast();
      facts = SlmFacts(kept);
    }
    return facts;
  }
}

/// The system text: what the model may do with the facts.
const slmSystemPrompt =
    'You help one person understand their own money. Use only the facts '
    'below; they were worked out by the app and are correct. Do not add, '
    'subtract or invent any number: quote amounts exactly as written. '
    'Explain, compare and suggest in plain words, in at most 6 short '
    'sentences. If the facts do not answer the question, say you are not '
    'sure.';

/// The system text with [facts] after it.
String slmSystem(SlmFacts facts) => '$slmSystemPrompt\n\nFacts:\n${facts.text}';
