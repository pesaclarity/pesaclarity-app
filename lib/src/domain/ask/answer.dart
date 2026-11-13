import '../time/calendar.dart';
import 'context.dart';
import 'matcher.dart';

/// The kind of reply, which picks its sentences. The names are the labels
/// `ask-writer.tflite` is conditioned on.
enum ReplyKind {
  total,
  totalUp,
  totalDown,
  nothing,
  count,
  biggest,
  topPayees,
  topCategories,
  trend,
  compareUp,
  compareDown,
  compareSame,
  share,
  safeToSpend,
  safeOver,
  noBudget,
  balance,
  debts,
  noDebts,
  lent,
  owesMe,
  nobodyOwes,
  bills,
  noBills,
  subscriptions,
  noSubscriptions,
  goals,
  noGoals,
  incomeSources,
  sales,
  topItems,
  profit,
  loss,
  lowStock,
  noLowStock,
  notFound,
  clarify,
  cant,
  hi,
  thanks,
  bye,
  help,
}

/// One line under an answer, such as a payee and what went to them.
class AskRow {
  const AskRow(this.title, {this.detail, this.amountMinor});

  factory AskRow.fromJson(Map<String, Object?> json) => AskRow(
    json['title']! as String,
    detail: json['detail'] as String?,
    amountMinor: json['amount'] as int?,
  );

  final String title;
  final String? detail;
  final int? amountMinor;

  Map<String, Object?> toJson() => {
    'title': title,
    'detail': ?detail,
    'amount': ?amountMinor,
  };
}

/// One bar of a trend chart.
class AskBar {
  const AskBar(this.label, this.valueMinor, {this.highlight = false});

  factory AskBar.fromJson(Map<String, Object?> json) => AskBar(
    json['label']! as String,
    json['value']! as int,
    highlight: json['highlight'] as bool? ?? false,
  );

  final String label;
  final int valueMinor;
  final bool highlight;

  Map<String, Object?> toJson() => {
    'label': label,
    'value': valueMinor,
    'highlight': highlight,
  };
}

/// A bar chart month by month, or a split bar for part of a whole.
class AskChart {
  const AskChart.bars(this.bars)
    : partMinor = 0,
      wholeMinor = 0,
      partLabel = '',
      restLabel = '';

  const AskChart.share({
    required this.partMinor,
    required this.wholeMinor,
    required this.partLabel,
    required this.restLabel,
  }) : bars = const [];

  factory AskChart.fromJson(Map<String, Object?> json) {
    final bars = json['bars'] as List?;
    if (bars != null) {
      return AskChart.bars([
        for (final b in bars) AskBar.fromJson((b as Map).cast()),
      ]);
    }
    return AskChart.share(
      partMinor: json['part']! as int,
      wholeMinor: json['whole']! as int,
      partLabel: json['partLabel']! as String,
      restLabel: json['restLabel']! as String,
    );
  }

  final List<AskBar> bars;
  final int partMinor;
  final int wholeMinor;
  final String partLabel;
  final String restLabel;

  bool get isShare => bars.isEmpty;

  /// The part's share in whole percent.
  int get partPercent =>
      wholeMinor <= 0 ? 0 : (partMinor * 100 / wholeMinor).round();

  Map<String, Object?> toJson() => isShare
      ? {
          'part': partMinor,
          'whole': wholeMinor,
          'partLabel': partLabel,
          'restLabel': restLabel,
        }
      : {
          'bars': [for (final b in bars) b.toJson()],
        };
}

/// Where an answer's "See all" goes.
enum AskLink {
  activity,
  insights,
  businessInsights,
  debts,
  goals,
  bills,
  stock,
}

/// A reply: the sentence's template and facts, the numbers behind it and
/// what to ask next. Saved whole, so an old answer shows the numbers as
/// they were on [asOf] until updated.
class AskAnswer {
  const AskAnswer({
    required this.kind,
    required this.template,
    required this.asOf,
    this.facts = const {},
    this.headline,
    this.figureMinor,
    this.figureText,
    this.rows = const [],
    this.totalRows = 0,
    this.chart,
    this.choices = const [],
    this.clarifyWord,
    this.askPeriod = false,
    this.suggestions = const [],
    this.context = AskContext.empty,
    this.link,
  });

  factory AskAnswer.fromJson(Map<String, Object?> json) => AskAnswer(
    kind: ReplyKind.values.asNameMap()[json['kind']] ?? ReplyKind.cant,
    template: json['template']! as String,
    asOf: DateTime.parse(json['asOf']! as String),
    facts: (json['facts'] as Map?)?.cast<String, Object>() ?? const {},
    headline: json['headline'] as String?,
    figureMinor: json['figure'] as int?,
    figureText: json['figureText'] as String?,
    rows: [
      for (final r in json['rows'] as List? ?? const [])
        AskRow.fromJson((r as Map).cast()),
    ],
    totalRows: json['totalRows'] as int? ?? 0,
    chart: switch (json['chart']) {
      final Map<Object?, Object?> c => AskChart.fromJson(c.cast()),
      _ => null,
    },
    choices: [
      for (final c in json['choices'] as List? ?? const [])
        AskEntity.fromJson((c as Map).cast()),
    ],
    clarifyWord: json['clarifyWord'] as String?,
    askPeriod: json['askPeriod'] as bool? ?? false,
    suggestions: [
      for (final s in json['suggestions'] as List? ?? const []) s as String,
    ],
    context: switch (json['context']) {
      final Map<Object?, Object?> c => AskContext.fromJson(c.cast()),
      _ => AskContext.empty,
    },
    link: AskLink.values.asNameMap()[json['link']],
  );

  final ReplyKind kind;

  /// The sentence with `{placeholders}`, filled from [facts] when shown.
  final String template;

  /// Values for the template. `amount` and `change` are money in minor
  /// units; the rest are text.
  final Map<String, Object> facts;

  /// When the numbers were worked out.
  final DateTime asOf;

  /// What the figure is, such as `Food · October 2026`.
  final String? headline;
  final int? figureMinor;

  /// A name in place of an amount, such as the item that sold most.
  final String? figureText;
  final List<AskRow> rows;

  /// How many rows there are in all; more than [rows] shows "See all".
  final int totalRows;
  final AskChart? chart;

  /// For "Which one do you mean?".
  final List<AskEntity> choices;

  /// The word that matched more than one, learned as a shortcut once the
  /// person picks.
  final String? clarifyWord;

  /// Whether the clarify card asks for when as well.
  final bool askPeriod;

  /// Follow-ups to tap.
  final List<String> suggestions;

  /// The lookup this answers, for Update and follow-ups.
  final AskContext context;
  final AskLink? link;

  CalendarDate get asOfDate => CalendarDate.local(asOf);

  /// Whether it has numbers that can be worked out again.
  bool get canUpdate =>
      context.intent != null &&
      kind != ReplyKind.clarify &&
      kind != ReplyKind.cant;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'template': template,
    'asOf': asOf.toIso8601String(),
    'facts': facts,
    'headline': ?headline,
    'figure': ?figureMinor,
    'figureText': ?figureText,
    if (rows.isNotEmpty) 'rows': [for (final r in rows) r.toJson()],
    'totalRows': totalRows,
    'chart': ?chart?.toJson(),
    if (choices.isNotEmpty) 'choices': [for (final c in choices) c.toJson()],
    'clarifyWord': ?clarifyWord,
    'askPeriod': askPeriod,
    if (suggestions.isNotEmpty) 'suggestions': suggestions,
    'context': context.toJson(),
    'link': ?link?.name,
  };
}
