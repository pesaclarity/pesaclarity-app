import 'dart:convert';
import 'dart:typed_data';

import '../../../core/ml/model_engines.dart';
import '../../../domain/reader/message_reading.dart';
import '../../../domain/reader/model_reader.dart';
import '../../../domain/reader/rule_reader.dart';
import '../../ask/data/ask_model_store.dart' show AssetReader;
import '../../categoriser/data/model_store.dart' show sha256Hex;

/// Where the message reader ships in the app, as pesaclarity-ml exports it.
const readerModelFolder = 'assets/models/reader';

/// The reader's manifest, beside `reader.weights`.
const readerManifestFile = 'reader-manifest.json';

/// Opens `reader.weights`. Null makes the review inbox use the rules reader.
typedef ReaderRuntimeOpener = ReaderRuntime Function(Uint8List bytes);

/// The trained reader when its files are bundled and fit this app, else the
/// rules reader. With no [openRuntime], always the rules reader. Never
/// throws, except in a rayo-only build ([onlyRayo]), where a reader that
/// cannot run is a [RayoOnlyFailure] instead of the rules.
Future<MessageReader> loadReader({
  required AssetReader readAsset,
  required ReaderRuntimeOpener? openRuntime,
  bool onlyRayo = rayoOnly,
  ModelEngines? engines,
}) async {
  const fallback = RuleMessageReader();
  final log = engines ?? ModelEngines.instance;
  const model = OnPhoneModel.messageReader;
  MessageReader refuse(String reason) {
    if (log.of(model).reason != reason) {
      log.record(model, ModelEngine('Rules', reason: reason));
    }
    if (onlyRayo) throw RayoOnlyFailure(model, reason);
    return fallback;
  }

  if (openRuntime == null) return refuse('this build has no runtime');
  try {
    final manifestBytes = await readAsset(
      '$readerModelFolder/$readerManifestFile',
    );
    if (manifestBytes == null) return refuse('not bundled');
    final manifest = ReaderManifest.fromJson(
      (jsonDecode(utf8.decode(manifestBytes)) as Map).cast<String, Object?>(),
    );
    final problems = manifest.incompatibilities();
    if (problems.isNotEmpty) return refuse(problems.join('; '));
    // The manifest names a file in the same folder, never a path.
    final file = manifest.weightsFile;
    if (file.contains('/') || file.contains(r'\') || file.startsWith('.')) {
      return refuse('weights file name $file');
    }
    final bytes = await readAsset('$readerModelFolder/$file');
    if (bytes == null ||
        bytes.length != manifest.weightsSizeBytes ||
        await sha256Hex(bytes) != manifest.weightsSha256) {
      return refuse('weights missing or not the manifest\'s');
    }
    final runtime = openRuntime(bytes);
    log.version(model, weightsVersion(manifest.weightsSha256));
    return ModelMessageReader(runtime);
  } on RayoOnlyFailure {
    rethrow;
  } on Object catch (e) {
    return refuse('$e');
  }
}
