import 'dart:async';
import 'dart:typed_data';

import 'package:rayo/rayo.dart';

import '../../../domain/ask/model_question_reader.dart';
import '../../../domain/ask/model_reply_writer.dart';
import '../../../domain/ml/dart_ask_reader.dart';
import '../../../domain/reader/reader_tokens.dart';

/// Opens `ask-reader.weights` on rayo, or on [DartAskReader] when rayo's
/// native library cannot load here or refuses the file. Throws only when
/// neither can read it.
AskReaderRuntime openAskReader(Uint8List bytes) {
  if (rayoAvailable()) {
    try {
      return RayoAskReader.open(bytes);
    } on Object {
      // The Dart reader reads the same file.
    }
  }
  return DartAskReader.parse(bytes);
}

/// Opens `ask-writer.weights` on rayo. Throws when rayo's native library
/// cannot load here, and Ask words its replies with the templates.
AskWriterRuntime openAskWriter(Uint8List bytes, AskWriterManifest manifest) =>
    RayoAskWriter.open(
      bytes,
      length: manifest.length,
      vocab: manifest.vocabSize,
    );

/// Runs [task] after the earlier runs queued on the same session, so two
/// runs never overlap.
class _Queue {
  Future<void> _last = Future.value();
  int pending = 0;
  bool closed = false;

  Future<R> add<R>(Future<R> Function() task) {
    pending++;
    final result = _last.then((_) {
      if (closed) throw StateError('closed');
      return task();
    });
    _last = result
        .then((_) {}, onError: (Object _) {})
        .whenComplete(() => pending--);
    return result;
  }

  /// Runs [then] once every queued run is done.
  void close(void Function() then) {
    closed = true;
    unawaited(_last.then((_) => then()));
  }
}

/// The Ask reader on rayo: `ask-reader.weights` with its graph, one session
/// kept for the app's life. Its inputs and outputs are the session's own
/// memory, written and read in place; a question allocates nothing native.
class RayoAskReader implements BackgroundAskReaderRuntime {
  RayoAskReader._(this._model, this._session, this._slots, this._intent);

  /// Throws [RayoException] when the file is damaged or is not the Ask
  /// reader's, and [StateError] when its sizes differ from this app's.
  factory RayoAskReader.open(Uint8List bytes) {
    final model = RayoModel.load(bytes);
    RayoSession? session;
    try {
      if (model.name != 'ask-reader') {
        throw StateError('weights of ${model.name}, not the ask reader');
      }
      final tokens = model.inputIndex('tokens');
      final shapes = model.inputIndex('shapes');
      final slots = model.outputIndex('slots');
      final intent = model.outputIndex('intent');
      if (tokens != 0 || shapes != 1) {
        throw StateError('inputs are not tokens, then shapes');
      }
      session = RayoSession(model)..bind('T', readerMaxTokens);
      final slotShape = session.outputInfo(slots).shape;
      if (session.inputInt32(0).length != readerMaxTokens ||
          slotShape.length != 2 ||
          slotShape[0] != readerMaxTokens) {
        throw StateError('slots of shape $slotShape');
      }
      return RayoAskReader._(model, session, slots, intent);
    } on Object {
      session?.close();
      model.close();
      rethrow;
    }
  }

  final RayoModel _model;
  final RayoSession _session;
  final int _slots;
  final int _intent;
  final _queue = _Queue();

  /// The kernels the session runs, such as `neon-dotprod`.
  String get kernels => _session.kernels;

  @override
  (List<List<double>>, List<double>) run(List<int> input) {
    if (_queue.pending > 0) throw StateError('a run is in progress');
    return _read(_session, input, _slots, _intent);
  }

  @override
  Future<(List<List<double>>, List<double>)> runInBackground(List<int> input) =>
      _queue.add(() => _inIsolate(_session, input, _slots, _intent));

  // Static, so the isolate's closure holds the input and indices only.
  static Future<(List<List<double>>, List<double>)> _inIsolate(
    RayoSession session,
    List<int> input,
    int slots,
    int intent,
  ) {
    final ids = Int32List.fromList(input);
    return runInIsolate(session, (s) => _read(s, ids, slots, intent));
  }

  static (List<List<double>>, List<double>) _read(
    RayoSession s,
    List<int> input,
    int slots,
    int intent,
  ) {
    const n = readerMaxTokens;
    if (input.length != 2 * n) {
      throw ArgumentError.value(input.length, 'input', 'expected ${2 * n}');
    }
    s.inputInt32(0).setRange(0, n, input);
    s.inputInt32(1).setRange(0, n, input, n);
    s.run();
    final labels = s.outputFloat32(slots);
    final width = labels.length ~/ n;
    return (
      [
        for (var t = 0; t < n; t++)
          List<double>.of(labels.sublist(t * width, (t + 1) * width)),
      ],
      List<double>.of(s.outputFloat32(intent)),
    );
  }

  @override
  void close() => _queue.close(() {
    _session.close();
    _model.close();
  });
}

/// The Ask writer on rayo: `ask-writer.weights`, a decoder with a key/value
/// cache. A reply runs the facts once, then one token per step, in a
/// short-lived isolate on the session kept for the app's life, so the UI
/// thread never waits on it. Replies decode one at a time.
class RayoAskWriter implements AskWriterRuntime {
  RayoAskWriter._(this._model, this._session, this._length, this._vocab);

  /// Throws [RayoException] when the file is damaged or is not the Ask
  /// writer's, and [StateError] when its sizes differ from [length] and
  /// [vocab].
  factory RayoAskWriter.open(
    Uint8List bytes, {
    required int length,
    required int vocab,
  }) {
    final model = RayoModel.load(bytes);
    RayoSession? session;
    try {
      if (model.name != 'ask-writer') {
        throw StateError('weights of ${model.name}, not the ask writer');
      }
      session = RayoSession(model)
        ..bind('P', 0)
        ..bind('T', length);
      final logits = session.outputInfo(model.outputIndex('logits')).shape;
      if (session.inputInt32(0).length != length ||
          logits.isEmpty ||
          logits.last != vocab) {
        throw StateError('expected $length tokens in, $vocab logits out');
      }
      return RayoAskWriter._(model, session, length, vocab);
    } on Object {
      session?.close();
      model.close();
      rethrow;
    }
  }

  final RayoModel _model;
  final RayoSession _session;
  final int _length;
  final int _vocab;
  final _queue = _Queue();

  @override
  Future<List<int>?> decode(WriterDecode request) {
    if (request.length != _length || request.vocabSize != _vocab) {
      throw ArgumentError('the request does not fit this model');
    }
    return _queue.add(() => _inIsolate(_session, request));
  }

  static Future<List<int>?> _inIsolate(
    RayoSession session,
    WriterDecode request,
  ) => runInIsolate(session, (s) => decodeOn(s, request));

  /// Decodes [request] on [s]: the prefix in one run, then each new token,
  /// reading the past from the cache. The logits are a view of the
  /// session's memory, read before the next run.
  static List<int>? decodeOn(RayoSession s, WriterDecode request) {
    var cached = 0;
    s.reset();
    return decodeReply((tokens, position) {
      final upto = position + 1;
      s
        ..bind('P', cached)
        ..bind('T', upto - cached);
      s.inputInt32(0).setRange(0, upto - cached, tokens, cached);
      s.run();
      cached = upto;
      return s.outputFloat32(0);
    }, request);
  }

  @override
  void close() => _queue.close(() {
    _session.close();
    _model.close();
  });
}
