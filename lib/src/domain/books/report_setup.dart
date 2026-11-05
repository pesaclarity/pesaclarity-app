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

  /// An accountant gets every entry; the others, totals.
  ReportDetail get detail => this == ReportAudience.accountant
      ? ReportDetail.everyEntry
      : ReportDetail.totals;

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

/// How much a report shows: totals only, or every entry.
enum ReportDetail {
  totals('Totals only'),
  everyEntry('Every entry');

  const ReportDetail(this.label);

  final String label;
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
  cashBook('Cash book'),
  tax('Tax estimate'),
  insights('Insights');

  const ReportSection(this.label);

  final String label;
}

/// How a report's first page looks.
enum ReportCoverStyle {
  strip('Thin strip'),
  band('Full band'),
  plain('Plain');

  const ReportCoverStyle(this.label);

  final String label;
}

/// The colour a report prints in.
enum ReportColour {
  brand('Red'),
  formal('Grey and black');

  const ReportColour(this.label);

  final String label;
}

/// How long a report is.
enum ReportLength {
  full('Full report'),
  summary('One-page summary');

  const ReportLength(this.label);

  final String label;
}

/// The words a report uses for its headings and totals.
enum ReportWording {
  plain('Everyday words'),
  formal('Accounting terms');

  const ReportWording(this.label);

  final String label;
}

/// How a report looks. The defaults are the app's usual report.
class ReportStyle {
  const ReportStyle({
    this.cover = ReportCoverStyle.strip,
    this.colour = ReportColour.brand,
    this.length = ReportLength.full,
    this.wording = ReportWording.plain,
    this.branding = true,
    this.compare = false,
    this.charts = false,
    this.signature = false,
    this.kraPin = false,
    this.permit = false,
  });

  final ReportCoverStyle cover;
  final ReportColour colour;
  final ReportLength length;
  final ReportWording wording;

  /// "Made on this phone by Pesa Clarity" at the foot of each page.
  final bool branding;

  /// The period before, next to this one.
  final bool compare;

  /// Bars for how people paid, sales by day and the profit trend.
  final bool charts;

  /// A line to sign at the end.
  final bool signature;

  /// The KRA PIN from Receipts and invoices, on the cover.
  final bool kraPin;

  /// The business permit number, on the cover.
  final bool permit;

  /// `Full band · Grey and black · One-page summary`, leaving out defaults.
  String get summary {
    final parts = [
      if (cover != ReportCoverStyle.strip) cover.label,
      if (colour != ReportColour.brand) colour.label,
      if (length != ReportLength.full) length.label,
      if (wording != ReportWording.plain) wording.label,
      if (compare) 'Compared',
      if (charts) 'Charts',
    ];
    return parts.isEmpty ? 'The usual look' : parts.join(' · ');
  }

  ReportStyle copyWith({
    ReportCoverStyle? cover,
    ReportColour? colour,
    ReportLength? length,
    ReportWording? wording,
    bool? branding,
    bool? compare,
    bool? charts,
    bool? signature,
    bool? kraPin,
    bool? permit,
  }) => ReportStyle(
    cover: cover ?? this.cover,
    colour: colour ?? this.colour,
    length: length ?? this.length,
    wording: wording ?? this.wording,
    branding: branding ?? this.branding,
    compare: compare ?? this.compare,
    charts: charts ?? this.charts,
    signature: signature ?? this.signature,
    kraPin: kraPin ?? this.kraPin,
    permit: permit ?? this.permit,
  );

  Map<String, Object?> toJson() => {
    'cover': cover.name,
    'colour': colour.name,
    'length': length.name,
    'wording': wording.name,
    'branding': branding,
    'compare': compare,
    'charts': charts,
    'signature': signature,
    'kraPin': kraPin,
    'permit': permit,
  };

  static ReportStyle fromJson(Object? json) {
    if (json is! Map) return const ReportStyle();
    T pick<T extends Enum>(List<T> values, String key, T fallback) =>
        values.where((v) => v.name == json[key]).firstOrNull ?? fallback;
    bool flag(String key, {required bool fallback}) {
      final v = json[key];
      return v is bool ? v : fallback;
    }

    return ReportStyle(
      cover: pick(ReportCoverStyle.values, 'cover', ReportCoverStyle.strip),
      colour: pick(ReportColour.values, 'colour', ReportColour.brand),
      length: pick(ReportLength.values, 'length', ReportLength.full),
      wording: pick(ReportWording.values, 'wording', ReportWording.plain),
      branding: flag('branding', fallback: true),
      compare: flag('compare', fallback: false),
      charts: flag('charts', fallback: false),
      signature: flag('signature', fallback: false),
      kraPin: flag('kraPin', fallback: false),
      permit: flag('permit', fallback: false),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReportStyle && _equal(toJson(), other.toJson());

  @override
  int get hashCode => Object.hashAll(toJson().values);
}

bool _equal(Map<String, Object?> a, Map<String, Object?> b) =>
    a.length == b.length && a.keys.every((k) => a[k] == b[k]);

/// The business's details on a report's cover.
class ReportCover {
  const ReportCover({
    this.business,
    this.owner,
    this.phone,
    this.place,
    this.permit,
  });

  final String? business;
  final String? owner;
  final String? phone;
  final String? place;

  /// The business permit number, shown when the report asks for it.
  final String? permit;

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
    'permit': ?permit,
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
      permit: text('permit'),
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
    this.detail = ReportDetail.totals,
    this.style = const ReportStyle(),
  });

  final String name;
  final ReportAudience audience;
  final Set<ReportSection> sections;
  final ReportDetail detail;
  final ReportStyle style;

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
    'detail': detail.name,
    'style': style.toJson(),
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
      detail:
          ReportDetail.values
              .where((d) => d.name == json['detail'])
              .firstOrNull ??
          (audience ?? ReportAudience.sacco).detail,
      style: ReportStyle.fromJson(json['style']),
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
