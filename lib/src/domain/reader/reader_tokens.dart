/// Message tokens and the message reader's input, as pesaclarity-ml defines
/// them (`docs/READER.md`, schema version 1).
///
/// `test/fixtures/reader/reader_vectors.v1.json` is a copy of the
/// conformance vectors, and `test/domain/reader/reader_tokens_test.dart`
/// fails if this file produces anything different.
library;

/// Version of the token pipeline this app implements.
const readerSchemaVersion = 1;

/// Tokens the model reads; later tokens are dropped.
const readerMaxTokens = 96;
const readerHashBuckets = 4096;

// Numbers with separators; words, which keep digits only when a letter
// follows them; masks; then any single visible character. `unicode: true`
// makes a character outside the Basic Multilingual Plane one token, as in
// Python.
final _token = RegExp(
  r'[0-9]+(?:[.,:/-][0-9]+)*'
  r'|[A-Za-z]+(?:[0-9]+[A-Za-z][A-Za-z0-9]*)?'
  r'|\*+[0-9]*'
  r'|[^\t\n\v\f\r ]',
  unicode: true,
);

/// What a token looks like. The index is the shape id; 0 is padding.
enum TokenShape {
  pad,
  upper,
  lower,
  title,
  mixed,
  integer,
  decimal,
  grouped,
  date,
  time,
  mask,
  punct,
}

/// A token and where it sits in the message, in UTF-16 code units.
class MessageToken {
  const MessageToken(this.text, this.start, this.end);

  final String text;
  final int start;
  final int end;

  TokenShape get shape => shapeOf(text);
}

List<MessageToken> tokenise(String message) => [
  for (final m in _token.allMatches(message))
    MessageToken(m.group(0)!, m.start, m.end),
];

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isUpper(int c) => c >= 0x41 && c <= 0x5A;
bool _isLower(int c) => c >= 0x61 && c <= 0x7A;

TokenShape shapeOf(String text) {
  final first = text.codeUnitAt(0);
  if (_isDigit(first)) {
    if (text.codeUnits.every(_isDigit)) return TokenShape.integer;
    if (text.contains(':')) return TokenShape.time;
    if (text.contains('/') || text.contains('-')) return TokenShape.date;
    return text.contains(',') ? TokenShape.grouped : TokenShape.decimal;
  }
  if (first == 0x2A) return TokenShape.mask;
  if (_isUpper(first) || _isLower(first)) {
    if (text.codeUnits.any(_isDigit)) return TokenShape.mixed;
    if (text.codeUnits.every(_isUpper)) {
      return text.length > 1 ? TokenShape.upper : TokenShape.title;
    }
    return _isUpper(first) ? TokenShape.title : TokenShape.lower;
  }
  return TokenShape.punct;
}

bool _isNumber(TokenShape s) =>
    s == TokenShape.integer ||
    s == TokenShape.decimal ||
    s == TokenShape.grouped ||
    s == TokenShape.date ||
    s == TokenShape.time;

/// What a token hashes as: numbers by layout (`1,250.00` is `#9,999.99`),
/// masks as `#mask`, words in ASCII lower case.
String hashKey(String text) {
  final shape = shapeOf(text);
  if (_isNumber(shape)) {
    return '#${String.fromCharCodes([for (final c in text.codeUnits) _isDigit(c) ? 0x39 : c])}';
  }
  if (shape == TokenShape.mask) return '#mask';
  return String.fromCharCodes([
    for (final c in text.codeUnits) _isUpper(c) ? c + 0x20 : c,
  ]);
}

/// 32-bit FNV-1a over [text], one byte per code point, with `?` for every
/// non-ASCII character.
int _fnv1a(String text) {
  var h = 0x811C9DC5;
  for (final rune in text.runes) {
    h ^= rune < 0x80 ? rune : 0x3F;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// 1 .. [readerHashBuckets] - 1; 0 is padding.
int tokenId(String text) => 1 + _fnv1a(hashKey(text)) % (readerHashBuckets - 1);

/// The model input for [tokens]: [readerMaxTokens] ids, then as many shape
/// ids, each padded with 0.
List<int> encodeTokens(List<MessageToken> tokens) {
  final kept = tokens.take(readerMaxTokens).toList();
  final pad = List<int>.filled(readerMaxTokens - kept.length, 0);
  return [
    for (final t in kept) tokenId(t.text),
    ...pad,
    for (final t in kept) t.shape.index,
    ...pad,
  ];
}
