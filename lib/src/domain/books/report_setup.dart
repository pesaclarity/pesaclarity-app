import '../ledger/activity_feed.dart';
import '../time/calendar.dart';
import 'business_report.dart';

/// Who a report is for; each ticks its own sections to start.
enum ReportAudience {
  sacco('A Sacco or loan'),
  accountant('An accountant'),
  me('Just me');

  const ReportAudience(this.label);

  final String label;

  Set<ReportSection> get sections => switch (this) {
    ReportAudience.sacco => const {
      ReportSection.profitAndLoss,
      ReportSection.byWay,
      ReportSection.customers,
      ReportSection.suppliers,
      ReportSection.balance,
    },
    ReportAudience.accountant => ReportSection.values.toSet(),
    ReportAudience.me => const {
      ReportSection.profitAndLoss,
      ReportSection.byWay,
      ReportSection.bestSellers,
      ReportSection.insights,
    },
  };
}

/// What a report can hold, in the order it prints.
enum ReportSection {
  profitAndLoss('Profit and loss'),
  byWay('Sales by how people paid'),
  customers('Customers who owe you'),
  suppliers('Suppliers you owe'),
  balance('Balance summary'),
  bestSellers('Best sellers'),
  stock('Stock'),
  cashBook('Cash book, every entry'),
  insights('Insights');

  const ReportSection(this.label);

  final String label;
}

/// The business's details on a report's cover.
class ReportCover {
  const ReportCover({this.business, this.owner, this.phone, this.place});

  final String? business;
  final String? owner;
  final String? phone;
  final String? place;

  /// `Vegetable stall · Wanjiru K. · Gikomba`, leaving out what is empty.
  String line(String businessName) => [
    business ?? businessName,
    ?owner,
    ?phone,
    ?place,
  ].where((s) => s.trim().isNotEmpty).join(' · ');

  Map<String, Object?> toJson() => {
    'business': ?business,
    'owner': ?owner,
    'phone': ?phone,
    'place': ?place,
  };

  static ReportCover fromJson(Object? json) {
    if (json is! Map) return const ReportCover();
    String? text(String key) {
      final v = json[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    return ReportCover(
      business: text('business'),
      owner: text('owner'),
      phone: text('phone'),
      place: text('place'),
    );
  }
}

/// A report the owner set up and saved, such as "Monthly Sacco report".
class ReportSetup {
  const ReportSetup({
    required this.name,
    required this.audience,
    required this.sections,
    this.range = ReportRange.lastMonth,
    this.from,
    this.to,
  });

  final String name;
  final ReportAudience audience;
  final Set<ReportSection> sections;

  /// Null when the report has its own dates, [from] up to [to].
  final ReportRange? range;
  final CalendarDate? from;

  /// The day after the last day.
  final CalendarDate? to;

  ReportPeriod periodOn(CalendarDate today) {
    final r = range;
    final f = from;
    final t = to;
    if (r == null && f != null && t != null) {
      return ReportPeriod(f, t, 'Dates');
    }
    return periodFor(r ?? ReportRange.lastMonth, today);
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'audience': audience.name,
    'sections': [
      for (final s in ReportSection.values)
        if (sections.contains(s)) s.name,
    ],
    'range': ?range?.name,
    if (range == null)
      'from': ?(from == null ? null : formatCalendarDate(from!)),
    if (range == null) 'to': ?(to == null ? null : formatCalendarDate(to!)),
  };

  static ReportSetup? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final audience = ReportAudience.values
        .where((a) => a.name == json['audience'])
        .firstOrNull;
    final names = json['sections'];
    final sections = {
      if (names is List)
        for (final s in ReportSection.values)
          if (names.contains(s.name)) s,
    };
    final range = ReportRange.values
        .where((r) => r.name == json['range'])
        .firstOrNull;
    CalendarDate? date(String key) {
      final v = json[key];
      return v is String ? parseCalendarDate(v) : null;
    }

    final from = date('from');
    final to = date('to');
    return ReportSetup(
      name: name.trim(),
      audience: audience ?? ReportAudience.sacco,
      sections: sections.isEmpty
          ? (audience ?? ReportAudience.sacco).sections
          : sections,
      range: range == null && from != null && to != null
          ? null
          : range ?? ReportRange.lastMonth,
      from: range == null ? from : null,
      to: range == null ? to : null,
    );
  }
}

/// The cover and the saved reports of one space.
class ReportSettings {
  const ReportSettings({
    this.cover = const ReportCover(),
    this.saved = const [],
  });

  final ReportCover cover;
  final List<ReportSetup> saved;

  ReportSettings copyWith({ReportCover? cover, List<ReportSetup>? saved}) =>
      ReportSettings(cover: cover ?? this.cover, saved: saved ?? this.saved);

  /// [setup] saved, replacing one of the same name.
  ReportSettings withSaved(ReportSetup setup) => copyWith(
    saved: [
      for (final s in saved)
        if (s.name.toLowerCase() != setup.name.toLowerCase()) s,
      setup,
    ],
  );

  Map<String, Object?> toJson() => {
    'cover': cover.toJson(),
    'saved': [for (final s in saved) s.toJson()],
  };

  static ReportSettings fromJson(Map<String, Object?>? json) {
    if (json == null) return const ReportSettings();
    final saved = json['saved'];
    return ReportSettings(
      cover: ReportCover.fromJson(json['cover']),
      saved: [
        if (saved is List)
          for (final s in saved) ?ReportSetup.fromJson(s),
      ],
    );
  }
}
