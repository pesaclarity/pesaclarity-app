// Spike for the on-device ML decision record (docs, decisions): can the Ask
// reader run in plain Dart, with no native library, and give TFLite's
// answers? Not used by the app; no build switches to it.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../ask/model_question_reader.dart';

/// The Ask reader's weights in the plain format `tool/ask_reader_weights.py`
/// writes from the bundled `ask-reader.tflite`: `PCW1`, a uint32 header
/// length, a JSON header, then little-endian tensors. int8 tensors carry
/// per-channel float32 scales in `<name>.scale`.
class PlainWeights {
  PlainWeights._(this.modelSha256, this.layers, this._tensors);

  factory PlainWeights.parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 8 || ascii.decode(bytes.sublist(0, 4)) != 'PCW1') {
      throw const FormatException('not a PCW1 weights file');
    }
    final headerLength = data.getUint32(4, Endian.little);
    final header = jsonDecode(
      utf8.decode(bytes.sublist(8, 8 + headerLength)),
    ) as Map<String, Object?>;
    final start = 8 + headerLength;
    final tensors = <String, ({List<int> shape, List<double> values})>{};
    for (final t in (header['tensors']! as List).cast<Map<String, Object?>>()) {
      final shape = (t['shape']! as List).cast<int>();
      final count = shape.fold(1, (a, b) => a * b);
      final at = start + (t['offset']! as int);
      final values = Float64List(count);
      switch (t['dtype']) {
        case 'int8':
          for (var i = 0; i < count; i++) {
            values[i] = data.getInt8(at + i).toDouble();
          }
        case 'float32':
          for (var i = 0; i < count; i++) {
            values[i] = data.getFloat32(at + 4 * i, Endian.little);
          }
        default:
          throw FormatException('dtype ${t['dtype']}');
      }
      tensors[t['name']! as String] = (shape: shape, values: values);
    }
    return PlainWeights._(
      header['model_sha256']! as String,
      (header['layers']! as List).cast<Map<String, Object?>>(),
      tensors,
    );
  }

  final String modelSha256;
  final List<Map<String, Object?>> layers;
  final Map<String, ({List<int> shape, List<double> values})> _tensors;

  List<int> shape(String name) => _tensors[name]!.shape;

  /// [name]'s values as floats: int8 weights times their per-channel scale
  /// (channels along the first dimension).
  Float64List dequantised(String name) {
    final t = _tensors[name]!;
    final scale = _tensors['$name.scale']?.values;
    final out = Float64List.fromList(t.values);
    if (scale == null) return out;
    final perChannel = out.length ~/ t.shape.first;
    for (var i = 0; i < out.length; i++) {
      out[i] *= scale.length == 1 ? scale[0] : scale[i ~/ perChannel];
    }
    return out;
  }

  bool isInt8(String name) => _tensors.containsKey('$name.scale');
}

/// [v] as float32 lanes; empty when rows of [width] do not split into fours.
Float32x4List _lanes(List<double> v, int width) => width % 4 == 0
    ? Float32List.fromList(v).buffer.asFloat32x4List()
    : Float32x4List(0);

class _Conv {
  _Conv(PlainWeights w, this.name, this.size, this.dilation)
    : kernel = w.dequantised('$name.kernel'),
      bias = w.dequantised('$name.bias'),
      outputs = w.shape('$name.kernel')[0],
      inputs = w.shape('$name.kernel')[3],
      hybrid = w.isInt8('$name.kernel');

  final String name;
  final int size;
  final int dilation;
  final Float64List kernel; // [out][1][size][in]
  late final Float32x4List kernel4 = _lanes(kernel, inputs);
  final Float64List bias;
  final int outputs;
  final int inputs;
  final bool hybrid;
}

class _Dense {
  _Dense(PlainWeights w, String name)
    : kernel = w.dequantised('$name.kernel'),
      bias = w.dequantised('$name.bias'),
      outputs = w.shape('$name.kernel')[0],
      inputs = w.shape('$name.kernel')[1],
      hybrid = w.isInt8('$name.kernel');

  final Float64List kernel; // [out][in]
  late final Float32x4List kernel4 = _lanes(kernel, inputs);
  final Float64List bias;
  final int outputs;
  final int inputs;
  final bool hybrid;
}

/// The Ask reader's forward pass in plain Dart, for exactly the layers this
/// model has: two embeddings, 1-D convolutions (some dilated), dense layers,
/// ReLU, masked max and mean pooling, and softmax.
///
/// With [hybrid] (the default) it copies how TFLite runs this
/// dynamic-range-quantised model: int8 weights, and each layer's float input
/// quantised to int8 on the fly. Without it, it computes in floats with the
/// dequantised weights.
class DartAskReader implements AskReaderRuntime {
  DartAskReader(PlainWeights w, {this.hybrid = true, this.simd = false})
    : _tokens = w.dequantised('token_embedding.table'),
      _tokenDim = w.shape('token_embedding.table')[1],
      _tokenRows = w.shape('token_embedding.table')[0],
      _shapes = w.dequantised('shape_embedding.table'),
      _shapeDim = w.shape('shape_embedding.table')[1],
      _shapeRows = w.shape('shape_embedding.table')[0],
      _conv = {
        for (final l in w.layers)
          if (l['kind'] == 'conv1d')
            l['name']! as String: _Conv(
              w,
              l['name']! as String,
              l['size']! as int,
              l['dilation']! as int,
            ),
      },
      _dense = {
        for (final l in w.layers)
          if (l['kind'] == 'dense')
            l['name']! as String: _Dense(w, l['name']! as String),
      };

