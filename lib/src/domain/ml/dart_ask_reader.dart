import 'dart:math' as math;
import 'dart:typed_data';

import '../ask/model_question_reader.dart';
import '../reader/reader_tokens.dart';
import 'plain_weights.dart';

/// The Ask reader's forward pass in plain Dart, from its plain weights
/// (`ask-reader.weights`), with no native library.
///
/// The network is pesaclarity-ml's `build_ask_reader`: token and shape
/// embeddings; three residual 1-D convolutions, the third dilated; a slot
/// head (a dense layer on each token's context and embedding, two residual
/// convolutions, a dense softmax); and an intent head on masked max and mean
/// pooling. [layers] is the list this code implements, and a weights file
/// that lists anything else is refused.
///
/// The weights are rayo-convert's int8 quantisation of the PyTorch model's
/// ONNX file (pesaclarity-ml docs/ASK.md), and this runs them as rayo does,
/// so it gives rayo's outputs (pesaclarity-ml docs/WEIGHTS.md; a copy of
/// akili's `reader_weights.forward`): before each int8 layer the float
/// input is quantised to int8 on the fly, the products are summed as
/// integers (exactly, in float32 lanes: every sum stays below 2^24) and the
/// sum is scaled back. A dilated convolution quantises each of its dilation
/// phases on its own, as rayo's conv1d does. Activations, and the pooling's
/// sums, are float32.
class DartAskReader implements AskReaderRuntime {
  DartAskReader._(
    this._tokens,
    this._tokenDim,
    this._shapes,
    this._shapeDim,
    this._conv1,
    this._conv2,
    this._conv3,
    this._slotHidden,
    this._slotContext,
    this._slotSpan,
    this._slots,
    this._intentHidden,
    this._intent,
  );

  /// Reads `ask-reader.weights`. Throws [FormatException] when the file is
  /// not the Ask reader's or does not fit [layers].
  factory DartAskReader.parse(Uint8List bytes) {
    final w = PlainWeights.parse(bytes);
    if (w.model != 'ask-reader') {
      throw FormatException('weights of ${w.model}, not the ask reader');
    }
    if (!_sameLayers(w.layers)) {
      throw const FormatException('layers this app does not implement');
    }
    final tokens = w['token_embedding.table'];
    final shapes = w['shape_embedding.table'];
    final tokenDim = tokens.shape[1];
    final shapeDim = shapes.shape[1];
    if (tokens.shape[0] != readerHashBuckets) {
      throw const FormatException('token table does not fit the tokeniser');
    }
    _Layer layer(String name, int inputs) {
      final spec = layers.firstWhere((l) => l.name == name);
      return _Layer.read(w, spec, inputs);
    }

    final e = tokenDim + shapeDim;
    final conv1 = layer('conv_1', e);
    final c = conv1.outputs;
    final slotHidden = layer('slot_hidden', c + e);
    final s = slotHidden.outputs;
    final intentHidden = layer('intent_hidden', 2 * c + e);
    return DartAskReader._(
      tokens.real(),
      tokenDim,
      shapes.real(),
      shapeDim,
      conv1,
      layer('conv_2', c),
      layer('conv_3', c),
      slotHidden,
      layer('slot_context', s),
      layer('slot_span', s),
      layer('slots', s),
      intentHidden,
      layer('intent', intentHidden.outputs),
    );
  }

  /// The layers this code implements, in the order they run.
  static const layers = [
    LayerSpec('token_embedding', 'embedding'),
    LayerSpec('shape_embedding', 'embedding'),
    LayerSpec('conv_1', 'conv1d', size: 3, dilation: 1, activation: 'relu'),
    LayerSpec('conv_2', 'conv1d', size: 5, dilation: 1, activation: 'relu'),
    LayerSpec('conv_3', 'conv1d', size: 3, dilation: 3, activation: 'relu'),
    LayerSpec('slot_hidden', 'dense', activation: 'relu'),
    LayerSpec(
      'slot_context',
      'conv1d',
      size: 5,
      dilation: 1,
      activation: 'relu',
    ),
    LayerSpec('slot_span', 'conv1d', size: 3, dilation: 2, activation: 'relu'),
    LayerSpec('slots', 'dense', activation: 'softmax'),
    LayerSpec('intent_hidden', 'dense', activation: 'relu'),
    LayerSpec('intent', 'dense', activation: 'softmax'),
  ];

