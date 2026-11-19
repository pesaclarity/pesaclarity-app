import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/categories_repository.dart';
import '../../../data/repositories/category_suggestions_repository.dart';
import '../../../domain/categoriser/learning.dart';
import '../../../domain/categoriser/suggester.dart';
import '../../../domain/categoriser/trainable.dart';
import '../../../domain/privacy/consent.dart';
import '../../ask/data/ask_model_store.dart' show AssetReader;
import '../../privacy/application/consent_controller.dart';
import '../../privacy/data/policy_source.dart';
import '../data/charging.dart';
import '../data/model_store.dart';
import '../data/rayo_categoriser_runtime.dart';
import '../data/tuned_weights_store.dart';

/// Opens `categoriser.weights` on rayo, or in Dart where rayo cannot load,
/// the same in every build. Override with null to use the rules only, or
/// with a fake in tests.
final categoriserRuntimeOpenerProvider = Provider<CategoriserRuntimeOpener?>(
  (ref) => openCategoriserRuntime,
);

/// Reads the bundled categoriser files; null when absent.
final categoriserAssetReaderProvider = Provider<AssetReader>(
  (ref) => (path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object {
      return null;
    }
  },
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

/// The installed model when it can be used, else the rules fallback.
final loadedCategoriserProvider = FutureProvider<LoadedCategoriser>((
  ref,
) async {
  TunedWeights? tuned;
  try {
    tuned = await ref.watch(tunedWeightsProvider.future);
  } on Object {
    tuned = null;
  }
  final loaded = await loadCategoriser(
    readAsset: ref.watch(categoriserAssetReaderProvider),
    openRuntime: ref.watch(categoriserRuntimeOpenerProvider),
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
/// while it loads, and when its manifest has no `fine_tune` block this app
/// implements.
final onDeviceTrainerProvider = Provider<OnDeviceTrainer?>((ref) {
  final model = ref.watch(loadedCategoriserProvider).value?.fineTunable;
  if (model == null) return null;
  return ModelFineTuner(
    model: model,
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
/// manifest allows. Null when the installed model cannot be fine-tuned.
final learningScheduleProvider = FutureProvider<LearningSchedule?>((ref) async {
  final loaded = await ref.watch(loadedCategoriserProvider.future);
  final model = loaded.fineTunable;
  if (model == null) return null;
  return LearningSchedule(
    learning: ref.watch(categoriserLearningProvider),
    optedIn: () => ref.read(improveAppOptInProvider),
    isCharging: ref.watch(isChargingProvider),
    store: ref.watch(tunedWeightsStoreProvider),
    interval: Duration(hours: model.manifest.settings.minHoursBetweenRuns),
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
