import 'dart:convert';
import 'dart:typed_data';

/// One tensor for [writePlainWeights].
class PlainTensorSpec {
  PlainTensorSpec.float32(this.name, this.shape, List<double> values)
    : int8 = null,
      float32 = values,
      scales = null,
      axis = null;

  PlainTensorSpec.int8(
    this.name,
    this.shape,
    List<int> values, {
    required List<double> this.scales,
    this.axis,
  }) : int8 = values,
       float32 = null;

  final String name;
  final List<int> shape;
  final List<int>? int8;
  final List<double>? float32;
  final List<double>? scales;
  final int? axis;
}

/// A file in pesaclarity-ml's plain weights format, version 1
/// (docs/WEIGHTS.md), holding [tensors] and no graph: what the app's Dart
/// readers need from it, for tests of networks too small to export.
Uint8List writePlainWeights({
  required String model,
  required List<PlainTensorSpec> tensors,
}) {
  final data = BytesBuilder();
  int put(Uint8List bytes) {
    final offset = data.length;
    data.add(bytes);
    while (data.length % 4 != 0) {
      data.addByte(0);
    }
    return offset;
  }

  Uint8List floats(List<double> v) {
    final b = ByteData(v.length * 4);
    for (var i = 0; i < v.length; i++) {
      b.setFloat32(i * 4, v[i], Endian.little);
    }
    return b.buffer.asUint8List();
  }

  final entries = <Map<String, Object?>>[];
  for (final t in tensors) {
    final q = t.int8;
    if (q != null) {
      final offset = put(
        Uint8List.fromList(Int8List.fromList(q).buffer.asUint8List()),
      );
      final scales = floats(t.scales!);
      final scalesOffset = put(scales);
      entries.add({
        'name': t.name,
        'dtype': 'int8',
        'shape': t.shape,
        'offset': offset,
        'bytes': q.length,
        'quantization': {
          'zero_point': 0,
          'axis': t.axis,
          'scales_offset': scalesOffset,
          'scales_bytes': scales.length,
        },
      });
    } else {
      final bytes = floats(t.float32!);
      entries.add({
        'name': t.name,
        'dtype': 'float32',
        'shape': t.shape,
        'offset': put(bytes),
        'bytes': bytes.length,
      });
    }
  }
  var header = utf8.encode(
    jsonEncode({
      'format_version': 1,
      'model': model,
      'source': {'file': '$model.onnx', 'sha256': '00' * 32, 'size_bytes': 0},
      'layers': <Object?>[],
      'tensors': entries,
    }),
  );
  header = Uint8List.fromList([
    ...header,
    for (var i = 0; i < (4 - (12 + header.length) % 4) % 4; i++) 0x20,
  ]);
  final out = BytesBuilder()
    ..add(ascii.encode('PCWT'))
    ..add(
      (ByteData(8)
            ..setUint32(0, 1, Endian.little)
            ..setUint32(4, header.length, Endian.little))
          .buffer
          .asUint8List(),
    )
    ..add(header)
    ..add(data.toBytes());
  return out.toBytes();
}
