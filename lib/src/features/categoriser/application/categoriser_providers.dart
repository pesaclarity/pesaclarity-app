import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../data/database/app_database.dart';
import '../../../data/repositories/categories_repository.dart';
import '../../../data/repositories/category_suggestions_repository.dart';
import '../../../domain/categoriser/learning.dart';
import '../../../domain/categoriser/rule_categoriser.dart';
import '../../../domain/categoriser/suggester.dart';
import '../../../domain/privacy/consent.dart';
import '../../privacy/application/consent_controller.dart';
import '../../privacy/data/policy_source.dart';
import '../data/model_store.dart';
import '../data/tflite_flutter_runtime.dart';

/// Opens TFLite models. Override in tests with a fake runtime.
final tfliteRuntimeOpenerProvider = Provider<TfliteRuntimeOpener>(
  (ref) =>
      (bytes, width) => TfliteFlutterRuntime.open(bytes, width: width),
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
  final loaded = await loadCategoriser(
    folder,
    openRuntime: ref.watch(tfliteRuntimeOpenerProvider),
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

/// Next step: fine-tune the TFLite model on the phone. Null until built.
final onDeviceTrainerProvider = Provider<OnDeviceTrainer?>((ref) => null);

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
