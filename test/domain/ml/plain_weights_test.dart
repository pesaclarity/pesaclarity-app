import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/ml/dart_ask_reader.dart';
import 'package:pesaclarity/src/domain/ml/plain_weights.dart';
import 'package:pesaclarity/src/domain/reader/reader_tokens.dart';

/// The plain weights format (pesaclarity-ml docs/WEIGHTS.md) on the bundled
/// Ask reader's file: it reads, and anything that does not fit is refused.
void main() {
  final bytes = File('assets/models/ask/ask-reader.weights').readAsBytesSync();

  Uint8List changed(void Function(ByteData data) change) {
    final copy = Uint8List.fromList(bytes);
    change(ByteData.sublistView(copy));
    return copy;
  }

  /// The file with its JSON header edited, sizes kept consistent.
  Uint8List withHeader(
    Map<String, Object?> Function(Map<String, Object?>) edit,
  ) {
    final length = ByteData.sublistView(bytes).getUint32(8, Endian.little);
    final header = jsonDecode(
      utf8.decode(bytes.sublist(12, 12 + length)),
    ) as Map<String, Object?>;
    var json = utf8.encode(jsonEncode(edit(header)));
    json = Uint8List.fromList([
      ...json,
      for (var i = 0; i < (4 - (12 + json.length) % 4) % 4; i++) 0x20,
    ]);
    final out = BytesBuilder()
      ..add(bytes.sublist(0, 8))
      ..add(
        (ByteData(
          4,
        )..setUint32(0, json.length, Endian.little)).buffer.asUint8List(),
      )
      ..add(json)
      ..add(bytes.sublist(12 + length));
    return out.toBytes();
  }

  test('reads the bundled file', () {
    final w = PlainWeights.parse(bytes);
    expect(w.model, 'ask-reader');
    expect(w.sourceSha256, hasLength(64));
    final kernel = w['conv_1.kernel'];
    expect(kernel.shape, [96, 1, 3, 32]);
    expect(kernel.int8, isNotNull);
    expect(kernel.scales, hasLength(96));
    expect(kernel.axis, 0);
    expect(w['slots.kernel'].float32, hasLength(7 * 64));
    expect(
      w['token_embedding.table'].real(),
      hasLength(readerHashBuckets * 24),
    );
    expect(() => w['nothing'], throwsFormatException);
  });

  test('refuses what does not fit the format', () {
    for (final bad in [
      changed((d) => d.setUint8(0, 0x58)), // magic
      changed((d) => d.setUint32(4, 2, Endian.little)), // version
      changed((d) => d.setUint32(8, 3, Endian.little)), // header length
      Uint8List.sublistView(bytes, 0, bytes.length - 4), // cut short
      Uint8List.fromList([...bytes, 0, 0, 0, 0]), // data after the end
      withHeader((h) => {...h, 'format_version': 2}),
    ]) {
      expect(() => PlainWeights.parse(bad), throwsFormatException);
    }
  });

  test('the Ask reader refuses weights of another network', () {
    expect(DartAskReader.parse(bytes), isA<DartAskReader>());
    expect(
      () => DartAskReader.parse(withHeader((h) => {...h, 'model': 'other'})),
      throwsFormatException,
    );
    expect(
      () => DartAskReader.parse(
        withHeader(
          (h) => {
            ...h,
            'layers': [
              for (final l
                  in (h['layers']! as List).cast<Map<String, Object?>>())
                l['name'] == 'conv_3' ? {...l, 'dilation': 2} : l,
            ],
          },
        ),
      ),
      throwsFormatException,
    );
  });
}
