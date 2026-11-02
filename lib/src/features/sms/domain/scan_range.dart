import 'dart:math';

import '../../../domain/ledger/activity_feed.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/format/date_labels.dart';

/// How far back the first scan of an account reads.
enum ScanPeriod {
  all('All messages'),
  months3('Last 3 months'),
  months6('Last 6 months'),
  months12('Last 12 months'),
  since('From a date');

  const ScanPeriod(this.label);

  final String label;

  int? get months => switch (this) {
    months3 => 3,
    months6 => 6,
    months12 => 12,
    _ => null,
  };
}

/// The period the person chose to read their messages from. New messages
/// are always added, whatever the choice.
class ScanRange {
  const ScanRange(this.period, {this.since});

  /// Reads a range written by [toJson]; anything unknown is [all].
  factory ScanRange.fromJson(Map<String, Object?>? json) {
    final period = ScanPeriod.values
        .where((p) => p.name == json?['period'])
        .firstOrNull;
    final since = switch (json?['since']) {
      final String s => DateTime.tryParse(s),
      _ => null,
    };
    if (period == null) return all;
    if (period == ScanPeriod.since) {
      return since == null
          ? all
          : ScanRange(
              period,
              since: CalendarDate(since.year, since.month, since.day),
            );
    }
    return ScanRange(period);
  }

  /// Every message on the phone: the default.
  static const all = ScanRange(ScanPeriod.all);

  final ScanPeriod period;

  /// The first day read, for [ScanPeriod.since].
  final CalendarDate? since;

  /// The first day read on [today]; null for every message.
  CalendarDate? firstDay(CalendarDate today) {
    final months = period.months;
    if (months != null) {
      final ym = today.yearMonth.addMonths(-months);
      return CalendarDate(ym.year, ym.month, min(today.day, ym.dayCount));
    }
    return period == ScanPeriod.since ? since : null;
  }

  /// "All messages", "Last 3 months", "From 5 Mar 2026".
  String get label => period == ScanPeriod.since && since != null
      ? 'From ${shortDate(since!)} ${since!.year}'
      : period.label;

  Map<String, Object?> toJson() => {
    'period': period.name,
    if (since != null) 'since': formatCalendarDate(since!),
  };

  @override
  bool operator ==(Object other) =>
      other is ScanRange && other.period == period && other.since == since;

  @override
  int get hashCode => Object.hash(period, since);
}