  static bool _sameLayers(List<Map<String, Object?>> listed) {
    if (listed.length != layers.length) return false;
    for (var i = 0; i < layers.length; i++) {
      final l = layers[i];
      final m = listed[i];
      if (m['name'] != l.name ||
          m['kind'] != l.kind ||
          m['size'] != l.size ||
          m['dilation'] != l.dilation ||
          m['activation'] != l.activation) {
        return false;
      }
    }
    return true;
  }

  final Float32List _tokens;
  final int _tokenDim;
  final Float32List _shapes;
  final int _shapeDim;
  final _Layer _conv1;
  final _Layer _conv2;
  final _Layer _conv3;
  final _Layer _slotHidden;
  final _Layer _slotContext;
  final _Layer _slotSpan;
  final _Layer _slots;
  final _Layer _intentHidden;
  final _Layer _intent;

  @override
  (List<List<double>>, List<double>) run(List<int> input) {
    const t = readerMaxTokens;
    if (input.length != 2 * t) {
      throw ArgumentError.value(input.length, 'input', 'expected ${2 * t}');
    }
    final e = _tokenDim + _shapeDim;

    // Embeddings: [token | shape] per position.
    final emb = Float32List(t * e);
    final mask = Float32List(t);
    var n = 0;
    for (var i = 0; i < t; i++) {
      final token = input[i];
      final shape = input[t + i];
      if (token < 0 ||
          token * _tokenDim >= _tokens.length ||
          shape < 0 ||
          shape * _shapeDim >= _shapes.length) {
        throw ArgumentError('input id out of range at $i');
      }
      emb.setRange(i * e, i * e + _tokenDim, _tokens, token * _tokenDim);
      emb.setRange(i * e + _tokenDim, (i + 1) * e, _shapes, shape * _shapeDim);
      if (shape > 0) {
        mask[i] = 1;
        n++;
      }
    }

    // Context: three residual convolutions.
    var x = _conv1.apply(emb, t);
    x = _add(x, _conv2.apply(x, t));
    x = _add(x, _conv3.apply(x, t));
    final c = _conv1.outputs;

    // Slots: each token's context next to its own embedding.
    var s = _slotHidden.apply(_concatRows(x, c, emb, e, t), t);
    s = _add(s, _slotContext.apply(s, t));
    s = _add(s, _slotSpan.apply(s, t));
    final slotProbs = _slots.apply(s, t);
    final k = _slots.outputs;
    final slots = [
      for (var i = 0; i < t; i++)
        List<double>.of(Float32List.sublistView(slotProbs, i * k, (i + 1) * k)),
    ];

    // Intent: masked max and mean of the context, and the mean embedding.
    // As rayo sums them: one position after another, in float32.
    final count = math.max(n, 1);
    final pooled = Float32List(2 * c + e);
    for (var j = 0; j < c; j++) {
      var best = double.negativeInfinity;
      var sum = 0.0;
      for (var i = 0; i < t; i++) {
        final v = x[i * c + j] * mask[i];
        best = math.max(best, v - (1 - mask[i]) * 1e4);
        sum = _Layer._f32(sum + v);
      }
      pooled[j] = best;
      pooled[c + j] = _Layer._f32(sum / count);
    }
    for (var j = 0; j < e; j++) {
      var sum = 0.0;
      for (var i = 0; i < t; i++) {
        sum = _Layer._f32(sum + emb[i * e + j] * mask[i]);
      }
      pooled[2 * c + j] = _Layer._f32(sum / count);
    }
    final h = _intentHidden.apply(pooled, 1);
    final intent = List<double>.of(_intent.apply(h, 1));
    return (slots, intent);
  }

