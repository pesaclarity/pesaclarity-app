import 'package:flutter/material.dart';

import '../../../domain/health/health_index.dart';
import '../../../theme/pesa_colors.dart';

/// The colour a health score is drawn in, so the ring or bar says how it
/// is going: the theme's success colour when healthy, its warning colour
/// while coping, and its danger colour when struggling.
Color healthBandColor(BuildContext context, HealthBand band) {
  final colors = PesaColors.of(context);
  return switch (band) {
    HealthBand.healthy => colors.success,
    HealthBand.coping => colors.warning,
    HealthBand.struggling => Theme.of(context).colorScheme.error,
  };
}