  final bool hybrid;

  /// Multiply-adds four float32 lanes at a time (Float32x4) instead of one
  /// double at a time: faster, with float32 rounding.
  final bool simd;
  final Float64List _tokens;
  final int _tokenDim;
  final int _tokenRows;
  final Float64List _shapes;
  final int _shapeDim;
  final int _shapeRows;
  final Map<String, _Conv> _conv;
  final Map<String, _Dense> _dense;

  @override
  (List<List<double>>, List<double>) run(List<int> input) {
    final t = input.length ~/ 2;
    final e = _tokenDim + _shapeDim;

    // Embeddings: [token | shape] per position.
    final emb = Float64List(t * e);
    final mask = Float64List(t);
    for (var i = 0; i < t; i++) {
      final token = input[i];
      final shape = input[t + i];
      if (token < 0 ||
          token >= _tokenRows ||
          shape < 0 ||
          shape >= _shapeRows) {
        throw ArgumentError('input id out of range at $i');
      }
      emb.setRange(i * e, i * e + _tokenDim, _tokens, token * _tokenDim);
      emb.setRange(i * e + _tokenDim, (i + 1) * e, _shapes, shape * _shapeDim);
      mask[i] = shape > 0 ? 1 : 0;
    }
    var n = 0.0;
    for (final m in mask) {
      n += m;
    }
    n = math.max(n, 1);

    // Context: three residual convolutions.
    var x = _convolve(emb, t, _conv['conv_1']!);
    x = _add(x, _convolve(x, t, _conv['conv_2']!));
    x = _add(x, _convolve(x, t, _conv['conv_3']!));
    final c = _conv['conv_1']!.outputs;

    // Slots: each token's context next to its own embedding.
    var s = _denseRows(
      _concatRows(x, c, emb, e, t),
      t,
      _dense['slot_hidden']!,
      relu: true,
    );
    s = _add(s, _convolve(s, t, _conv['slot_context']!));
    s = _add(s, _convolve(s, t, _conv['slot_span']!));
    final slotLogits = _denseRows(s, t, _dense['slots']!, relu: false);
    final k = _dense['slots']!.outputs;
    final slots = [
      for (var i = 0; i < t; i++)
        _softmax(Float64List.sublistView(slotLogits, i * k, (i + 1) * k)),
    ];

    // Intent: masked max and mean of the context, and the mean embedding.
    final pooled = Float64List(2 * c + e);
    for (var j = 0; j < c; j++) {
      var best = double.negativeInfinity;
      var sum = 0.0;
      for (var i = 0; i < t; i++) {
        final v = x[i * c + j] * mask[i];
        best = math.max(best, v - (1 - mask[i]) * 1e4);
        sum += v;
      }
      pooled[j] = best;
      pooled[c + j] = sum / n;
    }
    for (var j = 0; j < e; j++) {
      var sum = 0.0;
      for (var i = 0; i < t; i++) {
        sum += emb[i * e + j] * mask[i];
      }
      pooled[2 * c + j] = sum / n;
    }
    final h = _denseRows(pooled, 1, _dense['intent_hidden']!, relu: true);
    final intent = _softmax(_denseRows(h, 1, _dense['intent']!, relu: false));
    return (slots, intent);
  }

  @override
  void close() {}

  /// Same-padded 1-D convolution with ReLU, `[t][in]` to `[t][out]`.
  Float64List _convolve(Float64List x, int t, _Conv l) {
    final cin = l.inputs;
    var input = x;
    if (hybrid && l.hybrid) {
      // TFLite runs a dilated convolution as SPACE_TO_BATCH_ND, so each
      // phase (positions i with i % dilation == p) is quantised on its own.
      input = Float64List.fromList(x);
      for (var p = 0; p < l.dilation; p++) {
        _quantise(input, cin, p, l.dilation, t);
      }
    }
    final outputs = l.outputs;
    final size = l.size;
    final dilation = l.dilation;
    final kernel = l.kernel;
    final bias = l.bias;
    final out = Float64List(t * outputs);
    final half = (size - 1) ~/ 2;
    if (simd && cin % 4 == 0) {
      final x4 = Float32List.fromList(input).buffer.asFloat32x4List();
      final k4 = l.kernel4;
      final c4 = cin ~/ 4;
      for (var i = 0; i < t; i++) {
        for (var o = 0; o < outputs; o++) {
          var acc = Float32x4.zero();
          for (var j = 0; j < size; j++) {
            final at = i + (j - half) * dilation;
            if (at < 0 || at >= t) continue;
            final xi = at * c4;
            final wi = (o * size + j) * c4;
            for (var q = 0; q < c4; q++) {
              acc += x4[xi + q] * k4[wi + q];
            }
          }
          final v = bias[o] + acc.x + acc.y + acc.z + acc.w;
          out[i * outputs + o] = v > 0 ? v : 0;
        }
      }
      return out;
    }
    for (var i = 0; i < t; i++) {
      for (var o = 0; o < outputs; o++) {
        var acc = bias[o];
        for (var j = 0; j < size; j++) {
          final at = i + (j - half) * dilation;
          if (at < 0 || at >= t) continue;
          final xi = at * cin;
          final wi = (o * size + j) * cin;
          for (var q = 0; q < cin; q++) {
            acc += input[xi + q] * kernel[wi + q];
          }
        }
        out[i * outputs + o] = acc > 0 ? acc : 0;
      }
    }
    return out;
  }

