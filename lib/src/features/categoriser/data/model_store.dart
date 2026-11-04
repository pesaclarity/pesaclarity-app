import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import '../../../domain/categoriser/categoriser.dart';
import '../../../domain/categoriser/model_manifest.dart';
import '../../../domain/categoriser/rule_categoriser.dart';
import '../../../domain/categoriser/trainable.dart';

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
    this.trainable,
    this.tuned = false,
  ]);

  final Categoriser categoriser;
  final ModelStatus status;

  /// Why an installed model was refused.
  final List<String> reasons;

  /// The checked trainable copy, when the model came with one.
  final TrainableModel? trainable;

  /// Whether suggestions use weights fine-tuned on this phone.
  final bool tuned;
}

/// Loads the model in [folder]: `model-manifest.json`, `labels.json` and the
/// model file the manifest names. Falls back to [RuleCategoriser] when
/// nothing is installed or the model is refused.
///
/// A model is refused when its feature schema, config or input differ from
/// what this app produces, when its file size or SHA-256 differ from the
/// manifest, or when its labels do not match its outputs.
///
/// When the manifest lists a trainable copy that also checks out, it is
/// returned for fine-tuning. When [tuned] weights fit it, suggestions come
/// from the trainable copy with those weights restored.
Future<LoadedCategoriser> loadCategoriser(
  Directory folder, {
  required TfliteRuntimeOpener openRuntime,
  TrainableRuntimeOpener? openTrainable,
  TunedWeights? tuned,
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

  final (modelBytes, problem) = await _verifiedFile(
    folder,
    manifest.modelFile,
    manifest.modelSizeBytes,
    manifest.modelSha256,
  );
  if (problem != null) return refuse([problem]);
  if (modelBytes == null) return refuse(['model file missing']);

  final trainable = await _trainableModel(folder, manifest, labels);
  final width = manifest.featureConfig.width;
  if (trainable != null &&
      openTrainable != null &&
      tuned != null &&
      tuned.fits(trainable.manifest)) {
    try {
      final runtime = openTrainable(trainable.bytes, width);
      try {
        runtime.restore(tuned.weights);
      } on Object {
        runtime.close();
        rethrow;
      }
      // Closes the runtime itself when it refuses it.
      final categoriser = TfliteCategoriser(
        manifest: manifest,
        labels: labels,
        runtime: runtime,
      );
      return LoadedCategoriser(
        categoriser,
        ModelStatus.loaded,
        const [],
        trainable,
        true,
      );
    } on Object {
      // Fall back to the installed weights below.
    }
  }

  try {
    final categoriser = TfliteCategoriser(
      manifest: manifest,
      labels: labels,
      runtime: openRuntime(modelBytes, width),
    );
    return LoadedCategoriser(
      categoriser,
      ModelStatus.loaded,
      const [],
      trainable,
    );
  } on ModelRefused catch (e) {
    return refuse(e.reasons);
  } on Object catch (e) {
    return refuse(['the runtime could not open the model: $e']);
  }
}

/// The trainable copy when the manifest lists one and it checks out.
Future<TrainableModel?> _trainableModel(
  Directory folder,
  ModelManifest manifest,
  ModelLabels labels,
) async {
  final t = manifest.trainable;
  if (t == null || t.problems().isNotEmpty) return null;
  final (bytes, problem) = await _verifiedFile(
    folder,
    t.file,
    t.sizeBytes,
    t.sha256,
  );
  if (bytes == null || problem != null) return null;
  return TrainableModel(
    manifest: t,
    bytes: bytes,
    labels: labels.labels,
    width: manifest.featureConfig.width,
    featureSchemaVersion: manifest.featureSchemaVersion,
  );
}

/// The bytes of [name] in [folder] when its size and SHA-256 match, else
/// the problem. `(null, null)` when the file is missing.
Future<(Uint8List?, String?)> _verifiedFile(
  Directory folder,
  String name,
  int size,
  String sha256,
) async {
  // The manifest names a file in the same folder, never a path.
  if (p.basename(name) != name || name.startsWith('.')) {
    return (null, 'model file name $name');
  }
  final file = File(p.join(folder.path, name));
  if (!await file.exists()) return (null, null);
  final bytes = await file.readAsBytes();
  if (bytes.length != size) {
    return (null, 'model size ${bytes.length} != $size');
  }
  if (await sha256Hex(bytes) != sha256) {
    return (null, 'model SHA-256 does not match the manifest');
  }
  return (bytes, null);
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
