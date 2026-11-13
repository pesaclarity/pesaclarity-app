import 'matcher.dart';
import 'periods.dart';
import 'understanding.dart';

/// What the conversation is about now: what is asked, who or what it is
/// about, and when. Shown as tags above the box.
class AskContext {
  const AskContext({
    this.intent,
    this.entities = const {},
    this.period,
    this.at,
  });

  factory AskContext.fromJson(Map<String, Object?> json) => AskContext(
    intent: switch (json['intent']) {
      final String label => AskIntent.fromLabel(label),
      _ => null,
    },
    entities: {
      for (final e in json['entities'] as List? ?? const [])
        if (AskEntity.fromJson((e as Map).cast<String, Object?>())
            case final entity)
          entity.kind: entity,
    },
    period: switch (json['period']) {
      final Map<Object?, Object?> p => AskPeriod.fromJson(
        p.cast<String, Object?>(),
      ),
      _ => null,
    },
    at: switch (json['at']) {
      final String at => DateTime.parse(at),
      _ => null,
    },
  );

  static const empty = AskContext();

  /// After this long away, a question starts afresh.
  static const idle = Duration(minutes: 30);

  final AskIntent? intent;
  final Map<SlotKind, AskEntity> entities;
  final AskPeriod? period;

  /// When it last changed.
  final DateTime? at;

  bool get isEmpty => intent == null && entities.isEmpty && period == null;

  /// Whether it has gone stale by [now].
  bool expired(DateTime now) => at != null && now.difference(at!) >= idle;

  /// This context with the question's [intent], [entities] and [period]
  /// merged in. A refining question changes only what it names; a question
  /// on a new topic starts afresh.
  AskContext merge({
    required AskIntent intent,
    required Map<SlotKind, AskEntity> named,
    required AskPeriod? period,
    required DateTime now,
  }) {
    final base = expired(now) ? empty : this;
    final follows =
        intent == AskIntent.refine ||
        (base.intent != null &&
            named.isEmpty &&
            _sameTopic(base.intent!, intent));
    if (!follows || base.intent == null) {
      return AskContext(
        intent: intent == AskIntent.refine ? base.intent : intent,
        entities: named,
        period: period,
        at: now,
      );
    }
    return AskContext(
      intent: intent == AskIntent.refine ? base.intent : intent,
      entities: {...base.entities, ...named},
      period: period ?? base.period,
      at: now,
    );
  }

  /// Without [kind]: a tag the person dropped.
  AskContext without(SlotKind kind, DateTime now) => AskContext(
    intent: intent,
    entities: {
      for (final e in entities.entries)
        if (e.key != kind) e.key: e.value,
    },
    period: kind == SlotKind.period ? null : period,
    at: now,
  );

  AskContext withEntity(AskEntity entity, DateTime now) => AskContext(
    intent: intent,
    entities: {...entities, entity.kind: entity},
    period: period,
    at: now,
  );

  AskContext withPeriod(AskPeriod period, DateTime now) =>
      AskContext(intent: intent, entities: entities, period: period, at: now);

  Map<String, Object?> toJson() => {
    'intent': ?intent?.label,
    'entities': [for (final e in entities.values) e.toJson()],
    'period': ?period?.toJson(),
    'at': ?at?.toIso8601String(),
  };

  /// A question that names nothing new and asks the same thing, or a new
  /// view of it ("Compare with last year", "How many times?"), keeps what
  /// and who the conversation is about.
  static bool _sameTopic(AskIntent a, AskIntent b) {
    const views = {
      AskIntent.countPayments,
      AskIntent.biggestPayment,
      AskIntent.trend,
      AskIntent.compare,
      AskIntent.topPayees,
    };
    return a == b || views.contains(b);
  }
}
