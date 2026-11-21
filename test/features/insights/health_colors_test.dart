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
    testWidgets('$name: grey and red only, red for struggling', (tester) async {
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
      // Healthy in the text colour, coping in muted grey, and struggling,
      // the one band that is a problem, in red. No green or amber.
      expect(band[HealthBand.healthy], theme.colorScheme.onSurface);
      expect(band[HealthBand.coping], colors.textMuted);
      expect(band[HealthBand.struggling], colors.link);
      expect(band.values.toSet(), hasLength(3));
      for (final c in band.values) {
        expect(c, isNot(BrandTokens.success));
        expect(c, isNot(BrandTokens.warning));
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
            isIn([theme.colorScheme.onSurface, colors.textMuted, colors.link]),
          );
        }
      }
    });
  }
}
