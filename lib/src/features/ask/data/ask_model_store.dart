import 'dart:convert';
import 'dart:typed_data';

import '../../../domain/ask/model_question_reader.dart';
import '../../../domain/ask/understanding.dart';
import '../../categoriser/data/model_store.dart' show sha256Hex;

/// Where Ask's models ship in the app, once pesaclarity-ml publishes them.
const askModelFolder = 'assets/models/ask';

/// The question reader's manifest, beside `ask-reader.tflite`.
const askReaderManifestFile = 'ask-reader-manifest.json';

/// Opens `ask-reader.tflite`. Builds without a TFLite runtime, such as
/// F-Droid's, pass null and always use the rules.
typedef AskReaderRuntimeOpener = AskReaderRuntime Function(Uint8List bytes);

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
    final file = manifest.modelFile;
    if (file.contains('/') || file.contains(r'\') || file.startsWith('.')) {
      return fallback;
    }
    final bytes = await readAsset('$askModelFolder/$file');
    if (bytes == null ||
        bytes.length != manifest.modelSizeBytes ||
        await sha256Hex(bytes) != manifest.modelSha256) {
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
