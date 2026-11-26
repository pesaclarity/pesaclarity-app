import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:rayo/rayo.dart';

/// How a reply went.
class SlmStats {
  const SlmStats({
    required this.promptTokens,
    required this.replyTokens,
    required this.seconds,
    required this.rssBytes,
    required this.threads,
    this.loadSeconds,
  });

  final int promptTokens;
  final int replyTokens;
  final double seconds;
  final int rssBytes;
  final int threads;

  /// How long the model took to open, on the first reply only.
  final double? loadSeconds;

  double get tokensPerSecond => seconds <= 0 ? 0 : replyTokens / seconds;

  /// The small debug line under an answer.
  String get line => [
    '${tokensPerSecond.toStringAsFixed(1)} tokens/s',
    '$promptTokens prompt tokens',
    '$replyTokens reply tokens',
    '${(rssBytes / (1024 * 1024)).round()} MB',
    '$threads threads',
    if (loadSeconds != null) 'opened in ${loadSeconds!.toStringAsFixed(1)} s',
  ].join(' · ');
}

/// What a reply sends as it is made.
sealed class SlmEvent {
  const SlmEvent();
}

class SlmPiece extends SlmEvent {
  const SlmPiece(this.text);
  final String text;
}

class SlmDone extends SlmEvent {
  const SlmDone(this.stats);
  final SlmStats stats;
}

class SlmFailed extends SlmEvent {
  const SlmFailed(this.reason);
  final String reason;
}

/// A language model that answers one question at a time.
abstract interface class SlmGenerator {
  /// The reply to [question], with [system] (the rules and facts) before
  /// it. Each question starts afresh: earlier ones are not kept.
  Stream<SlmEvent> ask({required String system, required String question});

  /// Ends the reply being made.
  void stop();

  Future<void> close();
}

/// The downloaded money model at [path] on rayo, in a long-lived isolate so
/// Ask never waits. When rayo cannot run it, the reply fails and says why,
/// and Ask answers as it does without a model. Nothing is written anywhere:
/// prompts and replies live in memory only.
class RayoSlmGenerator implements SlmGenerator {
  RayoSlmGenerator({
    required this.path,
    bool Function() available = rayoAvailable,
  }) : _isAvailable = available;

  /// The model file.
  final String path;
  final bool Function() _isAvailable;
  final Pointer<Int32> _stop = malloc<Int32>()..value = 0;
  Isolate? _isolate;
  SendPort? _toIsolate;
  ReceivePort? _fromIsolate;
  StreamController<SlmEvent>? _current;
  Completer<void>? _ready;
  bool _closed = false;

  Future<void> _start() async {
    if (_ready != null) return _ready!.future;
    final ready = _ready = Completer<void>();
    final path = this.path;
    if (!File(path).existsSync()) {
      _ready = null;
      throw StateError('The model file is not on this phone.');
    }
    if (!_isAvailable()) {
      _ready = null;
      throw StateError("rayo's library cannot load here");
    }
    final port = _fromIsolate = ReceivePort();
    port.listen(_onMessage);
    _isolate = await Isolate.spawn(_main, (
      port.sendPort,
      path,
      _stop.address,
    ), debugName: 'slm');
    return ready.future;
  }

  void _onMessage(Object? message) {
    if (message is SendPort) {
      _toIsolate = message;
      _ready?.complete();
      return;
    }
    final m = message! as List<Object?>;
    final out = _current;
    switch (m[0]) {
      case 'piece':
        out?.add(SlmPiece(m[1]! as String));
      case 'done':
        out?.add(
          SlmDone(
            SlmStats(
              promptTokens: m[1]! as int,
              replyTokens: m[2]! as int,
              seconds: m[3]! as double,
              rssBytes: m[4]! as int,
              threads: m[5]! as int,
              loadSeconds: m[6] as double?,
            ),
          ),
        );
        out?.close();
        _current = null;
      case 'error':
        final reason = m[1]! as String;
        out?.add(SlmFailed(reason));
        out?.close();
        _current = null;
        final ready = _ready;
        if (ready != null && !ready.isCompleted) {
          _ready = null;
          ready.completeError(StateError(reason));
        }
    }
  }

  @override
  Stream<SlmEvent> ask({required String system, required String question}) {
    final out = StreamController<SlmEvent>();
    unawaited(() async {
      try {
        if (_closed) throw StateError('closed');
        await _start();
        _stop.value = 0;
        _current = out;
        _toIsolate!.send((system, question));
      } on Object catch (e) {
        out.add(SlmFailed(e is StateError ? e.message : '$e'));
        await out.close();
      }
    }());
    return out.stream;
  }

  @override
  void stop() => _stop.value = 1;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _stop.value = 1;
    _toIsolate?.send(null);
    await _current?.close();
    _fromIsolate?.close();
    // Let the isolate free its native memory before ours goes.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _isolate?.kill();
    malloc.free(_stop);
  }

  /// The isolate: opens the model once, then answers each question.
  static void _main((SendPort, String, int) args) {
    final (toMain, path, stopAddress) = args;
    final stop = Pointer<Int32>.fromAddress(stopAddress);
    final opening = Stopwatch()..start();
    RayoModel? model;
    RayoTokenizer? tokenizer;
    RayoGenerator? generator;
    try {
      model = RayoModel.map(path);
      tokenizer = RayoTokenizer.fromModel(model);
      generator = RayoGenerator(
        model,
        tokenizer,
        // Greedy: the chart line has one right spelling.
        temperature: 0,
        repetitionPenalty: 1,
        maxTokens: 200,
        context: 2048,
        // A float32 key/value cache: an int8 one costs the fine-tuned models
        // their chart line (pesaclarity-ml, SLM-QUANT on the release).
        int8Cache: false,
      );
    } on Object catch (e) {
      generator?.close();
      tokenizer?.close();
      model?.close();
      toMain.send(['error', 'rayo could not open the model: $e']);
      return;
    }
    double? loadSeconds = opening.elapsedMicroseconds / 1e6;
    final inbox = ReceivePort();
    toMain.send(inbox.sendPort);
    final g = generator;
    inbox.listen((message) {
      if (message == null) {
        inbox.close();
        g.close();
        tokenizer!.close();
        model!.close();
        return;
      }
      final (system, question) = message as (String, String);
      try {
        g
          ..reset()
          ..chat(question, system: system);
        final promptTokens = g.position;
        final clock = Stopwatch()..start();
        for (final piece in g.reply()) {
          toMain.send(['piece', piece]);
          if (stop.value != 0) {
            g.cancel();
            break;
          }
        }
        clock.stop();
        toMain.send([
          'done',
          promptTokens,
          g.position - promptTokens,
          clock.elapsedMicroseconds / 1e6,
          ProcessInfo.currentRss,
          g.threads,
          loadSeconds,
        ]);
        loadSeconds = null;
      } on Object catch (e) {
        toMain.send(['error', '$e']);
      }
    });
  }
}
