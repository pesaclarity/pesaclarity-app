import 'package:flutter/material.dart';

import '../../../core/ml/model_engines.dart';
import '../../../shared/adaptive/adaptive.dart';

/// Profile › About: what runs each on-phone model, as each one loads.
class ModelEngineTile extends StatelessWidget {
  const ModelEngineTile({super.key, this.engines, this.onlyRayo = rayoOnly});

  /// The app's own when null.
  final ModelEngines? engines;
  final bool onlyRayo;

  /// The tile's lines, one per model, then whether the build is rayo-only.
  static List<String> lines(ModelEngines engines, {required bool onlyRayo}) => [
    for (final model in OnPhoneModel.values)
      '${model.label}: ${engines.of(model).describe()}',
    if (onlyRayo) 'Rayo only: on',
  ];

  @override
  Widget build(BuildContext context) {
    final log = engines ?? ModelEngines.instance;
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) => ListTile(
        key: const Key('profile-model-engine'),
        leading: const RowIcon(Icons.memory_outlined),
        title: const Text('Model engine'),
        subtitle: Text(lines(log, onlyRayo: onlyRayo).join('\n')),
      ),
    );
  }
}
