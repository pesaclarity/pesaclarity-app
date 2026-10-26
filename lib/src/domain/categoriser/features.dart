/// The categoriser's model input, a Dart port of `akili.features` in
/// pesaclarity/pesaclarity-ml.
///
/// `docs/FEATURES.md` there is the spec and `feature_vectors.v1.json` the
/// conformance cases (copied into `test/fixtures/categoriser`). Every step is
/// ASCII-only integer arithmetic, so the result never depends on the phone's
/// locale or time zone.
library;

import 'dart:convert';

/// The feature pipeline version this file implements. A model whose manifest
/// names another version is refused.
const featureSchemaVersion = 1;

/// Token slots and hash buckets. Read from the model manifest; the shipping
/// values are the defaults.
class FeatureConfig {
  const FeatureConfig({this.maxTokens = 8, this.hashBuckets = 4096});

  final int maxTokens;
  final int hashBuckets;

  /// Length of one encoded row: the tokens plus five context features.
  int get width => maxTokens + contextLayout.length;

  /// Whether the pipeline can produce inputs for this config. Matches the
  /// bounds the training code accepts.
  bool get isValid =>
      maxTokens >= 1 &&
      maxTokens <= 32 &&
      hashBuckets >= 16 &&
      hashBuckets <= 65536;

  /// Names of the row's columns, in order, as the manifest's `layout`.
  List<String> get layout => [
    for (var i = 0; i < maxTokens; i++) 'token_$i',
    ...contextLayout,
  ];

  @override
  bool operator ==(Object other) =>
      other is FeatureConfig &&
      other.maxTokens == maxTokens &&
      other.hashBuckets == hashBuckets;

  @override
  int get hashCode => Object.hash(maxTokens, hashBuckets);

  @override
  String toString() =>
      'FeatureConfig(maxTokens: $maxTokens, hashBuckets: $hashBuckets)';
}

const contextLayout = [
  'amount_bucket',
  'direction',
  'hour_bucket',
  'weekday',
  'month_phase',
];

/// Amount bucket edges in minor units (KES 50 up to KES 100,000).
const amountEdgesMinor = [
  5000,
  10000,
  25000,
  50000,
  100000,
  250000,
  500000,
  1000000,
  2500000,
  5000000,
  10000000,
];

const numToken = '<num>';
const phoneToken = '<phone>';

/// One transaction as the categoriser sees it.
class FeatureInput {
  const FeatureInput({
    required this.payee,
    required this.amountMinor,
    required this.isInflow,
    required this.timestampMs,
  });

  /// Counterparty text as parsed from the message. May be empty.
  final String payee;
  final int amountMinor;
  final bool isInflow;

  /// The instant in milliseconds since the epoch (UTC).
  final int timestampMs;
}

// Spelled out so no engine applies Unicode rules to \d, \s or \b.
final _maskedPhone = RegExp(
  r'(?<![0-9a-z])[0-9]{2,4}[\t\n\v\f\r ]?\*{2,}[\t\n\v\f\r ]?[0-9]{2,4}(?![0-9a-z])',
);
final _word = RegExp('[0-9a-z]+');
final _digit = RegExp('[0-9]');

const _fnvOffset = 0x811C9DC5;
const _fnvPrime = 0x01000193;

/// 32-bit FNV-1a over the UTF-8 bytes of [text], as an unsigned value.
int fnv1a32(String text) {
  var h = _fnvOffset;
  for (final byte in utf8.encode(text)) {
    h ^= byte;
    h = (h * _fnvPrime) & 0xFFFFFFFF;
  }
  return h;
}

String _asciiLower(String s) {
  final units = s.codeUnits.toList();
  for (var i = 0; i < units.length; i++) {
    final c = units[i];
    if (c >= 0x41 && c <= 0x5A) units[i] = c + 0x20;
  }
  return String.fromCharCodes(units);
}

Iterable<String> _words(String segment) => _word
    .allMatches(segment)
    .map((m) => m[0]!)
    .map((w) => _digit.hasMatch(w) ? numToken : w);

/// Payee text as tokens: ASCII lower case, masked phone numbers as
/// `<phone>`, words holding a digit as `<num>`, runs of `<num>` collapsed.
List<String> tokenise(String payee) {
  final text = _asciiLower(payee);
  final raw = <String>[];
  var pos = 0;
  for (final match in _maskedPhone.allMatches(text)) {
    raw
      ..addAll(_words(text.substring(pos, match.start)))
      ..add(phoneToken);
    pos = match.end;
  }
  raw.addAll(_words(text.substring(pos)));

  final tokens = <String>[];
  for (final token in raw) {
    if (token == numToken && tokens.isNotEmpty && tokens.last == numToken) {
      continue;
    }
    tokens.add(token);
  }
  return tokens;
}

/// Hashed token ids, padded with 0 to `config.maxTokens`.
List<int> tokenIds(String payee, FeatureConfig config) {
  final ids = [
    for (final t in tokenise(payee).take(config.maxTokens))
      fnv1a32(t) % (config.hashBuckets - 1) + 1,
  ];
  return [...ids, ...List.filled(config.maxTokens - ids.length, 0)];
}

/// How many edges are at or below the absolute amount: 0 to 11.
int amountBucket(int amountMinor) {
  final amount = amountMinor.abs();
  return amountEdgesMinor.where((edge) => amount >= edge).length;
}

/// 0 for the 1st to 5th (rent), 2 from the 25th (payday), else 1.
int monthPhase(int day) => day <= 5
    ? 0
    : day >= 25
    ? 2
    : 1;

const _eatOffsetMs = 3 * 3600 * 1000;
const _dayMs = 86400000;

int _floorDiv(int a, int b) {
  final q = a ~/ b;
  return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q;
}

/// Nairobi (fixed UTC+3) hour, weekday (Monday 0) and day of month.
({int hour, int weekday, int day}) nairobiTime(int timestampMs) {
  final local = timestampMs + _eatOffsetMs;
  final days = _floorDiv(local, _dayMs);
  final msOfDay = local - days * _dayMs;
  return (
    hour: msOfDay ~/ 3600000,
    weekday: (days + 3) % 7,
    day: _civilDay(days),
  );
}

/// Day of month from days since 1970-01-01 (Howard Hinnant's algorithm).
int _civilDay(int days) {
  final z = days + 719468;
  final era = _floorDiv(z, 146097);
  final doe = z - era * 146097;
  final yoe = (doe - doe ~/ 1460 + doe ~/ 36524 - doe ~/ 146096) ~/ 365;
  final doy = doe - (365 * yoe + yoe ~/ 4 - yoe ~/ 100);
  final mp = (5 * doy + 2) ~/ 153;
  return doy - (153 * mp + 2) ~/ 5 + 1;
}

/// The model's int32 row for [input]: tokens, then amount bucket,
/// direction, hour bucket, weekday and month phase.
List<int> encodeFeatures(
  FeatureInput input, [
  FeatureConfig config = const FeatureConfig(),
]) {
  final t = nairobiTime(input.timestampMs);
  return [
    ...tokenIds(input.payee, config),
    amountBucket(input.amountMinor),
    input.isInflow ? 1 : 0,
    t.hour ~/ 4,
    t.weekday,
    monthPhase(t.day),
  ];
}
