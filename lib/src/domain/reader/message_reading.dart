import 'reader_tokens.dart';

/// The fields the reader finds, in the model's label order (index 0 is
/// `other`).
enum ReaderField {
  other,
  amount,
  counterparty,
  date,
  time,
  balance,
  reference,
  fee,
}

/// What a whole message is, in the model's label order.
enum MessageKind { moneyOut, moneyIn, notTransaction }

/// One field found in a message.
class FieldReading {
  const FieldReading({
    required this.field,
    required this.text,
    required this.start,
    required this.end,
    required this.confidence,
  });

  final ReaderField field;

  /// The message text from the field's first token to its last.
  final String text;
  final int start;
  final int end;

  /// The lowest token probability in the field, 0 to 1.
  final double confidence;
}

/// What the reader made of a message. Every value is a suggestion for the
/// person to confirm.
class MessageReading {
  const MessageReading({
    required this.kind,
    required this.kindConfidence,
    required this.fields,
  });

  final MessageKind kind;
  final double kindConfidence;

  /// The first and most confident run of each field found.
  final Map<ReaderField, FieldReading> fields;
}

/// Reads bank and wallet messages no parser rule matched.
abstract interface class MessageReader {
  MessageReading read(String message);

  void close();
}

/// Turns per-token label probabilities into fields: each field is the
/// longest run of consecutive tokens with that label; when a label occurs
/// in more than one run, the most confident run wins.
MessageReading decodeReading(
  String message,
  List<MessageToken> tokens,
  List<List<double>> fieldProbabilities,
  List<double> kindProbabilities,
) {
  final count = tokens.length < readerMaxTokens
      ? tokens.length
      : readerMaxTokens;
  final labels = <int>[];
  final scores = <double>[];
  for (var i = 0; i < count; i++) {
    final probs = fieldProbabilities[i];
    var best = 0;
    for (var j = 1; j < probs.length; j++) {
      if (probs[j] > probs[best]) best = j;
    }
    labels.add(best);
    scores.add(probs[best]);
  }

  final fields = <ReaderField, FieldReading>{};
  var i = 0;
  while (i < count) {
    final label = labels[i];
    var j = i;
    var confidence = 1.0;
    while (j < count && labels[j] == label) {
      if (scores[j] < confidence) confidence = scores[j];
      j++;
    }
    if (label > 0 && label < ReaderField.values.length) {
      final field = ReaderField.values[label];
      final reading = FieldReading(
        field: field,
        text: message.substring(tokens[i].start, tokens[j - 1].end),
        start: tokens[i].start,
        end: tokens[j - 1].end,
        confidence: confidence,
      );
      final current = fields[field];
      if (current == null || reading.confidence > current.confidence) {
        fields[field] = reading;
      }
    }
    i = j;
  }

  var kind = 0;
  for (var k = 1; k < kindProbabilities.length; k++) {
    if (kindProbabilities[k] > kindProbabilities[kind]) kind = k;
  }
  return MessageReading(
    kind: MessageKind.values[kind],
    kindConfidence: kindProbabilities[kind],
    fields: fields,
  );
}
