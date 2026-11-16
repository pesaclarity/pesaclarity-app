import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF6F1EE));
      expect(theme.colorScheme.surface, const Color(0xFFFFFFFF));
      expect(theme.colorScheme.onSurface, const Color(0xFF1C1215));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFF6F6064));
    });

    test('exposes brand colours outside the Material scheme', () {
      final colors = theme.extension<PesaColors>()!;
      expect(colors.brandSoft, const Color(0xFFFDECEE));
      // Links are in the text colour.
      expect(colors.link, const Color(0xFFC8102E));
      expect(colors.border, const Color(0xFFEFE6E7));
      expect(colors.successText, const Color(0xFF047857));
      expect(colors.warning, const Color(0xFFB45309));
    });
  });

  group('dark theme', () {
    final theme = AppTheme.dark;

    test('uses the dark brand tokens', () {
      expect(theme.brightness, Brightness.dark);
      // The same red as light, with white text on it.
      expect(theme.colorScheme.primary, const Color(0xFFC8102E));
      expect(theme.colorScheme.onPrimary, const Color(0xFFFFFFFF));
      expect(theme.scaffoldBackgroundColor, const Color(0xFF140E10));
      expect(theme.colorScheme.surface, const Color(0xFF1E1618));
      expect(theme.colorScheme.onSurface, const Color(0xFFE3D9DB));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFFA3969A));
    });

    test('floats sheets and menus on a lighter surface, without shadows', () {
      final colors = theme.extension<PesaColors>()!;
      expect(colors.field, const Color(0xFF241B1E));
      expect(colors.floating, const Color(0xFF2A2124));
      expect(colors.border, const Color(0xFF352B2E));
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

    test('danger is brand red, for fills and large figures', () {
      expect(colors.danger, const Color(0xFFC8102E));
      expect(colors.danger, theme.colorScheme.primary);
      // 3:1 for a large figure on a card and on the page.
      expect(contrast(colors.danger, BrandTokens.darkSurface), greaterThan(3));
      expect(
        contrast(colors.danger, BrandTokens.darkBackground),
        greaterThan(3),
      );
      // White on the red fill.
      expect(
        contrast(BrandTokens.darkOnBrand, colors.danger),
        greaterThan(4.5),
      );
    });

    test('small danger text is brand red brightened, the same hue', () {
      final text = theme.colorScheme.error;
      expect(text, const Color(0xFFFF3C5B));
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
      expect(colors.brandSoft, const Color(0xFF2F2D2C));
      expect(colors.selected, const Color(0xFF383534));
    });

    test('light keeps its reds', () {
      final light = AppTheme.light;
      expect(light.colorScheme.error, const Color(0xFFC8102E));
      expect(light.extension<PesaColors>()!.danger, const Color(0xFFC8102E));
      expect(light.extension<PesaColors>()!.brandSoft, const Color(0xFFFDECEE));
    });
  });

  group('high contrast', () {
    test('dark strengthens text, muted text and edges', () {
      final theme = AppTheme.darkHighContrast;
      final colors = theme.extension<PesaColors>()!;
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.onSurface, const Color(0xFFF5EEF0));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFFCFC3C6));
      expect(colors.textMuted, const Color(0xFFCFC3C6));
      expect(colors.border, const Color(0xFF5A4A4F));
      expect(colors.link, const Color(0xFFFF3C5B));
    });

    test('light strengthens text, muted text and edges', () {
      final theme = AppTheme.lightHighContrast;
      final colors = theme.extension<PesaColors>()!;
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.onSurface, const Color(0xFF120A0D));
      expect(colors.textMuted, const Color(0xFF4F4246));
      expect(colors.border, const Color(0xFFCDBFC2));
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
