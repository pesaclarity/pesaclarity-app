import 'dart:convert';
import 'dart:typed_data';

import '../../../domain/ask/model_question_reader.dart';
import '../../../domain/ask/model_reply_writer.dart';
import '../../../domain/ask/understanding.dart';
import '../../categoriser/data/model_store.dart' show sha256Hex;

/// Where Ask's models ship in the app, as pesaclarity-ml exports them.
const askModelFolder = 'assets/models/ask';

/// The question reader's manifest, beside `ask-reader.weights`.
const askReaderManifestFile = 'ask-reader-manifest.json';

/// The reply writer's manifest, beside `ask-writer.weights`.
const askWriterManifestFile = 'ask-writer-manifest.json';

/// Opens `ask-reader.weights`. Null makes Ask always use its rules.
typedef AskReaderRuntimeOpener = AskReaderRuntime Function(Uint8List bytes);

/// Opens `ask-writer.weights` for [manifest]. Null makes Ask word every
/// reply with its templates.
typedef AskWriterRuntimeOpener = AskWriterRuntime Function(
  Uint8List bytes,
  AskWriterManifest manifest,
);

/// Reads a bundled asset, or null when it is not there.
typedef AssetReader = Future<Uint8List?> Function(String path);

/// The trained question reader when its files are bundled and fit this app,
/// else [fallback]. Never throws.
Future<QuestionReader> loadAskReader({
  required AssetReader readAsset,
  required AskReaderRuntimeOpener? openRuntime,
  required QuestionReader fallback,
}) async {
  if (openRuntime == null) return fallback;
  try {
    final manifestBytes = await readAsset(
      '$askModelFolder/$askReaderManifestFile',
    );
    if (manifestBytes == null) return fallback;
    final manifest = AskReaderManifest.fromJson(
      (jsonDecode(utf8.decode(manifestBytes)) as Map).cast<String, Object?>(),
    );
    if (manifest.incompatibilities().isNotEmpty) return fallback;
    final file = manifest.weightsFile;
    if (file.contains('/') || file.contains(r'\') || file.startsWith('.')) {
      return fallback;
    }
    final bytes = await readAsset('$askModelFolder/$file');
    if (bytes == null ||
        bytes.length != manifest.weightsSizeBytes ||
        await sha256Hex(bytes) != manifest.weightsSha256) {
      return fallback;
    }
    return ModelQuestionReader(
      openRuntime(bytes),
      manifest,
      fallback: fallback,
    );
  } on Object {
    return fallback;
  }
}

/// The trained reply writer when its files are bundled and fit this app,
/// else null, and Ask words every reply with its templates. Never throws.
Future<ModelReplyWriter?> loadAskWriter({
  required AssetReader readAsset,
  required AskWriterRuntimeOpener? openRuntime,
}) async {
  if (openRuntime == null) return null;
  try {
    final manifestBytes = await readAsset(
      '$askModelFolder/$askWriterManifestFile',
    );
    if (manifestBytes == null) return null;
    final manifest = AskWriterManifest.fromJson(
      (jsonDecode(utf8.decode(manifestBytes)) as Map).cast<String, Object?>(),
    );
    if (manifest.incompatibilities().isNotEmpty) return null;
    final file = manifest.weightsFile;
    if (file.contains('/') || file.contains(r'\') || file.startsWith('.')) {
      return null;
    }
    final bytes = await readAsset('$askModelFolder/$file');
    if (bytes == null ||
        bytes.length != manifest.weightsSizeBytes ||
        await sha256Hex(bytes) != manifest.weightsSha256) {
      return null;
    }
    return ModelReplyWriter(openRuntime(bytes, manifest), manifest);
  } on Object {
    return null;
  }
}
