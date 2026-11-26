import 'package:flutter/foundation.dart';

import '../../domain/ml/rayo_only.dart';

export '../../domain/ml/rayo_only.dart';

/// What runs one model: [engine] as shown in Profile › About, the weights'
/// [version], and [reason] when it is not rayo.
@immutable
class ModelEngine {
  const ModelEngine(this.engine, {this.version, this.reason});

  static const notLoaded = ModelEngine('Not loaded');
  static const dartFallback = 'Dart fallback';
  static const templates = 'Templates (no writer)';
  static const failed = 'Rayo failed';

  final String engine;
  final String? version;
  final String? reason;

  ModelEngine withVersion(String? version) =>
      ModelEngine(engine, version: version ?? this.version, reason: reason);

  /// One line, such as `Rayo (NEON, SDOT) · weights 1a2b3c4d`.
  String describe() => [engine, ?version, ?reason].join(' · ');
}

/// rayo's engine name for its [kernels] (`rayo_session_kernels`), such as
/// `Rayo (NEON, SDOT)` for `neon-dotprod`.
String rayoEngineName(String kernels) => switch (kernels) {
  'neon-dotprod' => 'Rayo (NEON, SDOT)',
  'neon' => 'Rayo (NEON)',
  'generic' || '' => 'Rayo (generic)',
  'avx-vnni' => 'Rayo (AVX-VNNI)',
  'avx2' => 'Rayo (AVX2)',
  'sse4.1' => 'Rayo (SSE4.1)',
  _ => 'Rayo ($kernels)',
};

/// The weights' version as the app can tell it: their SHA-256's first
/// eight hex digits.
String weightsVersion(String sha256) =>
    'weights ${sha256.length > 8 ? sha256.substring(0, 8) : sha256}';

/// What runs each on-phone model, filled in as each one loads.
class ModelEngines extends ChangeNotifier {
  ModelEngines();

  /// The app's own.
  static final instance = ModelEngines();

  final _engines = <OnPhoneModel, ModelEngine>{};

  ModelEngine of(OnPhoneModel model) =>
      _engines[model] ?? ModelEngine.notLoaded;

  /// Records what runs [model], keeping a version recorded before.
  void record(OnPhoneModel model, ModelEngine engine) {
    final before = _engines[model];
    _engines[model] = engine.version == null && before?.version != null
        ? engine.withVersion(before!.version)
        : engine;
    if (engine.reason != null) {
      debugPrint('${model.label}: ${_engines[model]!.describe()}');
    }
    notifyListeners();
  }

  /// Records [model]'s weights version.
  void version(OnPhoneModel model, String version) {
    _engines[model] = of(model).withVersion(version);
    notifyListeners();
  }

  @visibleForTesting
  void clear() {
    _engines.clear();
    notifyListeners();
  }
}