  @override
  void close() {}

  static Float32List _add(Float32List a, Float32List b) {
    final out = Float32List(a.length);
    for (var i = 0; i < a.length; i++) {
      out[i] = a[i] + b[i];
    }
    return out;
  }

  static Float32List _concatRows(
    Float32List a,
    int aw,
    Float32List b,
    int bw,
    int rows,
  ) {
    final w = aw + bw;
    final out = Float32List(rows * w);
    for (var r = 0; r < rows; r++) {
      out.setRange(r * w, r * w + aw, a, r * aw);
      out.setRange(r * w + aw, (r + 1) * w, b, r * bw);
    }
    return out;
  }
}

/// One entry of the weights file's layer list.
class LayerSpec {
  const LayerSpec(
    this.name,
    this.kind, {
    this.size,
    this.dilation,
    this.activation,
  });

  final String name;

  /// `embedding`, `conv1d` or `dense`.
  final String kind;

  /// A convolution's kernel size and dilation ("same" padding).
  final int? size;
  final int? dilation;

  /// `relu` or `softmax`; null for embeddings.
  final String? activation;
}

/// A dense layer (one tap) or a same-padded 1-D convolution, on rows of
/// [inputs] values, with its activation.
class _Layer {
  _Layer._(
    this.outputs,
    this.inputs,
    this.size,
    this.dilation,
    this._dense,
    this.softmax,
    this._kernel,
    this._scales,
    this._bias,
  );

  /// Layer [spec] of [w], checked to take rows of [inputs] values.
  factory _Layer.read(PlainWeights w, LayerSpec spec, int inputs) {
    final kernel = w['${spec.name}.kernel'];
    final bias = w['${spec.name}.bias'];
    final conv = spec.kind == 'conv1d';
    final size = conv ? spec.size! : 1;
    final shape = kernel.shape;
    final fits = conv
        ? shape.length == 4 &&
              shape[1] == 1 &&
              shape[2] == size &&
              shape[3] == inputs
        : shape.length == 2 && shape[1] == inputs;
    if (!fits ||
        inputs % 4 != 0 ||
        bias.float32 == null ||
        bias.length != shape[0] ||
        (kernel.int8 != null &&
            (kernel.axis != 0 ||
                kernel.scales!.length != shape[0] ||
                // A lane's integer sum must stay exact in float32.
                inputs ~/ 4 * size * 255 * 127 >= 1 << 24))) {
      throw FormatException('${spec.name}: tensors do not fit');
    }
    // int8 layers keep their integer values (exact in float32); float32
    // layers their real values.
    final values = kernel.float32 ?? Float32List(kernel.length);
    final q = kernel.int8;
    if (q != null) {
      for (var i = 0; i < q.length; i++) {
        values[i] = q[i].toDouble();
      }
    }
    return _Layer._(
      shape[0],
      inputs,
      size,
      conv ? spec.dilation! : 1,
      !conv,
      spec.activation == 'softmax',
      Float32List.fromList(values).buffer.asFloat32x4List(),
      kernel.scales,
      bias.float32!,
    );
  }

  final int outputs;
  final int inputs;
  final int size;
  final int dilation;
  final bool _dense;
  final bool softmax;

  /// `[outputs][size][inputs / 4]` lanes.
  final Float32x4List _kernel;

  /// Per output, for an int8 kernel; null for a float32 one.
  final Float32List? _scales;
  final Float32List _bias;

