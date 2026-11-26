import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../shared/adaptive/adaptive.dart';
import '../data/slm_model_licence.dart';
import 'slm_experiment_screen.dart';

/// Profile › About: opens the experiment. Shown only when `SLM_EXPERIMENT`
/// is set (test builds).
class SlmExperimentTile extends StatelessWidget {
  const SlmExperimentTile({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
    key: const Key('profile-slm-experiment'),
    leading: const RowIcon(Icons.science_outlined),
    title: const Text(SlmStrings.profileRow),
    subtitle: const Text(SlmStrings.profileRowDetail),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SlmExperimentScreen()),
    ),
  );
}

/// Puts the model's licence on the licences page (test builds only).
void registerSlmLicence() => LicenseRegistry.addLicense(
  () => Stream.value(
    const LicenseEntryWithLineBreaks([
      slmModelName,
    ], '$slmModelAttribution\n\n$slmModelLicence'),
  ),
);
