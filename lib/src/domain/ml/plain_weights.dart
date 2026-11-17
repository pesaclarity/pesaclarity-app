import 'dart:convert';
import 'dart:typed_data';

/// The plain weights format version this app reads.
const plainWeightsFormatVersion = 1;

/// One tensor of a [PlainWeights] file.
class PlainTensor {
  PlainTensor._(this.shape, this.int8, this.float32, this.scales, this.axis);

  /// Row-major (C order), as in the TFLite graph.
  final List<int> shape;

  /// The values of an int8 tensor, else null.
  final Int8List? int8;

  /// The values of a float32 tensor, else null.
  final Float32List? float32;

  /// An int8 tensor's float32 scales: one per index along [axis], or one for
  /// the whole tensor when [axis] is null. Null for float32 tensors.
  final Float32List? scales;
  final int? axis;

  int get length => int8?.length ?? float32!.length;

  /// The real values as float32: a float32 tensor's own, or an int8
  /// tensor's times its one scale. Per-channel int8 tensors are kernels,
  /// which their layers read as integers and [scales].
  Float32List real() {
    final f = float32;
    if (f != null) return f;
    if (axis != null) throw StateError('one scale per channel');
    final q = int8!;
    final scale = scales![0];
    return Float32List.fromList([for (final v in q) v * scale]);
  }
}

/// A model's tensors in pesaclarity-ml's plain weights format, version 1
/// (pesaclarity-ml docs/WEIGHTS.md): `PCWT`, a uint32 format version, a
/// uint32 header length, a UTF-8 JSON header, then the tensors' bytes, all
/// little-endian. An int8 element's real value is
/// `scales[c] * (value - zero_point)`.
///
/// [PlainWeights.parse] throws [FormatException] on anything that does not
/// fit the spec: a file it cannot read is never half read.
class PlainWeights {
  PlainWeights._(this.model, this.sourceSha256, this.layers, this._tensors);

  factory PlainWeights.parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 12 || ascii.decode(bytes.sublist(0, 4)) != 'PCWT') {
      throw const FormatException('not a plain weights file');
    }
    final version = data.getUint32(4, Endian.little);
    if (version != plainWeightsFormatVersion) {
      throw FormatException('plain weights version $version');
    }
    final start = 12 + data.getUint32(8, Endian.little);
    if (start % 4 != 0 || start > bytes.length) {
      throw const FormatException('bad header length');
    }
    final header = jsonDecode(
      utf8.decode(bytes.sublist(12, start)),
    ) as Map<String, Object?>;
    if (header['format_version'] != version) {
      throw const FormatException('header and file disagree on the version');
    }
    final size = bytes.length - start;
    var end = 0;

    // The `count` elements of `width` bytes at `offset` of the data.
    int at(int offset, int length, int count, int width) {
      if (offset < 0 ||
          offset % 4 != 0 ||
          length != count * width ||
          offset + length > size) {
        throw const FormatException('tensor outside the data');
      }
      final padded = offset + (length + 3) ~/ 4 * 4;
      if (padded > end) end = padded;
      return start + offset;
    }

    final tensors = <String, PlainTensor>{};
    for (final t in (header['tensors']! as List).cast<Map<String, Object?>>()) {
      final shape = (t['shape']! as List).cast<int>();
      final count = shape.fold(1, (a, b) => a * b);
      final offset = t['offset']! as int;
      final length = t['bytes']! as int;
      final name = t['name']! as String;
      switch (t['dtype']) {
        case 'int8':
          final q = t['quantization']! as Map<String, Object?>;
          if (q['zero_point'] != 0) {
            // TFLite's weights are symmetric; anything else is a new format.
            throw FormatException('$name: zero point ${q['zero_point']}');
          }
          final axis = q['axis'] as int?;
          final n = axis == null ? 1 : shape[axis];
          final from = at(offset, length, count, 1);
          final scalesFrom = at(
            q['scales_offset']! as int,
            q['scales_bytes']! as int,
            n,
            4,
          );
          tensors[name] = PlainTensor._(
            shape,
            Int8List.fromList(Int8List.sublistView(bytes, from, from + count)),
            null,
            Float32List.fromList([
              for (var i = 0; i < n; i++)
                data.getFloat32(scalesFrom + 4 * i, Endian.little),
            ]),
            axis,
          );
        case 'float32':
          final from = at(offset, length, count, 4);
          tensors[name] = PlainTensor._(
            shape,
            null,
            Float32List.fromList([
              for (var i = 0; i < count; i++)
                data.getFloat32(from + 4 * i, Endian.little),
            ]),
            null,
            null,
          );
        default:
          throw FormatException('$name: dtype ${t['dtype']}');
      }
    }
    if (end != size) throw const FormatException('data after the last tensor');
    final source = header['source']! as Map<String, Object?>;
    return PlainWeights._(
      header['model']! as String,
      source['sha256']! as String,
      (header['layers']! as List).cast<Map<String, Object?>>(),
      tensors,
    );
  }

  /// Which model these are, such as `ask-reader`.
  final String model;

  /// The SHA-256 of the TFLite file they were read out of.
  final String sourceSha256;

  /// The layers in the order they run, as the header lists them.
  final List<Map<String, Object?>> layers;
  final Map<String, PlainTensor> _tensors;

  /// Tensor [name]; throws [FormatException] when there is none.
  PlainTensor operator [](String name) =>
      _tensors[name] ?? (throw FormatException('no tensor $name'));
}
