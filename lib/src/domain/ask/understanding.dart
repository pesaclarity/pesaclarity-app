/// What a question asks for, as the question reader sees it. The names are
/// the labels `ask-reader.tflite` uses, so they never change once shipped.
enum AskIntent {
  spent,
  received,
  sentTo('sent_to'),
  receivedFrom('received_from'),
  countPayments('count_payments'),
  biggestPayment('biggest_payment'),
  topPayees('top_payees'),
  topCategories('top_categories'),
  trend,
  compare,
  billsDue('bills_due'),
  subscriptions,
  debts,
  lent,
  safeToSpend('safe_to_spend'),
  balance,
  goals,
  incomeSources('income_sources'),
  sales,
  topItems('top_items'),
  profit,
  lowStock('low_stock'),
  whoOwesMe('who_owes_me'),
  refine,
  hi,
  thanks,
  bye,
  help,
  outOfScope('out_of_scope');

  const AskIntent([this._label]);

  final String? _label;

  /// The model's label for this intent.
  String get label => _label ?? name;

  static AskIntent? fromLabel(String label) {
    for (final i in values) {
      if (i.label == label) return i;
    }
    return null;
  }

  /// Small talk: answered with a sentence and suggestions, no lookup.
  bool get isSmallTalk => this == hi || this == thanks || this == bye;

  /// A lookup on the space's own records.
  bool get isLookup =>
      !isSmallTalk && this != help && this != outOfScope && this != refine;
}

/// The kinds of thing a question can name.
enum SlotKind { category, payee, period, item, account, amount }

/// Words in the question that name one slot, with where they sit in it.
class AskSpan {
  const AskSpan(this.kind, this.text, [this.start = 0, this.end = 0]);

  factory AskSpan.fromJson(Map<String, Object?> json) => AskSpan(
    SlotKind.values.byName(json['kind']! as String),
    json['text']! as String,
    json['start'] as int? ?? 0,
    json['end'] as int? ?? 0,
  );

  final SlotKind kind;
  final String text;
  final int start;
  final int end;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'text': text,
    'start': start,
    'end': end,
  };

  @override
  bool operator ==(Object other) =>
      other is AskSpan && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => 'AskSpan(${kind.name}: $text)';
}

/// What the reader made of one question.
class Understanding {
  const Understanding(
    this.intent, {
    this.confidence = 1,
    this.spans = const [],
  });

  factory Understanding.fromJson(Map<String, Object?> json) => Understanding(
    AskIntent.fromLabel(json['intent']! as String) ?? AskIntent.outOfScope,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 1,
    spans: [
      for (final s in json['spans'] as List? ?? const [])
        AskSpan.fromJson((s as Map).cast<String, Object?>()),
    ],
  );

  final AskIntent intent;

  /// From 0 to 1.
  final double confidence;
  final List<AskSpan> spans;

  /// The first span of [kind], if any.
  AskSpan? span(SlotKind kind) {
    for (final s in spans) {
      if (s.kind == kind) return s;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'intent': intent.label,
    'confidence': confidence,
    'spans': [for (final s in spans) s.toJson()],
  };
}

/// Reads a question into an [Understanding]. The rules reader works alone;
/// a trained reader can take its place behind the same interface.
abstract interface class QuestionReader {
  Understanding read(String question);

  void close();
}
