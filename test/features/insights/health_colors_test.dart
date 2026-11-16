import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/health/health_index.dart';
import 'package:pesaclarity/src/domain/health/health_inputs.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/insights/presentation/health_colors.dart';
import 'package:pesaclarity/src/features/insights/presentation/health_pillar_sheet.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';
import 'package:pesaclarity/src/theme/brand_tokens.dart';
import 'package:pesaclarity/src/theme/pesa_colors.dart';

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('$name: struggling is a stronger amber, never brand red', (
      tester,
    ) async {
      late Map<HealthBand, Color> band;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              band = {
                for (final b in HealthBand.values)
                  b: healthBandColor(context, b),
              };
              return const SizedBox();
            },
          ),
        ),
      );
      final colors = theme.extension<PesaColors>()!;
      expect(band[HealthBand.healthy], colors.success);
      expect(band[HealthBand.coping], colors.warning);
      expect(band[HealthBand.struggling], colors.warningStrong);
      // The two warning bands stay apart, and neither is red.
      expect(band[HealthBand.struggling], isNot(band[HealthBand.coping]));
      for (final c in band.values) {
        expect(c, isNot(theme.colorScheme.primary));
        expect(c, isNot(theme.colorScheme.error));
        expect(c, isNot(BrandTokens.brand));
      }
    });

    testWidgets('$name: the pillar sheet bars follow the bands', (
      tester,
    ) async {
      final index = HealthIndex.compute(
        HealthInputs(month: YearMonth(2026, 9)),
      );
      final colors = theme.extension<PesaColors>()!;
      for (final pillar in HealthPillar.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: SingleChildScrollView(
                child: HealthPillarSheet(index: index, pillar: pillar),
              ),
            ),
          ),
        );
        final bars = tester.widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(bars, isNotEmpty);
        for (final bar in bars) {
          expect(
            bar.color,
            isIn([colors.success, colors.warning, colors.warningStrong]),
          );
          expect(bar.color, isNot(theme.colorScheme.error));
        }
      }
    });
  }
}
