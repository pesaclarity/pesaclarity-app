import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/ml/plain_weights.dart';
import 'package:pesaclarity/src/domain/reader/message_reading.dart';
import 'package:pesaclarity/src/domain/reader/model_reader.dart';
import 'package:pesaclarity/src/domain/reader/reader_tokens.dart';
import 'package:pesaclarity/src/features/review/data/rayo_reader_runtime.dart';
import 'package:pesaclarity/src/features/review/data/reader_store.dart';

/// The bundled message reader (`assets/models/reader/reader.weights`), run
/// here as in the app: on rayo, whose build hook compiles its C for the
/// host.
///
/// tool/reader_decodes.py ran the same file on the app's own rayo library
/// (the commit the app pins, as its build hook compiles it), on these very
/// inputs, and checked it against the PyTorch model it was quantised from.
/// The app's outputs must be those bit for bit on the platform they were
/// recorded on. There is no Dart reader of this network: where rayo cannot
/// load, the review inbox uses the rules reader.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Uint8List?> asset(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object {
      return null;
    }
  }

  Future<Map<String, Object?>> manifest() async => (jsonDecode(
    utf8.decode((await asset('$readerModelFolder/$readerManifestFile'))!),
  ) as Map).cast<String, Object?>();

  Future<Uint8List> weights() async =>
      (await asset('$readerModelFolder/reader.weights'))!;

  final recorded = jsonDecode(
    File('test/fixtures/reader/reader_decodes.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final readings = {
    for (final r
        in (recorded['readings']! as List).cast<Map<String, Object?>>())
      r['message'] as String: r.cast<String, Object?>(),
  };
  final messages = [..._vectorMessages(), ..._messages];
  final missing = <String>[];
  tearDownAll(() => _saveMissing(missing));

  test(
    'the manifest is of the bundled weights, and this app reads it',
    () async {
      final json = await manifest();
      final bytes = await weights();
      final m = ReaderManifest.fromJson(json);
      expect(m.incompatibilities(), isEmpty);
      expect(m.weightsFile, 'reader.weights');
      expect(bytes.length, m.weightsSizeBytes);
      expect(sha256.convert(bytes).toString(), m.weightsSha256);
      expect(recorded['weights_sha256'], m.weightsSha256);
      final plain = PlainWeights.parse(bytes);
      expect(plain.sourceSha256, (json['source']! as Map)['sha256']);
      expect(json['trained_on'], 'synthetic messages only');
    },
  );

  test('the app opens the reader on rayo', () async {
    final reader = await loadReader(
      readAsset: asset,
      openRuntime: openMessageReader,
    );
    addTearDown(reader.close);
    expect(reader, isA<ModelMessageReader>());
  });

  // rayo gives the same floats on every kernel and thread count, and from
  // any compiler and flags (it is built with -ffp-contract=off). Another
  // platform's C library may round exp or tanh differently in the last bit,
  // so there only nearly.
  final exact = recorded['abi'] == Abi.current().toString();
  test(
    exact
        ? 'rayo gives the recorded outputs bit for bit'
        : 'rayo gives the recorded outputs within $_otherPlatforms',
    () async {
      final model = RayoMessageReader.open(await weights());
      addTearDown(model.close);
      void check(List<double> got, List<double> want, String what) {
        if (exact) {
          expect(got, want, reason: what);
        } else {
          expect(_argmax(got), _argmax(want), reason: what);
          for (final (i, w) in want.indexed) {
            expect(got[i], closeTo(w, _otherPlatforms), reason: what);
          }
        }
      }

      for (final message in messages) {
        final input = encodeTokens(tokenise(message));
        final r = readings[message];
        if (r == null || !_same((r['input']! as List).cast<int>(), input)) {
          missing.add(message);
          continue;
        }
        final (fields, kind) = model.run(input);
        check(kind, _float32s(r['kind']!), 'kind of "$message"');
        final want = (r['fields']! as List).map(_float32s).toList();
        final count = tokenise(message).take(readerMaxTokens).length;
        expect(want, hasLength(count));
        for (final (t, row) in want.indexed) {
          check(fields[t], row, 'fields of token $t of "$message"');
        }
      }
      expect(
        missing,
        isEmpty,
        reason: 'no rayo recording: run tool/reader_decodes.py',
      );
    },
  );

  test('a run leaves nothing behind for the next', () async {
    final model = RayoMessageReader.open(await weights());
    addTearDown(model.close);
    final a = encodeTokens(tokenise(messages.first));
    final b = encodeTokens(tokenise(messages.last));
    final (fields, kind) = model.run(a);
    model.run(b);
    final (again, kindAgain) = model.run(a);
    expect(again, fields);
    expect(kindAgain, kind);
  });

  test('off the UI thread, the readings are the same', () async {
    final reader = await loadReader(
      readAsset: asset,
      openRuntime: openMessageReader,
    ) as ModelMessageReader;
    addTearDown(reader.close);
    final there = await readMessages(reader, messages);
    for (final (i, message) in messages.indexed) {
      final here = reader.read(message);
      expect(there[i].kind, here.kind, reason: message);
      expect(there[i].kindConfidence, here.kindConfidence, reason: message);
      expect(
        {for (final f in there[i].fields.values) f.field: f.text},
        {for (final f in here.fields.values) f.field: f.text},
        reason: message,
      );
    }
  });

  test('refuses weights of another model', () async {
    final ask = (await asset('assets/models/ask/ask-reader.weights'))!;
    expect(() => RayoMessageReader.open(ask), throwsStateError);
  });

  group('reads the fields', () {
    late MessageReader reader;
    setUpAll(() async {
      reader = await loadReader(
        readAsset: asset,
        openRuntime: openMessageReader,
      );
    });
    tearDownAll(() => reader.close());

    for (final (message, kind, amount, payee, date) in _readings) {
      test(message, () {
        final r = reader.read(message);
        expect(r.kind, kind, reason: 'kind');
        expect(r.fields[ReaderField.amount]?.text, amount, reason: 'amount');
        expect(
          r.fields[ReaderField.counterparty]?.text,
          payee,
          reason: 'payee',
        );
        expect(r.fields[ReaderField.date]?.text, date, reason: 'date');
      });
    }
  });
}

