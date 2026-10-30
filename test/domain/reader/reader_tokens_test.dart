import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/reader/reader_tokens.dart';

/// The app must turn every message into exactly the model input that
/// pesaclarity-ml trained on.
void main() {
  final vectors = jsonDecode(
    File('test/fixtures/reader/reader_vectors.v1.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final manifest = vectors['manifest']! as Map<String, Object?>;

  test('implements the vectors schema', () {
    expect(manifest['reader_schema_version'], readerSchemaVersion);
    expect(manifest['max_tokens'], readerMaxTokens);
    expect(manifest['hash_buckets'], readerHashBuckets);
  });

  for (final raw in (vectors['cases']! as List).cast<Map<String, Object?>>()) {
    test('${raw['id']}: ${raw['note']}', () {
      final message = raw['message']! as String;
      final expected = raw['expected']! as Map<String, Object?>;
      final tokens = tokenise(message);
      expect(tokens, hasLength(expected['token_count']));
      final shown = (expected['tokens']! as List).cast<Map<String, Object?>>();
      for (final (i, want) in shown.indexed) {
        final t = tokens[i];
        expect(t.text, want['text']);
        expect(t.start, want['start']);
        expect(t.end, want['end']);
        expect(t.shape.index, want['shape']);
        expect(hashKey(t.text), want['hash_key']);
        expect(tokenId(t.text), want['id']);
      }
      expect(encodeTokens(tokens), expected['input']);
    });
  }
}
