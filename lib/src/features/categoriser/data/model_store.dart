import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../domain/categoriser/categoriser.dart';
import '../../../domain/categoriser/features.dart';
import '../../../domain/categoriser/model_manifest.dart';
import '../../../domain/categoriser/rule_categoriser.dart';
import '../../../domain/categoriser/trainable.dart';
import '../../ask/data/ask_model_store.dart' show AssetReader;

/// Where the categoriser ships in the app, as pesaclarity-ml exports it.
const categoriserModelFolder = 'assets/models/categoriser';

/// File names in the model folder, as pesaclarity-ml exports them.
const modelManifestFile = 'model-manifest.json';
const modelLabelsFile = 'labels.json';

/// Opens `categoriser.weights` for rows of [config].
typedef CategoriserRuntimeOpener = CategoriserRuntime Function(
  Uint8List weights,
  FeatureConfig config,
);

/// Whether a model was installed and used.
enum ModelStatus { notInstalled, loaded, refused }

/// The categoriser to use and why.
class LoadedCategoriser {
  const LoadedCategoriser(
    this.categoriser,
    this.status, [
    this.reasons = const [],
    this.fineTunable,
    this.tuned = false,
  ]);

  final Categoriser categoriser;
  final ModelStatus status;

  /// Why an installed model was refused.
  final List<String> reasons;

  /// The model as fine-tuning needs it, when its manifest's `fine_tune`
  /// block is one this app implements and fits the weights.
  final FineTunableModel? fineTunable;

  /// Whether suggestions use weights fine-tuned on this phone.
  final bool tuned;
}

/// Loads the categoriser in [folder] through [readAsset]:
/// `model-manifest.json`, `labels.json` and the weights file the manifest
/// names. Falls back to [RuleCategoriser] when nothing is there or the
/// model is refused. Never throws.
///
/// A model is refused when its weights format, feature schema, config or
/// input differ from what this app reads and produces, when its weights'
/// size or SHA-256 differ from the manifest, or when its labels do not
/// match its outputs. With no [openRuntime] an installed model that checks
/// out is still refused: the build cannot run it.
///
/// When the manifest's `fine_tune` block is one this app implements and its
/// shapes are the weights file's, the model is returned for fine-tuning.
/// When [tuned] weights fit it, suggestions run in Dart with those weights
/// in place of the shipped ones.
Future<LoadedCategoriser> loadCategoriser({
  required AssetReader readAsset,
  required CategoriserRuntimeOpener? openRuntime,
  String folder = categoriserModelFolder,
  TunedWeights? tuned,
}) async {
  const fallback = RuleCategoriser();
  LoadedCategoriser refuse(List<String> reasons) =>
      LoadedCategoriser(fallback, ModelStatus.refused, reasons);

  final ModelManifest manifest;
  final ModelLabels labels;
  try {
    final manifestBytes = await readAsset('$folder/$modelManifestFile');
    if (manifestBytes == null) {
      return const LoadedCategoriser(fallback, ModelStatus.notInstalled);
    }
    manifest = ModelManifest.fromJson(_json(manifestBytes));
    final labelBytes = await readAsset('$folder/$modelLabelsFile');
    if (labelBytes == null) return refuse(['no $modelLabelsFile']);
    labels = ModelLabels.fromJson(_json(labelBytes));
  } on Object catch (e) {
    return refuse(['unreadable manifest or labels: $e']);
  }

  final problems = manifest.incompatibilities();
  if (problems.isNotEmpty) return refuse(problems);

  // The manifest names a file in the same folder, never a path.
  final name = manifest.weightsFile;
  if (name.contains('/') || name.contains(r'\') || name.startsWith('.')) {
    return refuse(['weights file name $name']);
  }
  final Uint8List? weights;
  try {
    weights = await readAsset('$folder/$name');
  } on Object catch (e) {
    return refuse(['unreadable weights: $e']);
  }
  if (weights == null) return refuse(['weights file missing']);
  if (weights.length != manifest.weightsSizeBytes) {
    return refuse([
      'weights size ${weights.length} != ${manifest.weightsSizeBytes}',
    ]);
  }
  if (await sha256Hex(weights) != manifest.weightsSha256) {
    return refuse(['weights SHA-256 does not match the manifest']);
  }

  if (openRuntime == null) {
    return refuse(['this build has no runtime for the model']);
  }
  final fineTunable = _fineTunable(weights, manifest, labels);
  final tunedWeights = fineTunable == null ? null : tuned?.fitting(fineTunable);
  if (fineTunable != null && tunedWeights != null) {
    try {
      // Refuses, and closes, a runtime whose outputs are not the labels'.
      final categoriser = ModelCategoriser(
        manifest: manifest,
        labels: labels,
        runtime: DartCategoriserRuntime(fineTunable.network, tunedWeights),
      );
      return LoadedCategoriser(
        categoriser,
        ModelStatus.loaded,
        const [],
        fineTunable,
        true,
      );
    } on Object {
      // Suggest with the installed weights below.
    }
  }

  try {
    final categoriser = ModelCategoriser(
      manifest: manifest,
      labels: labels,
      runtime: openRuntime(weights, manifest.featureConfig),
    );
    return LoadedCategoriser(
      categoriser,
      ModelStatus.loaded,
      const [],
      fineTunable,
    );
  } on ModelRefused catch (e) {
    return refuse(e.reasons);
  } on Object catch (e) {
    return refuse(['the runtime could not open the model: $e']);
  }
}

/// The model for fine-tuning when its `fine_tune` block is one this app
/// implements, with the shapes of the network in [weights].
FineTunableModel? _fineTunable(
  Uint8List weights,
  ModelManifest manifest,
  ModelLabels labels,
) {
  final tune = manifest.fineTune;
  if (tune == null || tune.problems().isNotEmpty) return null;
  final CategoriserNetwork network;
  try {
    network = CategoriserNetwork.parse(weights, manifest.featureConfig);
  } on FormatException {
    return null;
  }
  final shapes = network.shipped.shapes;
  for (final MapEntry(:key, :value) in shapes.entries) {
    final want = tune.weightShapes[key];
    if (want == null || want.join(',') != value.join(',')) return null;
  }
  if (network.shipped.classes != labels.labels.length) return null;
  return FineTunableModel(
    manifest: tune,
    weightsSha256: manifest.weightsSha256,
    network: network,
    labels: labels.labels,
    featureSchemaVersion: manifest.featureSchemaVersion,
  );
}

/// Lower-case hex SHA-256 of [bytes].
Future<String> sha256Hex(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return [for (final b in hash.bytes) b.toRadixString(16).padLeft(2, '0')]
      .join();
}

Map<String, Object?> _json(Uint8List bytes) {
  final json = jsonDecode(utf8.decode(bytes));
  if (json is! Map<String, Object?>) {
    throw const FormatException('not a JSON object');
  }
  return json;
}
