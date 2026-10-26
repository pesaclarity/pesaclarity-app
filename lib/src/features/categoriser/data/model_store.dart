import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import '../../../domain/categoriser/categoriser.dart';
import '../../../domain/categoriser/model_manifest.dart';
import '../../../domain/categoriser/rule_categoriser.dart';

/// File names in the model folder, as pesaclarity-ml exports them.
const modelManifestFile = 'model-manifest.json';
const modelLabelsFile = 'labels.json';

/// Name of the model folder under the app's support directory.
const modelFolderName = 'categoriser';

/// Opens a TFLite model from its bytes, for rows [width] long.
typedef TfliteRuntimeOpener = TfliteRuntime Function(
  Uint8List modelBytes,
  int width,
);

/// Whether a model was installed and used.
enum ModelStatus { notInstalled, loaded, refused }

/// The categoriser to use and why.
class LoadedCategoriser {
  const LoadedCategoriser(
    this.categoriser,
    this.status, [
    this.reasons = const [],
  ]);

  final Categoriser categoriser;
  final ModelStatus status;

  /// Why an installed model was refused.
  final List<String> reasons;
}

/// Loads the model in [folder]: `model-manifest.json`, `labels.json` and the
/// model file the manifest names. Falls back to [RuleCategoriser] when
/// nothing is installed or the model is refused.
///
/// A model is refused when its feature schema, config or input differ from
/// what this app produces, when its file size or SHA-256 differ from the
/// manifest, or when its labels do not match its outputs.
Future<LoadedCategoriser> loadCategoriser(
  Directory folder, {
  required TfliteRuntimeOpener openRuntime,
}) async {
  const fallback = RuleCategoriser();
  final manifestFile = File(p.join(folder.path, modelManifestFile));
  if (!await manifestFile.exists()) {
    return const LoadedCategoriser(fallback, ModelStatus.notInstalled);
  }
  LoadedCategoriser refuse(List<String> reasons) =>
      LoadedCategoriser(fallback, ModelStatus.refused, reasons);

  final ModelManifest manifest;
  final ModelLabels labels;
  try {
    manifest = ModelManifest.fromJson(await _readJson(manifestFile));
    labels = ModelLabels.fromJson(
      await _readJson(File(p.join(folder.path, modelLabelsFile))),
    );
  } on Exception catch (e) {
    return refuse(['unreadable manifest or labels: $e']);
  }

  final problems = manifest.incompatibilities();
  if (problems.isNotEmpty) return refuse(problems);

  // The manifest names a file in the same folder, never a path.
  if (p.basename(manifest.modelFile) != manifest.modelFile ||
      manifest.modelFile.startsWith('.')) {
    return refuse(['model file name ${manifest.modelFile}']);
  }
  final modelFile = File(p.join(folder.path, manifest.modelFile));
  if (!await modelFile.exists()) return refuse(['model file missing']);
  final bytes = await modelFile.readAsBytes();
  if (bytes.length != manifest.modelSizeBytes) {
    return refuse(['model size ${bytes.length} != ${manifest.modelSizeBytes}']);
  }
  if (await sha256Hex(bytes) != manifest.modelSha256) {
    return refuse(['model SHA-256 does not match the manifest']);
  }

  try {
    final categoriser = TfliteCategoriser(
      manifest: manifest,
      labels: labels,
      runtime: openRuntime(bytes, manifest.featureConfig.width),
    );
    return LoadedCategoriser(categoriser, ModelStatus.loaded);
  } on ModelRefused catch (e) {
    return refuse(e.reasons);
  } on Object catch (e) {
    return refuse(['the runtime could not open the model: $e']);
  }
}

/// Lower-case hex SHA-256 of [bytes].
Future<String> sha256Hex(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return [for (final b in hash.bytes) b.toRadixString(16).padLeft(2, '0')]
      .join();
}

Future<Map<String, Object?>> _readJson(File file) async {
  final json = jsonDecode(await file.readAsString());
  if (json is! Map<String, Object?>) {
    throw FormatException('${p.basename(file.path)} is not an object');
  }
  return json;
}
