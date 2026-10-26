import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../domain/categoriser/categoriser.dart';

/// [TfliteRuntime] on package:tflite_flutter (Apache-2.0).
///
/// This is the only file that imports the plugin. On Android it links
/// Google's prebuilt LiteRT AAR from Maven, so an F-Droid build needs LiteRT
/// built from source or a runtime swapped in behind [TfliteRuntime].
class TfliteFlutterRuntime implements TfliteRuntime {
  TfliteFlutterRuntime._(this._interpreter, this._width, this.outputSize);

  /// Opens [modelBytes] for single rows of `[1, width]` int32 features.
  factory TfliteFlutterRuntime.open(
    Uint8List modelBytes, {
    required int width,
  }) {
    final interpreter = Interpreter.fromBuffer(modelBytes);
    try {
      interpreter
        ..resizeInputTensor(0, [1, width])
        ..allocateTensors();
      final shape = interpreter.getOutputTensor(0).shape;
      return TfliteFlutterRuntime._(interpreter, width, shape.last);
    } on Object {
      interpreter.close();
      rethrow;
    }
  }

  final Interpreter _interpreter;
  final int _width;

  @override
  final int outputSize;

  @override
  List<double> run(List<int> row) {
    if (row.length != _width) {
      throw ArgumentError.value(row.length, 'row', 'expected $_width values');
    }
    final output = [List<double>.filled(outputSize, 0)];
    _interpreter.run([Int32List.fromList(row)], output);
    return output.first;
  }

  @override
  void close() => _interpreter.close();
}
