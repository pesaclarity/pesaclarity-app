import 'package:flutter/material.dart';

import '../../../domain/health/health_index.dart';
import '../../../theme/pesa_colors.dart';

/// The colour a health score is drawn in, so the ring or bar says how it
/// is going, in grey and red only: the text colour when healthy, muted grey
/// while coping, and red when struggling, the one band that is a problem.
Color healthBandColor(BuildContext context, HealthBand band) {
  final colors = PesaColors.of(context);
  return switch (band) {
    HealthBand.healthy => colors.good,
    HealthBand.coping => colors.textMuted,
    HealthBand.struggling => colors.problem,
  };
}