/// The messages of pesaclarity-ml's reader vectors, synthetic.
List<String> _vectorMessages() {
  final vectors = jsonDecode(
    File('test/fixtures/reader/reader_vectors.v1.json').readAsStringSync(),
  ) as Map<String, Object?>;
  return [
    for (final c in (vectors['cases']! as List).cast<Map<String, Object?>>())
      c['message']! as String,
  ];
}

/// Synthetic messages in wordings no parser rule reads: invented
/// institutions, people, numbers and references.
const _messages = [
  'Dear Customer, KES 1,250.00 has been paid to EXAMPLE GROCERS on 29/10/26 '
      'at 14:05. Ref QW12ER34TY.',
  'Dear Customer, KES 80.00 has been paid to SUNRISE BAKERY on 30/10/26 '
      'at 09:12. Ref ZX98CV76BN.',
  'Your verification code is 482913. Do not share it.',
  'Sample Bank: You have received KES 3,000.00 from JANE WANJIKU on '
      '02/11/26 at 18:40. New balance KES 12,345.60. Ref RT55YU66IO.',
  'Imaginary Sacco: Withdrawal of KES 500.00 on 05-11-26 10:00. Charge '
      'KES 30.00. Avl bal KES 4,470.00.',
  'Paid USD 25.00 to DEMO STREAMING on 07/11/26. Ref AB12CD34.',
  'Habari! Pata ofa ya data leo. Tuma OFA kwa 456.',
];

/// (message, kind, amount, payee, date) as the bundled reader reads them.
const _readings = [
  (
    'Dear Customer, KES 1,250.00 has been paid to EXAMPLE GROCERS on '
        '29/10/26 at 14:05. Ref QW12ER34TY.',
    MessageKind.moneyOut,
    'KES 1,250.00',
    'EXAMPLE GROCERS',
    '29/10/26',
  ),
  (
    'Your verification code is 482913. Do not share it.',
    MessageKind.notTransaction,
    null,
    null,
    null,
  ),
];

/// How far rayo's outputs may be from the recordings on a platform other
/// than the one they were recorded on.
const _otherPlatforms = 1e-5;

int _argmax(List<double> v) {
  var best = 0;
  for (var i = 1; i < v.length; i++) {
    if (v[i] > v[best]) best = i;
  }
  return best;
}

List<double> _float32s(Object? values) => Float32List.fromList([
  for (final v in values! as List) (v! as num).toDouble(),
]);

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// With `READER_RECORD=path`, writes the messages with no recording for
/// tool/reader_decodes.py.
void _saveMissing(List<String> messages) {
  final path = Platform.environment['READER_RECORD'];
  if (path == null) return;
  File(path).writeAsStringSync(
    jsonEncode([
      for (final message in messages.toSet())
        {
          'message': message,
          'input': encodeTokens(tokenise(message)),
          'tokens': tokenise(message).take(readerMaxTokens).length,
        },
    ]),
  );
}
