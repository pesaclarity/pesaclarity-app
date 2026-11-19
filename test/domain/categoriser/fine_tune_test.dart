import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/categoriser/model_manifest.dart';
import 'package:pesaclarity/src/domain/categoriser/trainable.dart';

/// The fine-tuning step against pesaclarity-ml's conformance vectors
/// (`fine_tune_vectors.v1.json`, a copy of `akili.resources`'): torch's
/// automatic gradients computed every loss and weight, and the app's step
/// must give each within the file's tolerance.
void main() {
  final doc = jsonDecode(
    File('test/fixtures/categoriser/fine_tune_vectors.v1.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  final tolerance = (doc['tolerance']! as num).toDouble();

  test('the vectors are of the step and tensors this app implements', () {
    expect(doc['spec_version'], FineTuneManifest.supportedSpecVersion);
    expect(doc['trains'], FineTuneManifest.tensorNames);
    expect(tolerance, 1e-5);
    expect(doc['layouts'], {
      'hidden.kernel': '[hidden, in]',
      'category.kernel': '[classes, hidden]',
      'f': '[rows, in]',
    });
  });

  for (final c in (doc['cases']! as List).cast<Map<String, Object?>>()) {
    test('${c['id']}: ${c['note']}', () {
      final [inputs, hidden, classes] = (c['sizes']! as List).cast<int>();
      final weights = _weights(c['weights']! as Map<String, Object?>);
      final w = DenseWeights.fromNamed(weights, {
        'hidden.kernel': [hidden, inputs],
        'hidden.bias': [hidden],
        'category.kernel': [classes, hidden],
        'category.bias': [classes],
      })!;
      for (final (i, s)
          in (c['steps']! as List).cast<Map<String, Object?>>().indexed) {
        final f = [for (final row in s['f']! as List) _floats(row! as List)];
        final loss = w.step(
          f,
          (s['y']! as List).cast<int>(),
          (s['lr']! as num).toDouble(),
        );
        expect(
          loss,
          closeTo((s['loss']! as num).toDouble(), tolerance),
          reason: 'loss of step $i',
        );
        final after = _weights(s['after']! as Map<String, Object?>);
        final got = w.toNamed();
        for (final name in FineTuneManifest.tensorNames) {
          final want = after[name]!;
          expect(got[name], hasLength(want.length));
          for (var j = 0; j < want.length; j++) {
            expect(
              got[name]![j],
              closeTo(want[j], tolerance),
              reason: '$name[$j] after step $i',
            );
          }
        }
      }
    });
  }

  test('a dead hidden unit keeps its kernel row and bias', () {
    final c = (doc['cases']! as List).cast<Map<String, Object?>>().firstWhere(
      (c) => c['id'] == 'dead_unit',
    );
    final start = _weights(c['weights']! as Map<String, Object?>);
    final step = (c['steps']! as List).single as Map<String, Object?>;
    final after = _weights(step['after']! as Map<String, Object?>);
    final inputs = (c['sizes']! as List).first as int;
    expect(after['hidden.bias']![0], start['hidden.bias']![0]);
    expect(
      after['hidden.kernel']!.sublist(0, inputs),
      start['hidden.kernel']!.sublist(0, inputs),
    );
  });
}

Map<String, Float32List> _weights(Map<String, Object?> json) => {
  for (final MapEntry(:key, :value) in json.entries)
    key: _floats(value! as List),
};

/// A tensor's values, flattened row-major.
Float32List _floats(List<Object?> values) => Float32List.fromList([
  for (final v in values)
    if (v is List) ..._floats(v) else (v! as num).toDouble(),
]);
