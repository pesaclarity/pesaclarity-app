import 'dart:convert';

import 'message_reading.dart';
import 'reader_tokens.dart';

/// One part of a [ReadingTemplate]: either a token that must appear as is
/// (by its hash key, so `1,250.00` matches any `9,999.99`), or a slot that
/// holds a field and takes one or more tokens.
class TemplatePart {
  const TemplatePart.literal(String this.key) : field = null;
  const TemplatePart.slot(ReaderField this.field) : key = null;

  final String? key;
  final ReaderField? field;

  Object toJson() => key != null ? {'k': key} : {'f': field!.name};

  static TemplatePart fromJson(Map<String, Object?> json) => json['k'] != null
      ? TemplatePart.literal(json['k']! as String)
      : TemplatePart.slot(ReaderField.values.byName(json['f']! as String));
}

/// How a token outside the fields must match: by its hash key, except
/// codes of letters and digits (receipts, IDs), which differ in every
/// message and match any code.
String templateKey(MessageToken token) =>
    token.shape == TokenShape.mixed ? '#mixed' : hashKey(token.text);

/// "Read messages like this the same way": the shape of a message the
/// person checked once, with its fields as slots. A later message from the
/// same institution that fits it is read without asking.
class ReadingTemplate {
  const ReadingTemplate({required this.kind, required this.parts});

  /// Learns a template from [message] and the token ranges the person
  /// confirmed for each field, as inclusive `(first, last)` token indexes.
  /// Returns null without an amount, or when two fields overlap.
  static ReadingTemplate? learn(
    String message,
    MessageKind kind,
    Map<ReaderField, (int, int)> fieldTokens,
  ) {
    if (kind == MessageKind.notTransaction ||
        !fieldTokens.containsKey(ReaderField.amount)) {
      return null;
    }
    final tokens = tokenise(message);
    final owner = List<ReaderField?>.filled(tokens.length, null);
    for (final MapEntry(key: field, value: (first, last))
        in fieldTokens.entries) {
      if (first < 0 || last >= tokens.length || first > last) return null;
      for (var i = first; i <= last; i++) {
        if (owner[i] != null) return null;
        owner[i] = field;
      }
    }
    final parts = <TemplatePart>[];
    for (var i = 0; i < tokens.length; i++) {
      final field = owner[i];
      if (field == null) {
        parts.add(TemplatePart.literal(templateKey(tokens[i])));
      } else if (i == 0 || owner[i - 1] != field) {
        parts.add(TemplatePart.slot(field));
      }
    }
    return ReadingTemplate(kind: kind, parts: parts);
  }

  final MessageKind kind;
  final List<TemplatePart> parts;

  /// Reads [message] if it fits this template, else null. Fields come back
  /// with confidence 1: the person confirmed this layout.
  MessageReading? read(String message) {
    final tokens = tokenise(message);
    final keys = [for (final t in tokens) templateKey(t)];
    final spans = <ReaderField, (int, int)>{};
    final failed = <(int, int)>{};

    // Matches parts[p..] against tokens[t..], filling [spans].
    bool match(int p, int t) {
      if (p == parts.length) return t == tokens.length;
      if (failed.contains((p, t))) return false;
      final part = parts[p];
      if (part.key != null) {
        final ok =
            t < tokens.length && keys[t] == part.key && match(p + 1, t + 1);
        if (!ok) failed.add((p, t));
        return ok;
      }
      for (var end = t; end < tokens.length; end++) {
        spans[part.field!] = (t, end);
        if (match(p + 1, end + 1)) return true;
      }
      spans.remove(part.field);
      failed.add((p, t));
      return false;
    }

    if (!match(0, 0)) return null;
    return MessageReading(
      kind: kind,
      kindConfidence: 1,
      fields: {
        for (final MapEntry(key: field, value: (first, last)) in spans.entries)
          field: FieldReading(
            field: field,
            text: message.substring(tokens[first].start, tokens[last].end),
            start: tokens[first].start,
            end: tokens[last].end,
            confidence: 1,
          ),
      },
    );
  }

  String toJson() => jsonEncode({
    'kind': kind.name,
    'parts': [for (final p in parts) p.toJson()],
  });

  static ReadingTemplate fromJson(String text) {
    final json = jsonDecode(text) as Map<String, Object?>;
    return ReadingTemplate(
      kind: MessageKind.values.byName(json['kind']! as String),
      parts: [
        for (final p in (json['parts']! as List).cast<Map<String, Object?>>())
          TemplatePart.fromJson(p),
      ],
    );
  }
}

/// The inclusive token range covering characters [start] to [end] of a
/// message, or null when no token starts inside it.
(int, int)? tokenRange(List<MessageToken> tokens, int start, int end) {
  int? first;
  int? last;
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i].start >= start && tokens[i].end <= end) {
      first ??= i;
      last = i;
    }
  }
  return first == null ? null : (first, last!);
}
