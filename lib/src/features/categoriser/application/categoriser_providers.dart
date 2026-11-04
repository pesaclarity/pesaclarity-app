import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/categories_repository.dart';
import '../../../data/repositories/category_suggestions_repository.dart';
import '../../../domain/categoriser/learning.dart';
import '../../../domain/categoriser/rule_categoriser.dart';
import '../../../domain/categoriser/suggester.dart';
import '../../../domain/categoriser/trainable.dart';
import '../../../domain/privacy/consent.dart';
import '../../privacy/application/consent_controller.dart';
import '../../privacy/data/policy_source.dart';
import '../data/charging.dart';
import '../data/model_store.dart';
import '../data/tflite_flutter_runtime.dart';
import '../data/tuned_weights_store.dart';

/// Opens TFLite models. Override in tests with a fake runtime.
final tfliteRuntimeOpenerProvider = Provider<TfliteRuntimeOpener>(
  (ref) =>
      (bytes, width) => TfliteFlutterRuntime.open(bytes, width: width),
);

/// Opens trainable TFLite models. Override in tests with a fake runtime.
final trainableRuntimeOpenerProvider = Provider<TrainableRuntimeOpener>(
  (ref) =>
      (bytes, width) => TfliteTrainableRuntime.open(bytes, width: width),
);

/// Weights fine-tuned on this phone, kept with the open space.
final tunedWeightsStoreProvider = Provider<TunedWeightsStore>(
  (ref) => SettingsTunedWeightsStore(ref.watch(appSettingsRepositoryProvider)),
);

/// The open space's tuned weights; null when it has none yet.
final tunedWeightsProvider = FutureProvider<TunedWeights?>(
  (ref) => ref.watch(tunedWeightsStoreProvider).read(),
);

/// Whether the phone is charging. Override in tests.
final isChargingProvider = Provider<Future<bool> Function()>(
  (ref) => const PlatformChargingSource().isCharging,
);

/// The folder an installed model is read from, in app storage. No model
/// ships with the app: one arrives only after passing pesaclarity-ml's
/// privacy release gate.
final modelFolderProvider = FutureProvider<Directory>(
  (ref) async => Directory(
    p.join((await getApplicationSupportDirectory()).path, modelFolderName),
  ),
);

/// The installed model when it can be used, else the rules fallback.
final loadedCategoriserProvider = FutureProvider<LoadedCategoriser>((
  ref,
) async {
  final Directory folder;
  try {
    folder = await ref.watch(modelFolderProvider.future);
  } on Object {
    return const LoadedCategoriser(RuleCategoriser(), ModelStatus.notInstalled);
  }
  TunedWeights? tuned;
  try {
    tuned = await ref.watch(tunedWeightsProvider.future);
  } on Object {
    tuned = null;
  }
  final loaded = await loadCategoriser(
    folder,
    openRuntime: ref.watch(tfliteRuntimeOpenerProvider),
    openTrainable: ref.watch(trainableRuntimeOpenerProvider),
    tuned: tuned,
  );
  ref.onDispose(loaded.categoriser.close);
  return loaded;
});

/// The person's categories, by name.
final categoryListProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoriesRepositoryProvider).watchAll(),
);

final _correctionsProvider = StreamProvider<Map<String, int>>(
  (ref) => ref.watch(categorySuggestionsRepositoryProvider).watchCorrections(),
);

/// Suggests categories for uncategorised transactions; null while loading.
final categorySuggesterProvider = Provider<CategorySuggester?>((ref) {
  final loaded = ref.watch(loadedCategoriserProvider).value;
  final categories = ref.watch(categoryListProvider).value;
  final corrections = ref.watch(_correctionsProvider).value;
  if (loaded == null || categories == null || corrections == null) {
    return null;
  }
  return CategorySuggester(
    categoriser: loaded.categoriser,
    categories: [
      for (final c in categories)
        CategoryOption(id: c.id, key: c.key, type: c.type),
    ],
    corrections: corrections,
  );
});

/// Whether the person allows "Help improve the app" under the current
/// policy. Off until the consent record and policy have loaded, and while a
/// newer policy waits for review.
final improveAppOptInProvider = Provider<bool>((ref) {
  final record = ref.watch(consentControllerProvider).value;
  final policy = ref.watch(privacyPolicyProvider).value;
  if (record == null || policy == null) return false;
  return record.allows(ConsentKind.improveApp, policy);
});

/// Fine-tunes the installed model on the open space's confirmations. Null
/// until a model with a trainable copy is installed.
final onDeviceTrainerProvider = Provider<OnDeviceTrainer?>((ref) {
  final trainable = ref.watch(loadedCategoriserProvider).value?.trainable;
  if (trainable == null) return null;
  return ModelFineTuner(
    model: trainable,
    open: ref.watch(trainableRuntimeOpenerProvider),
    store: ref.watch(tunedWeightsStoreProvider),
    now: ref.watch(clockProvider),
  );
});

/// Next step: compute DP-FedAvg updates. Null until built.
final federatedUpdateTrainerProvider = Provider<FederatedUpdateTrainer?>(
  (ref) => null,
);

/// Next step: send updates to the aggregator in pesaclarity-backend. Null
/// until that service exists.
final modelUpdateUploaderProvider = Provider<ModelUpdateUploader?>(
  (ref) => null,
);

/// Learning from confirmations, gated on [improveAppOptInProvider].
final categoriserLearningProvider = Provider<CategoriserLearning>(
  (ref) => CategoriserLearning(
    optedIn: () => ref.read(improveAppOptInProvider),
    examples: () =>
        ref.read(categorySuggestionsRepositoryProvider).trainingExamples(),
    trainer: ref.watch(onDeviceTrainerProvider),
    federated: ref.watch(federatedUpdateTrainerProvider),
    uploader: ref.watch(modelUpdateUploaderProvider),
  ),
);

/// When to learn: with consent, while charging, and no more often than the
/// manifest allows. Null until a model with a trainable copy is installed.
final learningScheduleProvider = FutureProvider<LearningSchedule?>((ref) async {
  final loaded = await ref.watch(loadedCategoriserProvider.future);
  final trainable = loaded.trainable;
  if (trainable == null) return null;
  return LearningSchedule(
    learning: ref.watch(categoriserLearningProvider),
    optedIn: () => ref.read(improveAppOptInProvider),
    isCharging: ref.watch(isChargingProvider),
    store: ref.watch(tunedWeightsStoreProvider),
    interval: Duration(hours: trainable.manifest.fineTune.minHoursBetweenRuns),
    now: ref.watch(clockProvider),
  );
});

/// Runs learning if it is due, then reloads suggestions when new weights
/// were saved. Safe to call often.
Future<LearningOutcome?> runLearningIfDue(WidgetRef ref) async {
  final schedule = await ref.read(learningScheduleProvider.future);
  final outcome = await schedule?.maybeRun();
  if (outcome == LearningOutcome.fineTuned ||
      outcome == LearningOutcome.uploaded) {
    ref.invalidate(tunedWeightsProvider);
  }
  return outcome;
}
