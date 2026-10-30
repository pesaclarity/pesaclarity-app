import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../domain/reader/message_reading.dart';
import '../../../domain/reader/model_reader.dart';
import '../../../domain/reader/rule_reader.dart';
import '../../categoriser/data/model_store.dart' show sha256Hex;

const readerManifestFile = 'reader-manifest.json';

/// Name of the reader's folder under the app's support directory.
const readerFolderName = 'reader';

typedef ReaderRuntimeOpener = ReaderRuntime Function(Uint8List modelBytes);

/// The trained reader in [folder] when it is installed and fits this app,
/// else the rules reader. Never throws.
Future<MessageReader> loadReader(
  Directory folder, {
  required ReaderRuntimeOpener openRuntime,
}) async {
  const fallback = RuleMessageReader();
  try {
    final manifestFile = File(p.join(folder.path, readerManifestFile));
    if (!await manifestFile.exists()) return fallback;
    final manifest = ReaderManifest.fromJson(
      jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>,
    );
    if (manifest.incompatibilities().isNotEmpty) return fallback;
    // The manifest names a file in the same folder, never a path.
    if (p.basename(manifest.modelFile) != manifest.modelFile ||
        manifest.modelFile.startsWith('.')) {
      return fallback;
    }
    final bytes = await File(p.join(folder.path, manifest.modelFile))
        .readAsBytes();
    if (bytes.length != manifest.modelSizeBytes ||
        await sha256Hex(bytes) != manifest.modelSha256) {
      return fallback;
    }
    return ModelMessageReader(openRuntime(bytes));
  } on Object {
    return fallback;
  }
}
