import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pesaclarity/src/features/ask/model/ask_model_catalogue.dart';
import 'package:pesaclarity/src/features/ask/model/ask_model_download.dart';

/// Serves [body], honouring `Range`, and records each request's range.
class _Server extends http.BaseClient {
  _Server(this.body, {this.cutAt});

  final List<int> body;

  /// Ends the first response early after this many bytes.
  int? cutAt;
  final ranges = <String?>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final range = request.headers['Range'];
    ranges.add(range);
    var from = 0;
    if (range != null) from = int.parse(range.split('=')[1].split('-')[0]);
    var bytes = body.sublist(from);
    final cut = cutAt;
    final controller = StreamController<List<int>>();
    if (cut != null) {
      cutAt = null;
      bytes = bytes.sublist(0, cut);
      controller
        ..add(bytes)
        ..addError(const SocketException('dropped'));
    } else {
      for (var i = 0; i < bytes.length; i += 1000) {
        controller.add(bytes.sublist(i, (i + 1000).clamp(0, bytes.length)));
      }
    }
    unawaited(controller.close());
    return http.StreamedResponse(controller.stream, range == null ? 200 : 206);
  }
}

void main() {
  late Directory dir;
  final body = List<int>.generate(10000, (i) => i % 251);

  AskModelEntry model({String? sha}) => AskModelEntry(
    tier: AskModelTier.light,
    file: 'light.weights',
    url: '${askModelUrlPrefix}slm-models/light.weights',
    sizeBytes: body.length,
    sha256: sha ?? '${sha256.convert(body)}',
    minRamMb: 3072,
    parameters: '135M',
    licence: 'Apache-2.0',
    credit: 'A made-up model',
  );

  setUp(() => dir = Directory.systemTemp.createTempSync('ask-models'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('fetches, checks the SHA-256 and only then names the file', () async {
    final files = AskModelFiles(dir);
    final seen = <double>[];
    await files.download(
      model(),
      client: _Server(body),
      cancel: AskModelCancel(),
      onProgress: (p) => seen.add(p.fraction),
    );
    expect(files.has(model()), isTrue);
    expect(files.part(model()).existsSync(), isFalse);
    expect(seen.last, 1);
  });

  test('carries on from where a dropped download stopped', () async {
    final files = AskModelFiles(dir);
    final server = _Server(body, cutAt: 4000);
    await expectLater(
      files.download(model(), client: server, cancel: AskModelCancel()),
      throwsA(isA<AskModelDownloadFailure>()),
    );
    expect(files.partBytes(model()), 4000);
    await files.download(model(), client: server, cancel: AskModelCancel());
    expect(server.ranges, [null, 'bytes=4000-']);
    expect(files.has(model()), isTrue);
  });

  test('a file that does not match is deleted', () async {
    final files = AskModelFiles(dir);
    await expectLater(
      files.download(
        model(sha: 'b' * 64),
        client: _Server(body),
        cancel: AskModelCancel(),
      ),
      throwsA(isA<AskModelDownloadFailure>()),
    );
    expect(files.has(model()), isFalse);
    expect(files.partBytes(model()), 0);
  });

  test('cancel stops it and keeps what was fetched', () async {
    final files = AskModelFiles(dir);
    final cancel = AskModelCancel();
    await expectLater(
      files.download(
        model(),
        client: _Server(body),
        cancel: cancel,
        onProgress: (p) {
          if (p.received >= 3000) cancel.cancel();
        },
      ),
      throwsA(isA<AskModelDownloadFailure>()),
    );
    expect(files.has(model()), isFalse);
    expect(files.partBytes(model()), greaterThan(0));
    await files.deleteAll();
    expect(files.partBytes(model()), 0);
  });
}
