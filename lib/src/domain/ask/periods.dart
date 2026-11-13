import '../time/calendar.dart';
import '../time/date_labels.dart';

/// How a period was named, which decides its comparable period.
enum PeriodKind { day, week, month, year, months, days, since, range }

/// Days from [from] up to, not including, [to], in the user's timezone.
class AskPeriod {
  const AskPeriod(this.kind, this.from, this.to, {this.length = 1});

  factory AskPeriod.fromJson(Map<String, Object?> json) => AskPeriod(
    PeriodKind.values.byName(json['kind']! as String),
    _date(json['from']! as String),
    _date(json['to']! as String),
    length: json['length'] as int? ?? 1,
  );

  /// Today so far.
  factory AskPeriod.today(CalendarDate today) =>
      AskPeriod(PeriodKind.day, today, today.addDays(1));

  /// This month so far.
  factory AskPeriod.thisMonth(CalendarDate today) =>
      AskPeriod(PeriodKind.month, today.yearMonth.firstDay, today.addDays(1));

  factory AskPeriod.month(YearMonth month, CalendarDate today) => AskPeriod(
    PeriodKind.month,
    month.firstDay,
    _cap(month.next.firstDay, today),
  );

  /// Monday to today.
  factory AskPeriod.thisWeek(CalendarDate today) => AskPeriod(
    PeriodKind.week,
    today.addDays(1 - today.weekday),
    today.addDays(1),
  );

  /// This year so far.
  factory AskPeriod.thisYear(CalendarDate today) => AskPeriod(
    PeriodKind.year,
    CalendarDate(today.year, 1, 1),
    today.addDays(1),
  );

  factory AskPeriod.year(int year, CalendarDate today) => AskPeriod(
    PeriodKind.year,
    CalendarDate(year, 1, 1),
    _cap(CalendarDate(year + 1, 1, 1), today),
  );

  /// The last [count] months, this one included.
  factory AskPeriod.lastMonths(int count, CalendarDate today) => AskPeriod(
    PeriodKind.months,
    today.yearMonth.addMonths(1 - count).firstDay,
    today.addDays(1),
    length: count,
  );

  final PeriodKind kind;
  final CalendarDate from;

  /// The day after the last day.
  final CalendarDate to;

  /// Months or days for [PeriodKind.months] and [PeriodKind.days].
  final int length;

  DateTime get fromInstant => from.startInstant;
  DateTime get toInstant => to.startInstant;

  CalendarDate get lastDay => to.addDays(-1);

  bool contains(CalendarDate date) => !date.isBefore(from) && date.isBefore(to);

  /// Each month the period touches, oldest first.
  List<YearMonth> get months => [
    for (
      var m = from.yearMonth;
      m.compareTo(lastDay.yearMonth) <= 0;
      m = m.next
    )
      m,
  ];

  /// The period before this one of the same size: last month for a month,
  /// last year for a year, the week before for a week. A month or year so
  /// far is compared with the whole of the one before.
  AskPeriod previous() {
    switch (kind) {
      case PeriodKind.day:
        return AskPeriod(kind, from.addDays(-1), from);
      case PeriodKind.week:
        return AskPeriod(kind, from.addDays(-7), from);
      case PeriodKind.month:
        final m = from.yearMonth.previous;
        return AskPeriod(kind, m.firstDay, m.next.firstDay);
      case PeriodKind.year:
        return AskPeriod(
          kind,
          CalendarDate(from.year - 1, 1, 1),
          CalendarDate(from.year, 1, 1),
        );
      case PeriodKind.months:
        final start = from.yearMonth.addMonths(-length);
        return AskPeriod(kind, start.firstDay, from, length: length);
      case PeriodKind.days || PeriodKind.since || PeriodKind.range:
        final days = from.daysUntil(to);
        return AskPeriod(kind, from.addDays(-days), from, length: length);
    }
  }

