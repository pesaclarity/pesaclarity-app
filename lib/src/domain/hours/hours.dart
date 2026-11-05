import '../time/calendar.dart';

/// Time logged for a client.
class HourEntry {
  const HourEntry({
    required this.id,
    required this.client,
    required this.what,
    required this.day,
    required this.minutes,
    this.project,
    this.billable = true,
    this.rateMinor,
    this.invoiceId,
  });

  final int id;
  final String client;
  final String? project;
  final String what;
  final CalendarDate day;
  final int minutes;
  final bool billable;

  /// The rate an hour.
  final int? rateMinor;
  final int? invoiceId;

  bool get toBill => billable && invoiceId == null;

  /// What it bills: hours × rate, or 0 when not billed or without a rate.
  int get amountMinor =>
      billable && rateMinor != null ? (rateMinor! * minutes / 60).round() : 0;
}

/// `1.5`, `0.75`, `8`: hours from [minutes].
String hoursText(int minutes) {
  final whole = minutes ~/ 60;
  final rest = minutes % 60;
  if (rest == 0) return '$whole';
  final part = (rest * 100 / 60).round().toString().padLeft(2, '0');
  return '$whole.${part.replaceFirst(RegExp(r'0$'), '')}';
}

/// Minutes from what was typed: `1.5`, `1,5`, `1:30` or `90m`, to the
/// nearest quarter hour; null when it is not a time above zero.
int? minutesFrom(String text) {
  final t = text.trim().toLowerCase().replaceAll(',', '.');
  if (t.isEmpty) return null;
  int? minutes;
  final clock = RegExp(r'^(\d+):(\d{1,2})$').firstMatch(t);
  final mins = RegExp(r'^(\d+)\s*m(in)?$').firstMatch(t);
  if (clock != null) {
    minutes = int.parse(clock[1]!) * 60 + int.parse(clock[2]!);
  } else if (mins != null) {
    minutes = int.parse(mins[1]!);
  } else {
    final h = double.tryParse(t.replaceFirst(RegExp(r'\s*h$'), ''));
    if (h == null) return null;
    minutes = (h * 60).round();
  }
  final quarter = ((minutes / 15).round()) * 15;
  return quarter <= 0 ? null : quarter;
}

/// `Bidii Traders` for `Bidii Traders Ltd`.
String clientName(String client) => client.trim().replaceFirst(
  RegExp(r'\s+(ltd\.?|limited|inc\.?|llc|plc)$', caseSensitive: false),
  '',
);

/// `Bidii` for `Bidii Traders Ltd`: how splits name a client.
String clientShort(String client) =>
    clientName(client).split(RegExp(r'\s+')).first;

/// One day's hours.
class DayHours {
  DayHours(this.day, Iterable<HourEntry> entries)
    : entries = [
        for (final e in entries)
          if (e.day == day) e,
      ];

  final CalendarDate day;
  final List<HourEntry> entries;

  int get totalMinutes => entries.fold(0, (sum, e) => sum + e.minutes);

  /// Billable minutes by client, in the order they first appear.
  Map<String, int> get toBill {
    final out = <String, int>{};
    for (final e in entries) {
      if (e.billable) out[e.client] = (out[e.client] ?? 0) + e.minutes;
    }
    return out;
  }

  int get notBilledMinutes =>
      entries.where((e) => !e.billable).fold(0, (sum, e) => sum + e.minutes);
}

/// A project's hours in a period, at its rate.
class ProjectHours {
  const ProjectHours({
    required this.client,
    required this.project,
    required this.minutes,
    required this.amountMinor,
    this.rateMinor,
  });

  final String client;
  final String? project;
  final int minutes;
  final int? rateMinor;
  final int amountMinor;
}

/// Billable hours grouped by client and project, largest amount first.
List<ProjectHours> byProject(Iterable<HourEntry> entries) {
  final groups = <(String, String?), List<HourEntry>>{};
  for (final e in entries) {
    if (!e.billable) continue;
    groups.putIfAbsent((e.client, e.project), () => []).add(e);
  }
  final out = [
    for (final MapEntry(key: (client, project), value: list) in groups.entries)
      ProjectHours(
        client: client,
        project: project,
        minutes: list.fold(0, (sum, e) => sum + e.minutes),
        amountMinor: list.fold(0, (sum, e) => sum + e.amountMinor),
        rateMinor: list
            .map((e) => e.rateMinor)
            .whereType<int>()
            .toSet()
            .singleOrNull,
      ),
  ]..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
  return out;
}

/// The Monday of [day]'s week.
CalendarDate weekStart(CalendarDate day) => day.addDays(1 - day.weekday);

/// A week of hours, Monday to Sunday.
class WeekHours {
  WeekHours(this.from, Iterable<HourEntry> entries)
    : entries = [
        for (final e in entries)
          if (!e.day.isBefore(from) && e.day.isBefore(from.addDays(7))) e,
      ];

  final CalendarDate from;
  final List<HourEntry> entries;

  CalendarDate get lastDay => from.addDays(6);

  /// Days with hours logged, in order.
  List<DayHours> get days => [
    for (var i = 0; i < 7; i++)
      if (entries.any((e) => e.day == from.addDays(i)))
        DayHours(from.addDays(i), entries),
  ];

  List<ProjectHours> get projects => byProject(entries);

  int get loggedMinutes => entries.fold(0, (sum, e) => sum + e.minutes);

  int get toBillMinutes =>
      entries.where((e) => e.billable).fold(0, (sum, e) => sum + e.minutes);

  int get notBilledMinutes => loggedMinutes - toBillMinutes;

  /// What was done in the hours not billed, such as `Travel, admin`.
  List<String> get notBilledWhat => [
    ...{
      for (final e in entries)
        if (!e.billable) e.what,
    },
  ];

  int get amountMinor => entries.fold(0, (sum, e) => sum + e.amountMinor);

  /// Hours by client, for "Bidii 27 · Juhudi 4".
  Map<String, int> get byClient {
    final out = <String, int>{};
    for (final e in entries) {
      if (e.billable) out[e.client] = (out[e.client] ?? 0) + e.minutes;
    }
    return out;
  }
}
