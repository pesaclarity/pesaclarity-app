import 'dart:typed_data';

/// One confirmed transaction as a training example.
class TrainingExample {
  const TrainingExample({
    required this.features,
    required this.label,
    required this.featureSchemaVersion,
  });

  /// The encoded model input (see `encodeFeatures`); never the payee text.
  final List<int> features;

  /// The category key the person chose, such as `groceries`.
  final String label;
  final int featureSchemaVersion;
}

/// Fine-tunes the installed model on the person's confirmations, on the
/// phone. Nothing leaves the phone.
abstract interface class OnDeviceTrainer {
  Future<void> fineTune(List<TrainingExample> examples);
}

/// A clipped, noised weight delta for federated averaging.
class ModelUpdate {
  const ModelUpdate({required this.payload, required this.exampleCount});

  final Uint8List payload;
  final int exampleCount;
}

/// Computes a federated update from local examples (DP-FedAvg, matching
/// `federated` in pesaclarity-ml's configs).
abstract interface class FederatedUpdateTrainer {
  Future<ModelUpdate> computeUpdate(List<TrainingExample> examples);
}

/// Sends an update to the aggregator.
abstract interface class ModelUpdateUploader {
  Future<void> upload(ModelUpdate update);
}

/// How a learning run ended.
enum LearningOutcome {
  /// The person has not opted in to Improve the app; nothing was read,
  /// trained or sent.
  notOptedIn,

  /// No trainer is available in this build.
  unavailable,

  /// Opted in, but there are no confirmations to learn from yet.
  noExamples,

  /// The model was fine-tuned on the phone; nothing was sent.
  fineTuned,

  /// Fine-tuned (when a trainer exists) and a federated update was sent.
  uploaded,
}

/// Runs on-device fine-tuning and federated updates, only when the person
/// has opted in. Consent is checked before reading any examples and again
/// right before sending, so switching it off mid-run stops the upload.
class CategoriserLearning {
  CategoriserLearning({
    required this.optedIn,
    required this.examples,
    this.trainer,
    this.federated,
    this.uploader,
  });

  /// Reads the Improve the app consent at the moment of asking.
  final bool Function() optedIn;
  final Future<List<TrainingExample>> Function() examples;
  final OnDeviceTrainer? trainer;
  final FederatedUpdateTrainer? federated;
  final ModelUpdateUploader? uploader;

  Future<LearningOutcome> run() async {
    if (!optedIn()) return LearningOutcome.notOptedIn;
    final canUpload = federated != null && uploader != null;
    if (trainer == null && !canUpload) return LearningOutcome.unavailable;

    final batch = await examples();
    if (batch.isEmpty) return LearningOutcome.noExamples;
    if (!optedIn()) return LearningOutcome.notOptedIn;

    await trainer?.fineTune(batch);
    if (!canUpload) return LearningOutcome.fineTuned;

    final update = await federated!.computeUpdate(batch);
    if (!optedIn()) return LearningOutcome.notOptedIn;
    await uploader!.upload(update);
    return LearningOutcome.uploaded;
  }
}
