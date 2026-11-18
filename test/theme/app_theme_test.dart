import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/look/look_settings.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';
import 'package:pesaclarity/src/theme/brand_tokens.dart';
import 'package:pesaclarity/src/theme/pesa_colors.dart';

void main() {
  group('light theme', () {
    final theme = AppTheme.light;

    test('uses the brand tokens', () {
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, const Color(0xFFC8102E));
      expect(theme.colorScheme.onPrimary, const Color(0xFFFFFFFF));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF5F5F5));
      expect(theme.colorScheme.surface, const Color(0xFFFFFFFF));
      expect(theme.colorScheme.onSurface, const Color(0xFF171717));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFF525252));
    });

    test('exposes brand colours outside the Material scheme', () {
      final colors = theme.extension<PesaColors>()!;
      expect(colors.brandSoft, const Color(0xFFEBEBEB));
      // Links, progress and the current tab are in the brand's link red.
      expect(colors.link, const Color(0xFFC8102E));
      expect(colors.border, const Color(0xFFE5E5E5));
      expect(colors.successText, const Color(0xFF047857));
      expect(colors.warning, const Color(0xFFB45309));
    });

    test('keeps a deeper brand red for the second chart series', () {
      final colors = theme.extension<PesaColors>()!;
      expect(
        colors.secondSeries,
        Color.lerp(BrandTokens.danger, const Color(0xFF000000), 0.45),
      );
    });
  });

  group('dark theme', () {
    final theme = AppTheme.dark;

    test('uses the dark brand tokens', () {
      expect(theme.brightness, Brightness.dark);
      // The same red as light, with white text on it.
      expect(theme.colorScheme.primary, const Color(0xFFC8102E));
      expect(theme.colorScheme.onPrimary, const Color(0xFFFFFFFF));
      // A soft dark: grey page and cards, not near black.
      expect(theme.scaffoldBackgroundColor, const Color(0xFF121212));
      expect(theme.colorScheme.surface, const Color(0xFF1C1C1C));
      expect(theme.colorScheme.onSurface, const Color(0xFFE0E0E0));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFFA3A3A3));
    });

    test('floats sheets and menus on a lighter surface, without shadows', () {
      final colors = theme.extension<PesaColors>()!;
      expect(colors.field, const Color(0xFF222222));
      expect(colors.floating, const Color(0xFF262626));
      expect(colors.border, const Color(0xFF2E2E2E));
      expect(colors.floatingShadow, isEmpty);
      expect(theme.bottomSheetTheme.backgroundColor, colors.floating);
      expect(theme.bottomSheetTheme.modalElevation, 0);
    });
  });

  group('red in dark is red, never pink', () {
    final theme = AppTheme.dark;
    final colors = theme.extension<PesaColors>()!;

    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    // The hue of a colour, in degrees.
    double hue(Color c) => HSLColor.fromColor(c).hue;

    test('danger is brand red, a fill only', () {
      expect(colors.danger, const Color(0xFFC8102E));
      expect(colors.danger, theme.colorScheme.primary);
      // White on the red fill.
      expect(
        contrast(BrandTokens.darkOnBrand, colors.danger),
        greaterThan(4.5),
      );
      // Under 3:1 on a dark card, so never red text or a red edge there.
      expect(contrast(colors.danger, BrandTokens.darkSurface), lessThan(3));
    });

    test('red figures and edges on dark use the brightened red', () {
      // A large figure below zero takes error; a red edge takes link.
      expect(theme.colorScheme.error, const Color(0xFFFF4D6A));
      expect(colors.link, const Color(0xFFFF4D6A));
      for (final surface in [
        BrandTokens.darkBackground,
        BrandTokens.darkSurface,
        BrandTokens.darkField,
        BrandTokens.darkFloating,
      ]) {
        expect(contrast(colors.link, surface), greaterThanOrEqualTo(3));
      }
      // 5.29:1 on a card.
      expect(
        contrast(colors.link, BrandTokens.darkSurface),
        closeTo(5.29, 0.01),
      );
    });

    test('the second chart series is a neutral grey, not brand red', () {
      // Brand red is under 3:1 on a card, so the series beside the red one
      // (spending's fourth, Plan's Living) is grey in dark.
      expect(colors.secondSeries, const Color(0xFF737373));
      expect(colors.secondSeries, BrandTokens.darkChartGrey);
      final grey = HSLColor.fromColor(colors.secondSeries);
      expect(grey.saturation, 0);
      for (final surface in [
        BrandTokens.darkBackground,
        BrandTokens.darkSurface,
        BrandTokens.darkFloating,
      ]) {
        expect(contrast(colors.secondSeries, surface), greaterThanOrEqualTo(3));
      }
      expect(
        contrast(colors.secondSeries, BrandTokens.darkSurface),
        closeTo(3.59, 0.01),
      );
      // Apart by lightness from its neighbours: the red series, muted text
      // (the next series) and the border ("Other" and the bar's empty part).
      expect(contrast(colors.secondSeries, colors.link), greaterThan(1.4));
      expect(contrast(colors.secondSeries, colors.textMuted), greaterThan(1.8));
      expect(contrast(colors.secondSeries, colors.border), greaterThan(2.5));
    });

    test('the third chart series is a blue, not a second grey', () {
      // Plan's School sits beside the grey Living, so it takes a hue.
      expect(colors.thirdSeries, BrandTokens.darkChartBlue);
      expect(HSLColor.fromColor(colors.thirdSeries).saturation, greaterThan(0));
      for (final surface in [
        BrandTokens.darkBackground,
        BrandTokens.darkSurface,
        BrandTokens.darkFloating,
      ]) {
        expect(contrast(colors.thirdSeries, surface), greaterThanOrEqualTo(3));
      }
      expect(
        contrast(colors.thirdSeries, BrandTokens.darkSurface),
        closeTo(6.70, 0.01),
      );
      expect(
        contrast(colors.thirdSeries, colors.secondSeries),
        greaterThan(1.8),
      );
    });

    test("Plan's Living is a cyan, not the chart grey", () {
      expect(colors.livingSeries, BrandTokens.darkChartCyan);
      expect(
        HSLColor.fromColor(colors.livingSeries).saturation,
        greaterThan(0),
      );
      for (final surface in [
        BrandTokens.darkBackground,
        BrandTokens.darkSurface,
        BrandTokens.darkFloating,
      ]) {
        expect(contrast(colors.livingSeries, surface), greaterThanOrEqualTo(3));
      }
    });

    test('text keeps its contrast on the softer greys', () {
      expect(
        contrast(BrandTokens.darkText, BrandTokens.darkBackground),
        closeTo(14.19, 0.01),
      );
      expect(
        contrast(BrandTokens.darkText, BrandTokens.darkSurface),
        closeTo(12.91, 0.01),
      );
      for (final surface in [
        BrandTokens.darkBackground,
        BrandTokens.darkSurface,
        BrandTokens.darkField,
        BrandTokens.darkFloating,
        BrandTokens.darkSelected,
      ]) {
        expect(
          contrast(BrandTokens.darkTextMuted, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('focus, cursor and chosen controls are in the link red', () {
      expect(theme.textSelectionTheme.cursorColor, colors.link);
      expect(theme.progressIndicatorTheme.color, colors.link);
      expect(
        theme.radioTheme.fillColor!.resolve({WidgetState.selected}),
        colors.link,
      );
      final focused =
          theme.inputDecorationTheme.focusedBorder! as UnderlineInputBorder;
      expect(focused.borderSide.color, colors.link);
      final boxed = AppTheme.withFields(theme, FieldStyle.boxed);
      expect(
        boxed.inputDecorationTheme.focusedBorder!.borderSide.color,
        colors.link,
      );
    });

    test('small danger text is brand red brightened, the same hue', () {
      final text = theme.colorScheme.error;
      expect(text, const Color(0xFFFF4D6A));
      expect(hue(text), closeTo(hue(BrandTokens.brand), 0.5));
      expect(HSLColor.fromColor(text).saturation, 1);
      for (final surface in [
        BrandTokens.darkBackground,
        BrandTokens.darkSurface,
        BrandTokens.darkField,
        BrandTokens.darkFloating,
      ]) {
        expect(contrast(text, surface), greaterThanOrEqualTo(4.5));
      }
      // The pink it replaces.
      expect(text, isNot(const Color(0xFFFF6B7A)));
    });

    test('tints behind red are neutral, not pink', () {
      for (final tint in [colors.brandSoft, colors.selected]) {
        final hsl = HSLColor.fromColor(tint);
        // Not rose: no more red than green and blue together suggest.
        expect(hsl.saturation, lessThan(0.06), reason: '$tint');
        expect(tint.b, lessThanOrEqualTo(tint.g), reason: '$tint');
      }
      expect(colors.brandSoft, const Color(0xFF262626));
      expect(colors.selected, const Color(0xFF333333));
    });

    test('light keeps its reds', () {
      final light = AppTheme.light;
      expect(light.colorScheme.error, const Color(0xFFC8102E));
      expect(light.extension<PesaColors>()!.danger, const Color(0xFFC8102E));
      expect(light.extension<PesaColors>()!.brandSoft, const Color(0xFFEBEBEB));
    });
  });

  group('high contrast', () {
    test('dark strengthens text, muted text and edges', () {
      final theme = AppTheme.darkHighContrast;
      final colors = theme.extension<PesaColors>()!;
      expect(theme.brightness, Brightness.dark);
      // Keeps the deeper near-black page of the old dark.
      expect(theme.scaffoldBackgroundColor, const Color(0xFF0A0A0A));
      expect(theme.colorScheme.onSurface, const Color(0xFFF5F5F5));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFFCCCCCC));
      expect(colors.textMuted, const Color(0xFFCCCCCC));
      expect(colors.border, const Color(0xFF525252));
      expect(colors.link, const Color(0xFFFF4D6A));
    });

    test('light strengthens text, muted text and edges', () {
      final theme = AppTheme.lightHighContrast;
      final colors = theme.extension<PesaColors>()!;
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.onSurface, const Color(0xFF0A0A0A));
      expect(colors.textMuted, const Color(0xFF404040));
      expect(colors.border, const Color(0xFFC4C4C4));
    });
  });

  group('controls', () {
    test('a switch that is on is green, not red', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final colors = theme.extension<PesaColors>()!;
        final track = theme.switchTheme.trackColor!.resolve({
          WidgetState.selected,
        });
        expect(track, colors.success);
        expect(track, isNot(theme.colorScheme.primary));
      }
    });

    test('the light tab bar and menus have a soft shadow', () {
      expect(PesaColors.light.floatingShadow, isNotEmpty);
    });
  });

  group('typography', () {
    final text = AppTheme.light.textTheme;

    test('uses Space Grotesk with tabular figures for numbers and titles', () {
      for (final style in [
        text.displayLarge!,
        text.headlineSmall!,
        text.titleLarge!,
      ]) {
        expect(style.fontFamily, BrandTokens.displayFont);
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      }
    });

    test('uses Inter for body text and labels', () {
      for (final style in [
        text.bodyLarge!,
        text.bodyMedium!,
        text.labelLarge!,
        text.titleMedium!,
      ]) {
        expect(style.fontFamily, BrandTokens.bodyFont);
      }
    });
  });

  test('buttons meet the 44 px touch target', () {
    final size = AppTheme.light.filledButtonTheme.style!.minimumSize!.resolve(
      {},
    );
    expect(size!.height, greaterThanOrEqualTo(BrandTokens.touchTarget));
  });
}
