import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../domain/categoriser/categoriser.dart';
import '../../../domain/reader/model_reader.dart';
import '../../../domain/reader/reader_tokens.dart';

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

/// [ReaderRuntime] on package:tflite_flutter: one message of
/// `[1, 2 * readerMaxTokens]` int32, two outputs.
class TfliteReaderRuntime implements ReaderRuntime {
  TfliteReaderRuntime._(this._interpreter, this._fieldsIndex, this._kindIndex);

  factory TfliteReaderRuntime.open(Uint8List modelBytes) {
    final interpreter = Interpreter.fromBuffer(modelBytes);
    try {
      interpreter
        ..resizeInputTensor(0, [1, 2 * readerMaxTokens])
        ..allocateTensors();
      final outputs = interpreter.getOutputTensors();
      final fields = outputs.indexWhere((t) => t.shape.length == 3);
      final kind = outputs.indexWhere((t) => t.shape.length == 2);
      if (fields < 0 || kind < 0) {
        throw StateError('expected a 3-D and a 2-D output');
      }
      return TfliteReaderRuntime._(interpreter, fields, kind);
    } on Object {
      interpreter.close();
      rethrow;
    }
  }

  final Interpreter _interpreter;
  final int _fieldsIndex;
  final int _kindIndex;

  @override
  (List<List<double>>, List<double>) run(List<int> input) {
    final fieldsShape = _interpreter.getOutputTensor(_fieldsIndex).shape;
    final kindShape = _interpreter.getOutputTensor(_kindIndex).shape;
    final fields = [
      List.generate(
        fieldsShape[1],
        (_) => List<double>.filled(fieldsShape[2], 0),
      ),
    ];
    final kind = [List<double>.filled(kindShape[1], 0)];
    _interpreter.runForMultipleInputs(
      [
        [Int32List.fromList(input)],
      ],
      {_fieldsIndex: fields, _kindIndex: kind},
    );
    return (fields.first, kind.first);
  }

  @override
  void close() => _interpreter.close();
}
