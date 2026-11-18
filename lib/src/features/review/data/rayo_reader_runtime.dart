import 'dart:async';
import 'dart:typed_data';

import 'package:rayo/rayo.dart';

import '../../../domain/reader/message_reading.dart';
import '../../../domain/reader/model_reader.dart';
import '../../../domain/reader/reader_tokens.dart';

/// Opens `reader.weights` on rayo. Throws when rayo's native library cannot
/// load here or refuses the file, and the review inbox uses the rules
/// reader.
ReaderRuntime openMessageReader(Uint8List bytes) {
  if (!rayoAvailable()) {
    throw StateError("rayo's library cannot load here");
  }
  return RayoMessageReader.open(bytes);
}

/// The message reader on rayo: `reader.weights` with its graph (pesaclarity-ml
/// docs/READER.md), opened once and kept for the app's life. The app's
/// encoded message is rayo's two inputs, `tokens` (its first
/// [readerMaxTokens] ids) and `shapes` (the rest), with `T` bound to
/// [readerMaxTokens]; its outputs are `fields` `[T, 8]` and `kind` `[3]`.
/// Inputs and outputs are the session's own memory, written and read in
/// place.
///
/// The message being checked is read on the caller's thread (about 0.5 ms
/// on a 2.1 GHz Xeon core). Many at once, as Home counts every message to
/// check, run in a short-lived isolate on a second session of the same
/// model, one batch at a time, so they never wait on or for the first.
class RayoMessageReader implements BackgroundReaderRuntime {
  RayoMessageReader._(
    this._model,
    this._session,
    this._background,
    this._fields,
    this._kind,
  );

  /// Throws [RayoException] when the file is damaged or is not the message
  /// reader's, and [StateError] when its sizes differ from this app's.
  factory RayoMessageReader.open(Uint8List bytes) {
    final model = RayoModel.load(bytes);
    RayoSession? session;
    RayoSession? background;
    try {
      if (model.name != 'reader') {
        throw StateError('weights of ${model.name}, not the message reader');
      }
      final tokens = model.inputIndex('tokens');
      final shapes = model.inputIndex('shapes');
      final fields = model.outputIndex('fields');
      final kind = model.outputIndex('kind');
      if (tokens != 0 || shapes != 1) {
        throw StateError('inputs are not tokens, then shapes');
      }
      session = RayoSession(model)..bind('T', readerMaxTokens);
      final fieldShape = session.outputInfo(fields).shape;
      final kindShape = session.outputInfo(kind).shape;
      if (session.inputInt32(0).length != readerMaxTokens ||
          session.inputInt32(1).length != readerMaxTokens ||
          fieldShape.length != 2 ||
          fieldShape[0] != readerMaxTokens ||
          fieldShape[1] != ReaderField.values.length ||
          kindShape.length != 1 ||
          kindShape[0] != MessageKind.values.length) {
        throw StateError('fields of shape $fieldShape, kind of $kindShape');
      }
      background = RayoSession(model)..bind('T', readerMaxTokens);
      return RayoMessageReader._(model, session, background, fields, kind);
    } on Object {
      background?.close();
      session?.close();
      model.close();
      rethrow;
    }
  }

  final RayoModel _model;
  final RayoSession _session;
  final RayoSession _background;
  final int _fields;
  final int _kind;
  var _closed = false;
  Future<void> _last = Future.value();

  /// The kernels the session runs, such as `x86-vnni`.
  String get kernels => _session.kernels;

  @override
  (List<List<double>>, List<double>) run(List<int> input) {
    if (_closed) throw StateError('closed');
    return _read(_session, input, _fields, _kind);
  }

  @override
  Future<List<(List<List<double>>, List<double>)>> runAllInBackground(
    List<List<int>> inputs,
  ) {
    if (_closed) throw StateError('closed');
    final result = _last.then(
      (_) => _inIsolate(_background, inputs, _fields, _kind),
    );
    _last = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  // Static, so the isolate's closure holds the inputs and indices only.
  static Future<List<(List<List<double>>, List<double>)>> _inIsolate(
    RayoSession session,
    List<List<int>> inputs,
    int fields,
    int kind,
  ) {
    final ids = [for (final input in inputs) Int32List.fromList(input)];
    return runInIsolate(
      session,
      (s) => [for (final input in ids) _read(s, input, fields, kind)],
    );
  }

  static (List<List<double>>, List<double>) _read(
    RayoSession s,
    List<int> input,
    int fieldsOutput,
    int kindOutput,
  ) {
    const n = readerMaxTokens;
    if (input.length != 2 * n) {
      throw ArgumentError.value(input.length, 'input', 'expected ${2 * n}');
    }
    s.inputInt32(0).setRange(0, n, input);
    s.inputInt32(1).setRange(0, n, input, n);
    s.run();
    final fields = s.outputFloat32(fieldsOutput);
    final width = fields.length ~/ n;
    return (
      [
        for (var t = 0; t < n; t++)
          List<double>.of(fields.sublist(t * width, (t + 1) * width)),
      ],
      List<double>.of(s.outputFloat32(kindOutput)),
    );
  }

  /// Closes the model once any batch in the background is done.
  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _session.close();
    unawaited(
      _last.then((_) {
        _background.close();
        _model.close();
      }),
    );
  }
}
