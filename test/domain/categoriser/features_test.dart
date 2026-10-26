import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/categoriser/features.dart';

/// Conformance with pesaclarity-ml's `feature_vectors.v1.json`, copied
/// unchanged from `src/akili/resources` in that repository.
void main() {
  final vectors = jsonDecode(
    File('test/fixtures/categoriser/feature_vectors.v1.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  final cfg = vectors['feature_config'] as Map<String, dynamic>;
  final config = FeatureConfig(
    maxTokens: cfg['max_tokens'] as int,
    hashBuckets: cfg['hash_buckets'] as int,
  );

  test('the vectors describe the version and config implemented here', () {
    expect(vectors['feature_schema_version'], featureSchemaVersion);
    expect(config, const FeatureConfig());
    expect(vectors['layout'], config.layout);
    expect((vectors['input'] as Map)['shape'], [-1, config.width]);
    expect(vectors['amount_edges_minor'], amountEdgesMinor);
  });

  test('FNV-1a check values', () {
    for (final check
        in (vectors['hash_checks'] as List).cast<Map<String, dynamic>>()) {
      expect(fnv1a32(check['text'] as String), check['fnv1a_32']);
    }
  });

  final cases = (vectors['cases'] as List).cast<Map<String, dynamic>>();
  test('the vectors hold the cases', () => expect(cases, hasLength(60)));

  for (final c in cases) {
    test('case ${c['id']}', () {
      final input = c['input'] as Map<String, dynamic>;
      final expected = c['expected'] as Map<String, dynamic>;
      final payee = input['payee'] as String;
      expect(tokenise(payee), expected['tokens'], reason: 'tokens');
      expect(
        encodeFeatures(
          FeatureInput(
            payee: payee,
            amountMinor: input['amount_minor'] as int,
            isInflow: switch (input['direction']) {
              'in' => true,
              'out' => false,
              final d => throw FormatException('direction $d'),
            },
            timestampMs: input['timestamp_ms'] as int,
          ),
          config,
        ),
        expected['features'],
        reason: 'features',
      );
    });
  }

  test('instants before 1970 use floor division', () {
    // 1969-12-31 23:00 EAT is a Wednesday, the 31st.
    final t = nairobiTime(-4 * 3600 * 1000);
    expect(t, (hour: 23, weekday: 2, day: 31));
  });
}
