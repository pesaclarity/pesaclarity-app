// The signature runner has C bindings only in tflite_flutter 0.12.
// ignore_for_file: implementation_imports
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:tflite_flutter/src/bindings/bindings.dart';
import 'package:tflite_flutter/src/bindings/tensorflow_lite_bindings_generated.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../domain/categoriser/categoriser.dart';
import '../../../domain/categoriser/model_manifest.dart';
import '../../../domain/categoriser/trainable.dart';
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

/// [TrainableRuntime] on the TFLite C signature runner that
/// package:tflite_flutter links: `train`, `infer`, `save` and `restore` from
/// `categoriser-train.tflite`. The weights live in the interpreter's
/// resource variables, shared by all four signatures.
class TfliteTrainableRuntime implements TrainableRuntime {
  TfliteTrainableRuntime._(
    this._interpreter,
    this._runners,
    this._width,
    this.outputSize,
  );

  factory TfliteTrainableRuntime.open(
    Uint8List modelBytes, {
    required int width,
  }) {
    final interpreter = Interpreter.fromBuffer(modelBytes);
    final runners = <String, Pointer<TfLiteSignatureRunner>>{};
    try {
      final native = Pointer<TfLiteInterpreter>.fromAddress(
        interpreter.address,
      );
      for (final name in TrainableManifest.requiredSignatures) {
        final runner = _withName(
          name,
          (key) =>
              tfliteBinding.TfLiteInterpreterGetSignatureRunner(native, key),
        );
        if (runner == nullptr) throw StateError('no $name signature');
        runners[name] = runner;
      }
      final infer = runners['infer']!;
      _resize(infer, 'x', [1, width]);
      _check(
        tfliteBinding.TfLiteSignatureRunnerAllocateTensors(infer),
        'allocate infer',
      );
      final out = Tensor(_output(infer, 'output'));
      return TfliteTrainableRuntime._(
        interpreter,
        runners,
        width,
        out.shape.last,
      );
    } on Object {
      runners.values.forEach(tfliteBinding.TfLiteSignatureRunnerDelete);
      interpreter.close();
      rethrow;
    }
  }

  final Interpreter _interpreter;
  final Map<String, Pointer<TfLiteSignatureRunner>> _runners;
  final int _width;

  @override
  final int outputSize;

  @override
  List<double> run(List<int> row) {
    if (row.length != _width) {
      throw ArgumentError.value(row.length, 'row', 'expected $_width values');
    }
    // Sized to [1, width] once in open; the other signatures do not touch it.
    final infer = _runners['infer']!;
    Tensor(_input(infer, 'x')).data = Int32List.fromList(row).buffer
        .asUint8List();
    _check(tfliteBinding.TfLiteSignatureRunnerInvoke(infer), 'infer');
    return Tensor(_output(infer, 'output')).data.buffer
        .asFloat32List(0, outputSize)
        .toList();
  }

  @override
  double train(List<List<int>> rows, List<int> labels, double learningRate) {
    if (rows.isEmpty || rows.length != labels.length) {
      throw ArgumentError('${rows.length} rows for ${labels.length} labels');
    }
    final x = Int32List(rows.length * _width);
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].length != _width) {
        throw ArgumentError.value(rows[i].length, 'row', 'expected $_width');
      }
      x.setRange(i * _width, (i + 1) * _width, rows[i]);
    }
    final train = _runners['train']!;
    _resize(train, 'x', [rows.length, _width]);
    _resize(train, 'y', [labels.length]);
    _check(
      tfliteBinding.TfLiteSignatureRunnerAllocateTensors(train),
      'allocate train',
    );
    Tensor(_input(train, 'x')).data = x.buffer.asUint8List();
    Tensor(_input(train, 'y')).data = Int32List.fromList(labels).buffer
        .asUint8List();
    Tensor(_input(train, 'lr')).data = Float32List.fromList([learningRate])
        .buffer
        .asUint8List();
    _check(tfliteBinding.TfLiteSignatureRunnerInvoke(train), 'train');
    return Tensor(_output(train, 'loss')).data.buffer.asFloat32List(0, 1)[0];
  }

  @override
  Map<String, Float32List> save() {
    final save = _runners['save']!;
    _check(
      tfliteBinding.TfLiteSignatureRunnerAllocateTensors(save),
      'allocate save',
    );
    _check(tfliteBinding.TfLiteSignatureRunnerInvoke(save), 'save');
    return {
      for (final name in TrainableManifest.weightNames)
        name: Float32List.fromList(
          Tensor(_output(save, name)).data.buffer.asFloat32List(),
        ),
    };
  }

  @override
  void restore(Map<String, Float32List> weights) {
    final restore = _runners['restore']!;
    _check(
      tfliteBinding.TfLiteSignatureRunnerAllocateTensors(restore),
      'allocate restore',
    );
    for (final name in TrainableManifest.weightNames) {
      final w = weights[name];
      if (w == null) throw ArgumentError('no $name');
      // The setter checks the byte size against the tensor.
      Tensor(_input(restore, name)).data = w.buffer.asUint8List(
        w.offsetInBytes,
        w.lengthInBytes,
      );
    }
    _check(tfliteBinding.TfLiteSignatureRunnerInvoke(restore), 'restore');
  }

  @override
  void close() {
    _runners.values.forEach(tfliteBinding.TfLiteSignatureRunnerDelete);
    _runners.clear();
    _interpreter.close();
  }

  static T _withName<T>(String name, T Function(Pointer<Char>) f) {
    final key = name.toNativeUtf8();
    try {
      return f(key.cast());
    } finally {
      malloc.free(key);
    }
  }

  static Pointer<TfLiteTensor> _input(
    Pointer<TfLiteSignatureRunner> runner,
    String name,
  ) {
    final t = _withName(
      name,
      (key) => tfliteBinding.TfLiteSignatureRunnerGetInputTensor(runner, key),
    );
    if (t == nullptr) throw StateError('no input $name');
    return t;
  }

  static Pointer<TfLiteTensor> _output(
    Pointer<TfLiteSignatureRunner> runner,
    String name,
  ) {
    final t = _withName(
      name,
      (key) => tfliteBinding.TfLiteSignatureRunnerGetOutputTensor(runner, key),
    );
    if (t == nullptr) throw StateError('no output $name');
    return t.cast();
  }

  static void _resize(
    Pointer<TfLiteSignatureRunner> runner,
    String name,
    List<int> dims,
  ) {
    final p = malloc<Int>(dims.length);
    try {
      for (var i = 0; i < dims.length; i++) {
        p[i] = dims[i];
      }
      _check(
        _withName(
          name,
          (key) => tfliteBinding.TfLiteSignatureRunnerResizeInputTensor(
            runner,
            key,
            p,
            dims.length,
          ),
        ),
        'resize $name',
      );
    } finally {
      malloc.free(p);
    }
  }

  static void _check(int status, String what) {
    if (status != TfLiteStatus.kTfLiteOk) {
      throw StateError('$what failed with status $status');
    }
  }
}