  /// How the period reads in a heading, such as `October 2026`,
  /// `Jan to Nov 2026` or `Mon 9 to Fri 13 Nov`.
  String label(CalendarDate today) {
    final last = lastDay;
    switch (kind) {
      case PeriodKind.day:
        if (from == today) return 'Today';
        if (from == today.addDays(-1)) return 'Yesterday';
        return dateLabel(from);
      case PeriodKind.month:
        return '${_monthNames[from.month - 1]} ${from.year}';
      case PeriodKind.year:
        if (from.yearMonth == last.yearMonth) return monthLabel(from.yearMonth);
        return '${monthName(from.yearMonth)} to '
            '${monthName(last.yearMonth)} ${last.year}';
      case PeriodKind.week || PeriodKind.days:
        return '${_weekdays[from.weekday - 1]} ${from.day}'
            '${from.month == last.month ? '' : ' ${monthName(from.yearMonth)}'}'
            ' to ${_weekdays[last.weekday - 1]} ${last.day} '
            '${monthName(last.yearMonth)}';
      case PeriodKind.range:
        return _range(from, last);
      case PeriodKind.months || PeriodKind.since:
        final sameYear = from.year == last.year;
        return '${monthName(from.yearMonth)}${sameYear ? '' : ' ${from.year}'}'
            ' to ${monthName(last.yearMonth)} ${last.year}';
    }
  }

  /// How the period reads inside a sentence, such as `last month`,
  /// `in October` or `this year`.
  String phrase(CalendarDate today) {
    final thisMonth = today.yearMonth;
    switch (kind) {
      case PeriodKind.day:
        if (from == today) return 'today';
        if (from == today.addDays(-1)) return 'yesterday';
        return 'on ${dayLabel(from, thisYear: today.year)}';
      case PeriodKind.week:
        if (from == today.addDays(1 - today.weekday)) return 'this week';
        if (from == today.addDays(-6 - today.weekday)) return 'last week';
        return 'that week';
      case PeriodKind.month:
        final m = from.yearMonth;
        if (m == thisMonth) return 'this month';
        if (m == thisMonth.previous) return 'last month';
        return 'in ${_monthNames[m.month - 1]}'
            '${m.year == today.year ? '' : ' ${m.year}'}';
      case PeriodKind.year:
        if (from.year == today.year) return 'this year';
        if (from.year == today.year - 1) return 'last year';
        return 'in ${from.year}';
      case PeriodKind.months:
        return 'in the last $length months';
      case PeriodKind.days:
        return 'in the last $length days';
      case PeriodKind.since:
        return 'since ${_monthNames[from.month - 1]}';
      case PeriodKind.range:
        return 'from ${_range(from, lastDay)}';
    }
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'from': _key(from),
    'to': _key(to),
    'length': length,
  };

  @override
  bool operator ==(Object other) =>
      other is AskPeriod &&
      other.kind == kind &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(kind, from, to);

  @override
  String toString() => 'AskPeriod(${kind.name} $from..$to)';

  static CalendarDate _cap(CalendarDate end, CalendarDate today) {
    final tomorrow = today.addDays(1);
    return end.isAfter(tomorrow) ? tomorrow : end;
  }
}

/// `1 to 27 Oct`, or `28 Sep to 3 Oct`.
String _range(CalendarDate from, CalendarDate last) =>
    from.yearMonth == last.yearMonth
    ? '${from.day} to ${last.day} ${monthName(last.yearMonth)}'
    : '${from.day} ${monthName(from.yearMonth)} to ${last.day} '
          '${monthName(last.yearMonth)}';

