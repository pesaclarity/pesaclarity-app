import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'ask_model_catalogue.dart';

/// How far a download is, in bytes.
class AskModelProgress {
  const AskModelProgress(this.received, this.total);

  final int received;
  final int total;

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0, 1);
}

/// Why a download stopped.
class AskModelDownloadFailure implements Exception {
  const AskModelDownloadFailure(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Cancels a download between chunks.
class AskModelCancel {
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Where models live: `ask-models/` in app support storage, kept out of
/// backups. A file is only there under its own name once its SHA-256 matched
/// the signed catalogue; until then it is `<name>.part`.
class AskModelFiles {
  AskModelFiles(this.directory);

  final Directory directory;

  File file(AskModelEntry model) => File(p.join(directory.path, model.file));

  File part(AskModelEntry model) =>
      File(p.join(directory.path, '${model.file}.part'));

  /// Whether [model]'s checked file is there, at its catalogue size.
  bool has(AskModelEntry model) {
    final f = file(model);
    return f.existsSync() && f.lengthSync() == model.sizeBytes;
  }

  /// Bytes of [model] already fetched.
  int partBytes(AskModelEntry model) {
    final f = part(model);
    return f.existsSync() ? f.lengthSync() : 0;
  }

  /// Deletes every model and half-fetched file.
  Future<void> deleteAll() async {
    if (!directory.existsSync()) return;
    for (final f in directory.listSync()) {
      if (f is File) await f.delete();
    }
  }

  /// Deletes every model but [keep].
  Future<void> deleteOthers(AskModelEntry keep) async {
    if (!directory.existsSync()) return;
    for (final f in directory.listSync()) {
      if (f is File &&
          p.basename(f.path) != keep.file &&
          p.basename(f.path) != '${keep.file}.part') {
        await f.delete();
      }
    }
  }

  /// Fetches [model] over [client], carrying on from a `.part` file when
  /// there is one, then checks its size and SHA-256 and only then gives it
  /// its name. Reports each chunk to [onProgress]. Throws
  /// [AskModelDownloadFailure] when cancelled or anything does not match;
  /// a wrong file is deleted.
  Future<File> download(
    AskModelEntry model, {
    required http.Client client,
    required AskModelCancel cancel,
    void Function(AskModelProgress)? onProgress,
  }) async {
    await directory.create(recursive: true);
    final part = this.part(model);
    var have = partBytes(model);
    if (have > model.sizeBytes) {
      await part.delete();
      have = 0;
    }
    if (have < model.sizeBytes) {
      final request = http.Request('GET', Uri.parse(model.url));
      if (have > 0) request.headers['Range'] = 'bytes=$have-';
      final http.StreamedResponse response;
      try {
        response = await client.send(request);
      } on Object catch (e) {
        throw AskModelDownloadFailure('$e');
      }
      final FileMode mode;
      if (response.statusCode == 206 && have > 0) {
        mode = FileMode.append;
      } else if (response.statusCode == 200) {
        // The server sent it whole: start again.
        have = 0;
        mode = FileMode.write;
      } else {
        await response.stream.drain<void>().catchError((_) {});
        throw AskModelDownloadFailure('HTTP ${response.statusCode}');
      }
      final sink = part.openWrite(mode: mode);
      var received = have;
      onProgress?.call(AskModelProgress(received, model.sizeBytes));
      try {
        await for (final chunk in response.stream) {
          if (cancel.cancelled) break;
          received += chunk.length;
          if (received > model.sizeBytes) {
            throw const AskModelDownloadFailure('larger than expected');
          }
          sink.add(chunk);
          onProgress?.call(AskModelProgress(received, model.sizeBytes));
        }
      } on AskModelDownloadFailure {
        await sink.close();
        await part.delete();
        rethrow;
      } on Object catch (e) {
        await sink.close();
        throw AskModelDownloadFailure('$e');
      }
      await sink.close();
      if (cancel.cancelled) throw const AskModelDownloadFailure('cancelled');
    }
    if (part.lengthSync() != model.sizeBytes) {
      throw const AskModelDownloadFailure('the download was cut short');
    }
    final digest = await sha256.bind(part.openRead()).first;
    if ('$digest' != model.sha256) {
      await part.delete();
      throw const AskModelDownloadFailure('the file did not match');
    }
    return part.rename(file(model).path);
  }
}
