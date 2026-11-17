// Times the Ask reader (lib/src/domain/ml/dart_ask_reader.dart) on this
// computer, on the questions recorded in test/fixtures/ask/:
//
//   dart compile exe tool/ask_reader_bench.dart -o build/ask_reader_bench
//   build/ask_reader_bench [rounds]
//
// Prints how long the weights take to load, the first question and the
// median and 90th percentile of one question at a time. `dart run` works
// too, but times the JIT, which is slower than the app's AOT build.

import 'dart:convert';
import 'dart:io';

import 'package:pesaclarity/src/domain/ml/dart_ask_reader.dart';

void main(List<String> args) {
  final rounds = args.isEmpty ? 50 : int.parse(args.first);
  final recorded = jsonDecode(
    File('test/fixtures/ask/ask_reader_decodes.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final inputs = [
    for (final r
        in (recorded['readings']! as List).cast<Map<String, Object?>>())
      (r['input']! as List).cast<int>(),
  ];
  final bytes = File('assets/models/ask/ask-reader.weights').readAsBytesSync();

  final load = Stopwatch()..start();
  final reader = DartAskReader.parse(bytes);
  load.stop();
  final first = Stopwatch()..start();
  reader.run(inputs.first);
  first.stop();
  final times = <double>[];
  for (var round = 0; round < rounds; round++) {
    for (final input in inputs) {
      final w = Stopwatch()..start();
      reader.run(input);
      times.add(w.elapsedMicroseconds / 1000);
    }
  }
  times.sort();
  String ms(double v) => v.toStringAsFixed(2);
  stdout.writeln(
    'load ${ms(load.elapsedMicroseconds / 1000)} ms, '
    'first question ${ms(first.elapsedMicroseconds / 1000)} ms, '
    'per question median ${ms(times[times.length ~/ 2])} ms, '
    'p90 ${ms(times[times.length * 9 ~/ 10])} ms',
  );
}
