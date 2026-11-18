import 'dart:convert';
import 'dart:typed_data';

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
/// throws.
Future<MessageReader> loadReader({
  required AssetReader readAsset,
  required ReaderRuntimeOpener? openRuntime,
}) async {
  const fallback = RuleMessageReader();
  if (openRuntime == null) return fallback;
  try {
    final manifestBytes = await readAsset(
      '$readerModelFolder/$readerManifestFile',
    );
    if (manifestBytes == null) return fallback;
    final manifest = ReaderManifest.fromJson(
      (jsonDecode(utf8.decode(manifestBytes)) as Map).cast<String, Object?>(),
    );
    if (manifest.incompatibilities().isNotEmpty) return fallback;
    // The manifest names a file in the same folder, never a path.
    final file = manifest.weightsFile;
    if (file.contains('/') || file.contains(r'\') || file.startsWith('.')) {
      return fallback;
    }
    final bytes = await readAsset('$readerModelFolder/$file');
    if (bytes == null ||
        bytes.length != manifest.weightsSizeBytes ||
        await sha256Hex(bytes) != manifest.weightsSha256) {
      return fallback;
    }
    return ModelMessageReader(openRuntime(bytes));
  } on Object {
    return fallback;
  }
}