  /// The layer on [rows] rows of [x]: a convolution along the rows, or a
  /// dense layer on each row.
  Float32List apply(Float32List x, int rows) {
    final lanes = inputs ~/ 4;
    final scales = _scales;
    // Each row's input scale: rayo quantises a dense layer's rows one by
    // one and each dilation phase of a convolution (the rows i with
    // i % dilation == p) as a whole.
    final Float32List input;
    final rowScale = Float32List(rows);
    if (scales == null) {
      input = x;
    } else {
      input = Float32List(x.length);
      if (_dense) {
        for (var r = 0; r < rows; r++) {
          rowScale[r] = _quantise(x, input, inputs, r, 1, r + 1);
        }
      } else {
        for (var p = 0; p < dilation; p++) {
          final scale = _quantise(x, input, inputs, p, dilation, rows);
          for (var r = p; r < rows; r += dilation) {
            rowScale[r] = scale;
          }
        }
      }
    }
    final x4 = input.buffer.asFloat32x4List(
      input.offsetInBytes,
      input.length ~/ 4,
    );
    final out = Float32List(rows * outputs);
    final half = (size - 1) ~/ 2;
    for (var i = 0; i < rows; i++) {
      for (var o = 0; o < outputs; o++) {
        var acc = Float32x4.zero();
        for (var j = 0; j < size; j++) {
          final at = i + (j - half) * dilation;
          if (at < 0 || at >= rows) continue;
          final xi = at * lanes;
          final wi = (o * size + j) * lanes;
          for (var q = 0; q < lanes; q++) {
            acc += x4[xi + q] * _kernel[wi + q];
          }
        }
        final sum = acc.x + acc.y + acc.z + acc.w;
        // As rayo: the sum times (input scale * weight scale), then the
        // bias, in float32.
        final v = scales == null
            ? _f32(_bias[o] + sum)
            : _f32(_bias[o] + _f32(sum * _f32(rowScale[i] * scales[o])));
        out[i * outputs + o] = softmax || v > 0 ? v : 0;
      }
    }
    if (softmax) {
      for (var i = 0; i < rows; i++) {
        _softmax(out, i * outputs, outputs);
      }
    }
    return out;
  }

  static final _one = Float32List(1);
  static double _f32(double v) => (_one..[0] = v)[0];

  /// Quantises rows `from, from + step, ...` (below [end]) of the
  /// [width]-wide matrix [x] into [out] as `value - zero point` (integers),
  /// as rayo quantises one row (as TFLite's AsymmetricQuantizeFloats does):
  /// one scale and zero point for them all, the range widened to include 0,
  /// rounding halves away from zero. Returns the scale.
  static double _quantise(
    Float32List x,
    Float32List out,
    int width,
    int from,
    int step,
    int end,
  ) {
    var lo = 0.0;
    var hi = 0.0;
    for (var r = from; r < end; r += step) {
      for (var i = r * width; i < (r + 1) * width; i++) {
        final v = x[i];
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    if (lo == hi) {
      for (var r = from; r < end; r += step) {
        out.fillRange(r * width, (r + 1) * width, 0);
      }
      return 0;
    }
    final scale = (hi - lo) / 255;
    final zp = 128 + (lo / scale).abs() < 127 + (hi / scale).abs()
        ? -128 - lo / scale
        : 127 - hi / scale;
    final zero = zp <= -128 ? -128 : (zp >= 127 ? 127 : zp.round());
    final scaleF = _f32(scale);
    final inv = _f32(1 / scaleF);
    for (var r = from; r < end; r += step) {
      for (var i = r * width; i < (r + 1) * width; i++) {
        final q = _f32(zero + _f32(x[i] * inv)).round().clamp(-128, 127);
        out[i] = (q - zero).toDouble();
      }
    }
    return scaleF;
  }

  static void _softmax(Float32List x, int from, int length) {
    var top = double.negativeInfinity;
    for (var i = from; i < from + length; i++) {
      top = math.max(top, x[i]);
    }
    var sum = 0.0;
    final e = Float64List(length);
    for (var i = 0; i < length; i++) {
      e[i] = math.exp(x[from + i] - top);
      sum += e[i];
    }
    for (var i = 0; i < length; i++) {
      x[from + i] = e[i] / sum;
    }
  }
}
