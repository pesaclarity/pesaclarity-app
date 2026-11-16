import 'dart:math' as math;

import 'understanding.dart';

/// One category, payee, account or stock item in the open space, as Ask
/// can name it. [key] is stable within the space, such as `c:4`.
class AskEntity {
  const AskEntity(this.kind, this.key, this.name, {this.detail});

  factory AskEntity.fromJson(Map<String, Object?> json) => AskEntity(
    SlotKind.values.byName(json['kind']! as String),
    json['key']! as String,
    json['name']! as String,
    detail: json['detail'] as String?,
  );

  final SlotKind kind;
  final String key;
  final String name;

  /// A short line that tells two of the same name apart, such as
  /// `Sent 6 times`.
  final String? detail;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'key': key,
    'name': name,
    'detail': ?detail,
  };

  @override
  bool operator ==(Object other) =>
      other is AskEntity && other.kind == kind && other.key == key;

  @override
  int get hashCode => Object.hash(kind, key);

  @override
  String toString() => 'AskEntity(${kind.name} $key $name)';
}

/// A word the person taught Ask by answering "Which one do you mean?".
class AskShortcut {
  const AskShortcut(this.word, this.kind, this.key);

  final String word;
  final SlotKind kind;
  final String key;
}

/// What a span matched.
sealed class MatchResult {
  const MatchResult();
}

class Matched extends MatchResult {
  const Matched(this.entity);
  final AskEntity entity;
}

/// More than one fits about as well: ask which.
class Ambiguous extends MatchResult {
  const Ambiguous(this.candidates);
  final List<AskEntity> candidates;
}

class NoMatch extends MatchResult {
  const NoMatch();
}

/// Words people use for the usual categories, English, Swahili and Sheng.
/// Each list is tried against the space's own category names.
const categorySynonyms = <String, List<String>>{
  'food': ['food', 'groceries', 'eating out', 'snacks'],
  'chakula': ['food', 'groceries', 'eating out'],
  'groceries': ['groceries', 'food', 'supermarket'],
  'supermarkets': ['groceries', 'supermarket'],
  'supermarket': ['groceries', 'supermarket'],
  'fare': ['transport', 'fare'],
  'matatu': ['transport', 'fare'],
  'transport': ['transport', 'fare'],
  'travel': ['transport', 'travel'],
  'rent': ['rent', 'housing'],
  'kodi': ['rent', 'housing'],
  'electricity': ['electricity', 'power', 'utilities'],
  'power': ['electricity', 'power', 'utilities'],
  'stima': ['electricity', 'power', 'utilities'],
  'water': ['water', 'utilities'],
  'maji': ['water', 'utilities'],
  'airtime': ['airtime', 'data'],
  'data': ['airtime', 'data', 'internet'],
  'bundles': ['airtime', 'data'],
  'internet': ['internet', 'wifi', 'data'],
  'school': ['school', 'education', 'school fees'],
  'fees': ['school fees', 'education'],
  'karo': ['school fees', 'education'],
  'church': ['church', 'giving'],
  'sadaka': ['church', 'giving'],
  'giving': ['giving', 'church'],
  'health': ['health', 'medical', 'hospital'],
  'hospital': ['health', 'medical', 'hospital'],
  'dawa': ['health', 'medical', 'pharmacy'],
  'fuel': ['fuel', 'petrol', 'transport'],
  'petrol': ['fuel', 'petrol'],
  'drinks': ['drinks', 'entertainment', 'going out'],
  'betting': ['betting', 'gambling'],
  'salary': ['salary', 'wages', 'pay'],
  'mshahara': ['salary', 'wages', 'pay'],
};

/// Lowercase, accents off, punctuation as spaces, single spaces.
String normaliseName(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final c = String.fromCharCode(rune);
    final plain = _accents[c] ?? c;
    out.write(RegExp('[a-z0-9]').hasMatch(plain) ? plain : ' ');
  }
  return out.toString().trim().replaceAll(RegExp(' +'), ' ');
}

const _accents = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'ö': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ñ': 'n',
  'ç': 'c',
};

/// Edits that turn [a] into [b].
int editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      current[j] = math.min(
        math.min(current[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + cost,
      );
    }
    previous = current;
  }
  return previous[b.length];
}

Set<String> _trigrams(String text) {
  final padded = '  $text ';
  return {
    for (var i = 0; i + 3 <= padded.length; i++) padded.substring(i, i + 3),
  };
}

/// How well [query] names [name], from 0 to 1. Both are normalised.
double nameScore(String query, String name) {
  if (query.isEmpty || name.isEmpty) return 0;
  if (query == name) return 1;
  final words = name.split(' ');
  final queryWords = query.split(' ');
  // Every word asked is a whole word of the name: "john" in "John Kamau".
  if (queryWords.every(words.contains)) {
    return 0.8 + 0.15 * queryWords.length / words.length;
  }
  if (name.startsWith(query) && query.length >= 3) return 0.8;
  // A typo in one word: "naivaz" for "naivas".
  var best = 0.0;
  for (final w in [...words, name]) {
    for (final q in [...queryWords, query]) {
      if (q.length < 3 || w.length < 3) continue;
      final d = editDistance(q, w);
      final allowed = q.length >= 7 ? 2 : 1;
      if (d <= allowed) {
        final s = 0.85 - 0.08 * d - (q == query ? 0 : 0.1);
        if (s > best) best = s;
      }
    }
  }
  final a = _trigrams(query);
  final b = _trigrams(name);
  final shared = a.intersection(b).length;
  final jaccard = shared / (a.length + b.length - shared);
  return math.max(best, jaccard);
}

/// Finds the space's own category, payee, account or item that a span
/// names, using the person's shortcuts first.
class EntityMatcher {
  EntityMatcher(this.entities, {Iterable<AskShortcut> shortcuts = const []})
    : _shortcuts = {for (final s in shortcuts) normaliseName(s.word): s};

  final List<AskEntity> entities;
  final Map<String, AskShortcut> _shortcuts;

  /// Below this, a name is not a match.
  static const threshold = 0.6;

  /// Candidates this close to the best are asked about.
  static const _closeness = 0.04;

  /// The [kinds] to look in, in order: the reader's guess first.
  MatchResult match(String text, List<SlotKind> kinds) {
    final query = normaliseName(text);
    if (query.isEmpty) return const NoMatch();
    final shortcut = _shortcuts[query];
    if (shortcut != null) {
      for (final e in entities) {
        if (e.kind == shortcut.kind && e.key == shortcut.key) {
          return Matched(e);
        }
      }
    }
    for (final kind in kinds) {
      final result = _matchKind(query, kind);
      if (result is! NoMatch) return result;
    }
    return const NoMatch();
  }

  MatchResult _matchKind(String query, SlotKind kind) {
    final queries = kind == SlotKind.category
        ? {query, ...?categorySynonyms[query]}
        : {query};
    final scored = <(AskEntity, double)>[];
    for (final e in entities) {
      if (e.kind != kind) continue;
      final name = normaliseName(e.name);
      var score = 0.0;
      for (final q in queries) {
        // A synonym counts a little less than the word itself.
        final s = nameScore(q, name) * (q == query ? 1 : 0.97);
        if (s > score) score = s;
      }
      if (score >= threshold) scored.add((e, score));
    }
    if (scored.isEmpty) return const NoMatch();
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final top = scored.first.$2;
    if (top == 1) return Matched(scored.first.$1);
    final close = [
      for (final (e, s) in scored)
        if (top - s <= _closeness) e,
    ];
    if (close.length > 1 && kind != SlotKind.category) return Ambiguous(close);
    return Matched(scored.first.$1);
  }
}
