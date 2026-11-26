import 'dart:convert';

import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/ledger/ledger_role.dart';
import '../../../domain/time/calendar.dart';
import 'slm_facts.dart';

/// The chart the model picks. The app draws it from its own numbers.
enum SlmChart { bar, line, donut, none }

/// What the chart shows.
enum SlmData {
  top_categories, // ignore: constant_identifier_names
  top_payees, // ignore: constant_identifier_names
  in_out_weeks, // ignore: constant_identifier_names
  budget_vs_spent, // ignore: constant_identifier_names
  months_trend, // ignore: constant_identifier_names
  fees,
  none,
}

/// The time the chart covers.
enum SlmPeriod {
  since_payday, // ignore: constant_identifier_names
  this_month, // ignore: constant_identifier_names
  last_3_months, // ignore: constant_identifier_names
}

/// The model's choice, from the first line of its reply.
class SlmChoice {
  const SlmChoice(this.chart, this.data, this.period);

  final SlmChart chart;
  final SlmData data;
  final SlmPeriod period;

  /// Whether there is a chart to draw.
  bool get draws => chart != SlmChart.none && data != SlmData.none;
}

/// A reply read: the choice (null when the first line is not exactly the
/// schema) and the words to show.
class SlmAnswer {
  const SlmAnswer(this.choice, this.text);

  final SlmChoice? choice;
  final String text;

  /// Reads [reply]: one JSON line
  /// `{"chart":"…","data":"…","period":"…"}`, then the answer. Anything else
  /// on the first line, unknown words or missing keys: no choice, and the
  /// reply is shown as text (without a broken JSON line).
  static SlmAnswer parse(String reply) {
    final trimmed = reply.trimLeft();
    final nl = trimmed.indexOf('\n');
    final first = (nl < 0 ? trimmed : trimmed.substring(0, nl)).trim();
    final rest = nl < 0 ? '' : trimmed.substring(nl + 1).trim();
    if (!first.startsWith('{')) return SlmAnswer(null, reply.trim());
    try {
      final m = jsonDecode(first);
      if (m is! Map || m.length != 3) return SlmAnswer(null, rest);
      T? pick<T extends Enum>(List<T> values, Object? name) {
        for (final v in values) {
          if (v.name == name) return v;
        }
        return null;
      }

      final chart = pick(SlmChart.values, m['chart']);
      final data = pick(SlmData.values, m['data']);
      final period = pick(SlmPeriod.values, m['period']);
      if (chart == null || data == null || period == null) {
        return SlmAnswer(null, rest);
      }
      return SlmAnswer(SlmChoice(chart, data, period), rest);
    } on FormatException {
      return SlmAnswer(null, rest);
    }
  }
}

final _number = RegExp(r'\d[\d,]*(?:\.\d+)?');

String _plain(String n) {
  var s = n.replaceAll(',', '');
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

/// The numbers in [answer] that are not in [facts], as written in the
/// answer: each one gets "Check this number". `12,400` and `12400` count as
/// the same number; a number is grounded only when the facts have it.
List<String> ungroundedNumbers(String answer, String facts) {
  final known = {for (final m in _number.allMatches(facts)) _plain(m[0]!)};
  return [
    for (final m in _number.allMatches(answer))
      if (!known.contains(_plain(m[0]!.replaceFirst(RegExp(r',$'), ''))))
        m[0]!.replaceFirst(RegExp(r',$'), ''),
  ];
}

/// One bar, slice or point: a label and its amount (and, for money in and
/// out or a budget, a second amount).
class SlmPoint {
  const SlmPoint(this.label, this.amountMinor, [this.secondMinor]);

  final String label;
  final int amountMinor;
  final int? secondMinor;
}

/// The chart's numbers, worked out by the app from the same records as the
/// facts. Never the model's.
List<SlmPoint> slmChartPoints(SlmFactsInput input, SlmChoice choice) {
  final today = input.today;
  final end = today.addDays(1);
  final payday = input.lastPayday;
  final from = switch (choice.period) {
    SlmPeriod.since_payday when payday != null && !payday.isAfter(today) =>
      payday,
    SlmPeriod.last_3_months => today.yearMonth.addMonths(-3).firstDay,
    _ => today.yearMonth.firstDay,
  };
  final inWindow = [
    for (final e in input.entries)
      if (!CalendarDate.local(e.occurredAt).isBefore(from) &&
          CalendarDate.local(e.occurredAt).isBefore(end))
        e,
  ];
  List<SlmPoint> top(String? Function(LedgerEntry) key) {
    final sums = <String, int>{};
    for (final e in inWindow) {
      final k = key(e);
      final s = spendingOf(e);
      if (k == null || s == 0) continue;
      sums[k] = (sums[k] ?? 0) + s;
    }
    final list = sums.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in list.take(SlmFacts.topCount)) SlmPoint(e.key, e.value),
    ];
  }

  switch (choice.data) {
    case SlmData.top_categories:
      return top(
        (e) => e.categoryId == null
            ? 'Not sorted'
            : input.categoryNames[e.categoryId] ?? 'Other',
      );
    case SlmData.top_payees:
      return top((e) {
        final p = (e.payeeName ?? e.counterpartyName)?.trim();
        return p == null || p.isEmpty ? null : p;
      });
    case SlmData.in_out_weeks:
      final weeks = <SlmPoint>[];
      for (var s = from; s.isBefore(end); s = s.addDays(7)) {
        final e7 = s.addDays(7);
        var inMinor = 0;
        var outMinor = 0;
        for (final e in inWindow) {
          final d = CalendarDate.local(e.occurredAt);
          if (d.isBefore(s) || !d.isBefore(e7)) continue;
          inMinor += incomeOf(e);
          outMinor += spendingOf(e);
        }
        weeks.add(SlmPoint('${s.day}/${s.month}', inMinor, outMinor));
      }
      return weeks;
    case SlmData.budget_vs_spent:
      return [
        for (final b in input.budgets.take(SlmFacts.topCount))
          SlmPoint(b.name, b.usedMinor, b.plannedMinor),
      ];
    case SlmData.months_trend:
      return [
        for (var i = 3; i >= 0; i--)
          () {
            final m = today.yearMonth.addMonths(-i);
            var outMinor = 0;
            var inMinor = 0;
            for (final e in input.entries) {
              if (!m.contains(CalendarDate.local(e.occurredAt))) continue;
              outMinor += spendingOf(e);
              inMinor += incomeOf(e);
            }
            return SlmPoint('${m.month}/${m.year % 100}', outMinor, inMinor);
          }(),
      ];
    case SlmData.fees:
      var fees = 0;
      var spent = 0;
      for (final e in inWindow) {
        fees += e.feeMinor;
        spent += spendingOf(e);
      }
      return [SlmPoint('Fees', fees), SlmPoint('Other spending', spent - fees)];
    case SlmData.none:
      return const [];
  }
}