  /// A dense layer on each of [rows] rows.
  Float64List _denseRows(
    Float64List x,
    int rows,
    _Dense l, {
    required bool relu,
  }) {
    var input = x;
    if (hybrid && l.hybrid) {
      input = Float64List.fromList(x);
      for (var r = 0; r < rows; r++) {
        _quantise(input, l.inputs, r, 1, r + 1);
      }
    }
    final inputs = l.inputs;
    final outputs = l.outputs;
    final kernel = l.kernel;
    final bias = l.bias;
    final out = Float64List(rows * outputs);
    if (simd && inputs % 4 == 0) {
      final x4 = Float32List.fromList(input).buffer.asFloat32x4List();
      final k4 = l.kernel4;
      final c4 = inputs ~/ 4;
      for (var r = 0; r < rows; r++) {
        for (var o = 0; o < outputs; o++) {
          var acc = Float32x4.zero();
          for (var q = 0; q < c4; q++) {
            acc += x4[r * c4 + q] * k4[o * c4 + q];
          }
          final v = bias[o] + acc.x + acc.y + acc.z + acc.w;
          out[r * outputs + o] = relu && v < 0 ? 0 : v;
        }
      }
      return out;
    }
    for (var r = 0; r < rows; r++) {
      final xi = r * inputs;
      for (var o = 0; o < outputs; o++) {
        var acc = bias[o];
        final wi = o * inputs;
        for (var q = 0; q < inputs; q++) {
          acc += input[xi + q] * kernel[wi + q];
        }
        out[r * outputs + o] = relu && acc < 0 ? 0 : acc;
      }
    }
    return out;
  }

  static final _f32 = Float32List(1);
  static double _float(double v) => (_f32..[0] = v)[0];

  /// Replaces rows `from, from + step, ...` (below [end]) of the
  /// [width]-wide matrix [x] with their int8 round trip, as TFLite's
  /// AsymmetricQuantizeFloats does for one batch row: one scale and zero
  /// point for them all, the range widened to include 0.
  static void _quantise(Float64List x, int width, int from, int step, int end) {
    var lo = 0.0;
    var hi = 0.0;
    for (var r = from; r < end; r += step) {
      for (var i = r * width; i < (r + 1) * width; i++) {
        lo = math.min(lo, x[i]);
        hi = math.max(hi, x[i]);
      }
    }
    final scale = (hi - lo) / 255;
    final zp = 128 + (lo / scale).abs() < 127 + (hi / scale).abs()
        ? -128 - lo / scale
        : 127 - hi / scale;
    final zero = lo == hi
        ? 0
        : (zp <= -128 ? -128 : (zp >= 127 ? 127 : zp.round()));
    final scaleF = _float(scale);
    final inv = _float(1 / scaleF);
    for (var r = from; r < end; r += step) {
      for (var i = r * width; i < (r + 1) * width; i++) {
        if (lo == hi) {
          x[i] = 0;
          continue;
        }
        final q = _float(zero + _float(x[i] * inv)).round().clamp(-128, 127);
        x[i] = (q - zero) * scaleF;
      }
    }
  }

  static Float64List _add(Float64List a, Float64List b) {
    final out = Float64List(a.length);
    for (var i = 0; i < a.length; i++) {
      out[i] = a[i] + b[i];
    }
    return out;
  }

  static Float64List _concatRows(
    Float64List a,
    int aw,
    Float64List b,
    int bw,
    int rows,
  ) {
    final w = aw + bw;
    final out = Float64List(rows * w);
    for (var r = 0; r < rows; r++) {
      out.setRange(r * w, r * w + aw, a, r * aw);
      out.setRange(r * w + aw, (r + 1) * w, b, r * bw);
    }
    return out;
  }

  static List<double> _softmax(List<double> x) {
    var top = double.negativeInfinity;
    for (final v in x) {
      top = math.max(top, v);
    }
    final e = [for (final v in x) math.exp(v - top)];
    final sum = e.fold(0.0, (a, b) => a + b);
    return [for (final v in e) v / sum];
  }
}
