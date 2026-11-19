import 'dart:typed_data';

import 'package:rayo/rayo.dart';

import '../../../domain/categoriser/categoriser.dart';
import '../../../domain/categoriser/features.dart';
import '../../../domain/categoriser/model_manifest.dart';
import '../../../domain/categoriser/trainable.dart';

/// Opens `categoriser.weights` on rayo for rows of [config], or in Dart
/// ([DartCategoriserRuntime], the same network with the int8 kernel
/// dequantised) when rayo's native library cannot load here or refuses the
/// file. Throws only when neither can read it.
CategoriserRuntime openCategoriserRuntime(
  Uint8List bytes,
  FeatureConfig config,
) {
  if (rayoAvailable()) {
    try {
      return RayoCategoriser.open(bytes, config.width);
    } on Object {
      // The Dart network reads the same file.
    }
  }
  return DartCategoriserRuntime(CategoriserNetwork.parse(bytes, config));
}

/// The categoriser on rayo: `categoriser.weights` with its graph
/// (pesaclarity-ml docs/CATEGORISER.md), one session kept while the model
/// is loaded. Its input is the app's encoded row, `features` int32 `[13]`,
/// unchanged (the graph slices it); its output is `category` `[27]`, the
/// softmax in `labels.json` order. Both are the session's own memory,
/// written and read in place; a row runs in microseconds, on the caller's
/// thread.
class RayoCategoriser implements CategoriserRuntime {
  RayoCategoriser._(this._model, this._session, this._output, this.outputSize);

  /// Throws [RayoException] when the file is damaged or is not the
  /// categoriser's, and [StateError] when its sizes differ from [width].
  factory RayoCategoriser.open(Uint8List bytes, int width) {
    final model = RayoModel.load(bytes);
    RayoSession? session;
    try {
      if (model.name != 'categoriser') {
        throw StateError('weights of ${model.name}, not the categoriser');
      }
      if (model.inputs.length != 1 || model.inputIndex('features') != 0) {
        throw StateError('inputs are not features alone');
      }
      final output = model.outputIndex(ModelManifest.categoryOutput);
      session = RayoSession(model);
      final shape = session.outputInfo(output).shape;
      if (session.inputInt32(0).length != width || shape.length != 1) {
        throw StateError(
          'features of ${session.inputInt32(0).length}, category of $shape',
        );
      }
      return RayoCategoriser._(model, session, output, shape[0]);
    } on Object {
      session?.close();
      model.close();
      rethrow;
    }
  }

  final RayoModel _model;
  final RayoSession _session;
  final int _output;
  var _closed = false;

  @override
  final int outputSize;

  /// The kernels the session runs, such as `x86-vnni`.
  String get kernels => _session.kernels;

  @override
  List<double> run(List<int> row) {
    if (_closed) throw StateError('closed');
    final input = _session.inputInt32(0);
    if (row.length != input.length) {
      throw ArgumentError.value(row.length, 'row', 'expected ${input.length}');
    }
    input.setAll(0, row);
    _session.run();
    return List<double>.of(_session.outputFloat32(_output));
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _session.close();
    _model.close();
  }
}
