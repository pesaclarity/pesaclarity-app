import 'ask_model_catalogue.dart';

/// Phones report a little less memory than they are sold with (a 3 GB
/// phone says about 2.8 GB), so a model fits from this share of its need.
const _memoryAllowance = 0.85;

/// Room left over beside the model, in bytes, so the phone never fills.
const askModelSpareBytes = 300 * 1000 * 1000;

/// The slowest a model may reply in the warm-up, in tokens a second.
const askModelMinTokensPerSecond = 4.0;

/// Whether a phone with [memoryBytes] can run [model]. Unknown memory
/// counts as no.
bool fitsMemory(AskModelEntry model, int? memoryBytes) =>
    memoryBytes != null &&
    memoryBytes >= model.minRamMb * 1024 * 1024 * _memoryAllowance;

/// Whether [freeBytes] has room to download [model], with
/// [alreadyHave] bytes of it fetched.
bool fitsSpace(AskModelEntry model, int? freeBytes, {int alreadyHave = 0}) =>
    freeBytes != null &&
    freeBytes >= model.sizeBytes - alreadyHave + askModelSpareBytes;

/// The models [memoryBytes] and [freeBytes] allow, minus [tooSlow] (those
/// that failed the warm-up here). Empty means Ask never offers one.
List<AskModelEntry> capableModels(
  AskModelCatalogue catalogue, {
  required int? memoryBytes,
  required int? freeBytes,
  Set<AskModelTier> tooSlow = const {},
}) => [
  for (final m in catalogue.models)
    if (!tooSlow.contains(m.tier) &&
        fitsMemory(m, memoryBytes) &&
        fitsSpace(m, freeBytes))
      m,
];

/// Whether a warm-up reply at [tokensPerSecond] is quick enough to use.
bool fastEnough(double tokensPerSecond) =>
    tokensPerSecond >= askModelMinTokensPerSecond;
