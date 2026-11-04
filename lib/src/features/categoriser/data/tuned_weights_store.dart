import '../../../data/repositories/app_settings_repository.dart';
import '../../../domain/categoriser/trainable.dart';

/// [TunedWeightsStore] in the open space's encrypted settings, so each space
/// learns only from its own confirmations.
class SettingsTunedWeightsStore implements TunedWeightsStore {
  SettingsTunedWeightsStore(this._settings);

  final AppSettingsRepository _settings;

  static const weightsKey = 'categoriser.tunedWeights';
  static const lastRunKey = 'categoriser.lastLearningRun';

  @override
  Future<TunedWeights?> read() async {
    final json = await _settings.readJson(weightsKey);
    return json == null ? null : TunedWeights.fromJson(json);
  }

  @override
  Future<void> write(TunedWeights weights) =>
      _settings.writeJson(weightsKey, weights.toJson());

  @override
  Future<DateTime?> lastRun() async {
    final at = (await _settings.readJson(lastRunKey))?['at_ms'];
    return at is int
        ? DateTime.fromMillisecondsSinceEpoch(at, isUtc: true)
        : null;
  }

  @override
  Future<void> markRun(DateTime at) =>
      _settings.writeJson(lastRunKey, {'at_ms': at.millisecondsSinceEpoch});
}
