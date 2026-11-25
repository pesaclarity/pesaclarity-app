import 'dart:convert';
import 'dart:typed_data';

import '../../../core/ml/model_engines.dart';
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
  bool onlyRayo = rayoOnly,
  ModelEngines? engines,
}) async {
  final log = engines ?? ModelEngines.instance;
  const model = OnPhoneModel.askReader;
  QuestionReader refuse(String reason) {
    log.record(model, ModelEngine('Rules', reason: reason));
    if (onlyRayo) throw RayoOnlyFailure(model, reason);
    return fallback;
  }

  if (openRuntime == null) return refuse('this build has no runtime');
  try {
    final manifestBytes = await readAsset(
      '$askModelFolder/$askReaderManifestFile',
    );
    if (manifestBytes == null) return refuse('not bundled');
    final manifest = AskReaderManifest.fromJson(
      (jsonDecode(utf8.decode(manifestBytes)) as Map).cast<String, Object?>(),
    );
    final problems = manifest.incompatibilities();
    if (problems.isNotEmpty) return refuse(problems.join('; '));
    final file = manifest.weightsFile;
    if (file.contains('/') || file.contains(r'\') || file.startsWith('.')) {
      return refuse('weights file name $file');
    }
    final bytes = await readAsset('$askModelFolder/$file');
    if (bytes == null ||
        bytes.length != manifest.weightsSizeBytes ||
        await sha256Hex(bytes) != manifest.weightsSha256) {
      return refuse('weights missing or not the manifest\'s');
    }
    final runtime = openRuntime(bytes);
    log.version(model, weightsVersion(manifest.weightsSha256));
    return ModelQuestionReader(runtime, manifest, fallback: fallback);
  } on RayoOnlyFailure {
    rethrow;
  } on Object catch (e) {
    return refuse('$e');
  }
}

/// The trained reply writer when its files are bundled and fit this app,
/// else null, and Ask words every reply with its templates. Never throws.
Future<ModelReplyWriter?> loadAskWriter({
  required AssetReader readAsset,
  required AskWriterRuntimeOpener? openRuntime,
  bool onlyRayo = rayoOnly,
  ModelEngines? engines,
}) async {
  final log = engines ?? ModelEngines.instance;
  const model = OnPhoneModel.askWriter;
  ModelReplyWriter? refuse(String reason) {
    log.record(model, ModelEngine(ModelEngine.templates, reason: reason));
    if (onlyRayo) throw RayoOnlyFailure(model, reason);
    return null;
  }

  if (openRuntime == null) return refuse('this build has no runtime');
  try {
    final manifestBytes = await readAsset(
      '$askModelFolder/$askWriterManifestFile',
    );
    if (manifestBytes == null) return refuse('not bundled');
    final manifest = AskWriterManifest.fromJson(
      (jsonDecode(utf8.decode(manifestBytes)) as Map).cast<String, Object?>(),
    );
    final problems = manifest.incompatibilities();
    if (problems.isNotEmpty) return refuse(problems.join('; '));
    final file = manifest.weightsFile;
    if (file.contains('/') || file.contains(r'\') || file.startsWith('.')) {
      return refuse('weights file name $file');
    }
    final bytes = await readAsset('$askModelFolder/$file');
    if (bytes == null ||
        bytes.length != manifest.weightsSizeBytes ||
        await sha256Hex(bytes) != manifest.weightsSha256) {
      return refuse('weights missing or not the manifest\'s');
    }
    final runtime = openRuntime(bytes, manifest);
    log.version(model, weightsVersion(manifest.weightsSha256));
    return ModelReplyWriter(runtime, manifest);
  } on RayoOnlyFailure {
    rethrow;
  } on Object catch (e) {
    return refuse('$e');
  }
}