String _key(CalendarDate d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

CalendarDate _date(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return CalendarDate(parts[0], parts[1], parts[2]);
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

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

const _monthWords = {
  'january': 1,
  'jan': 1,
  'february': 2,
  'feb': 2,
  'march': 3,
  'mar': 3,
  'april': 4,
  'apr': 4,
  'may': 5,
  'june': 6,
  'jun': 6,
  'july': 7,
  'jul': 7,
  'august': 8,
  'aug': 8,
  'september': 9,
  'sept': 9,
  'sep': 9,
  'october': 10,
  'oct': 10,
  'november': 11,
  'nov': 11,
  'december': 12,
  'dec': 12,
};

const _numberWords = {
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
};

/// A period found in a question, and where its words sit.
class PeriodMatch {
  const PeriodMatch(this.period, this.start, this.end, this.text);

  final AskPeriod period;
  final int start;
  final int end;
  final String text;
}

final _monthAlt =
    (_monthWords.keys.toList()..sort((a, b) => b.length.compareTo(a.length)))
        .join('|');
final _countAlt = '[0-9]{1,3}|${_numberWords.keys.join('|')}';

final _rules = <(RegExp, AskPeriod? Function(RegExpMatch, CalendarDate))>[
  (
    RegExp('\\b(?:in |over )?(?:the )?(?:last|past) ($_countAlt) months?\\b'),
    (m, today) {
      final n = _count(m.group(1)!);
      return n == null || n < 1 ? null : AskPeriod.lastMonths(n, today);
    },
  ),
  (
    RegExp('\\b(?:in |over )?(?:the )?(?:last|past) ($_countAlt) days?\\b'),
    (m, today) {
      final n = _count(m.group(1)!);
      if (n == null || n < 1) return null;
      return AskPeriod(
        PeriodKind.days,
        today.addDays(1 - n),
        today.addDays(1),
        length: n,
      );
    },
  ),
  (
    RegExp('\\bsince ($_monthAlt)(?: ([0-9]{4}))?\\b'),
    (m, today) {
      final month = _monthOf(m.group(1)!, m.group(2), today);
      return AskPeriod(PeriodKind.since, month.firstDay, today.addDays(1));
    },
  ),
  (
    RegExp(r'\b(?:so far )?this week\b|\bwiki hii\b'),
    (m, today) => AskPeriod.thisWeek(today),
  ),
  (
    RegExp(r'\blast week\b|\bwiki (?:iliyopita|jana)\b'),
    (m, today) {
      final start = today.addDays(-6 - today.weekday);
      return AskPeriod(PeriodKind.week, start, start.addDays(7));
    },
  ),
  (
    RegExp(r'\b(?:so far )?this month(?: so far)?\b|\bmwezi huu\b'),
    (m, today) => AskPeriod.thisMonth(today),
  ),
  (
    RegExp(r'\blast month\b|\bmwezi (?:uliopita|jana)\b|\bprevious month\b'),
    (m, today) => AskPeriod.month(today.yearMonth.previous, today),
  ),
  (
    RegExp(r'\b(?:so far )?this year\b|\bmwaka huu\b'),
    (m, today) => AskPeriod.thisYear(today),
  ),
  (
    RegExp(r'\blast year\b|\bmwaka (?:uliopita|jana)\b'),
    (m, today) => AskPeriod.year(today.year - 1, today),
  ),
  (RegExp(r'\btoday\b|\bleo\b'), (m, today) => AskPeriod.today(today)),
  (
    RegExp(r'\byesterday\b|\bjana\b'),
    (m, today) {
      final day = today.addDays(-1);
      return AskPeriod(PeriodKind.day, day, today);
    },
  ),
  (
    RegExp('\\b(?:in |for |during )?($_monthAlt)(?:,? ([0-9]{4}))?\\b'),
    (m, today) {
      final word = m.group(1)!;
      // "may" and "march" are also plain words; take them only with a year
      // or after "in".
      final plain = word == 'may' || word == 'mar' || word == 'march';
      if (plain && m.group(2) == null && !m.group(0)!.startsWith('in ')) {
        return null;
      }
      return AskPeriod.month(_monthOf(word, m.group(2), today), today);
    },
  ),
  (
    RegExp(r'\b(?:in |for |during )?(20[0-9]{2})\b'),
    (m, today) {
      final year = int.parse(m.group(1)!);
      if (year > today.year) return null;
      return AskPeriod.year(year, today);
    },
  ),
];

int? _count(String word) => int.tryParse(word) ?? _numberWords[word];

YearMonth _monthOf(String word, String? year, CalendarDate today) {
  final month = _monthWords[word]!;
  if (year != null) return YearMonth(int.parse(year), month);
  // The most recent one: November asked in March is last November.
  return month > today.month
      ? YearMonth(today.year - 1, month)
      : YearMonth(today.year, month);
}

/// The first period named in [question], or null when it names none.
PeriodMatch? findPeriod(String question, CalendarDate today) {
  final text = question.toLowerCase();
  PeriodMatch? best;
  for (final (pattern, make) in _rules) {
    for (final m in pattern.allMatches(text)) {
      final period = make(m, today);
      if (period == null) continue;
      if (best == null || m.start < best.start) {
        best = PeriodMatch(period, m.start, m.end, m.group(0)!);
      }
      break;
    }
    // Earlier rules are more specific: keep the first rule's match when it
    // covers the same place.
  }
  return best;
}

/// The period [text] names, such as `last month`, or null.
AskPeriod? parsePeriod(String text, CalendarDate today) =>
    findPeriod(text, today)?.period;
