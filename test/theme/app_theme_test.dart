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
      expect(colors.link, const Color(0xFF1C1215));
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

  group('high contrast', () {
    test('dark strengthens text, muted text and edges', () {
      final theme = AppTheme.darkHighContrast;
      final colors = theme.extension<PesaColors>()!;
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.onSurface, const Color(0xFFF5EEF0));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFFCFC3C6));
      expect(colors.textMuted, const Color(0xFFCFC3C6));
      expect(colors.border, const Color(0xFF5A4A4F));
      expect(colors.link, const Color(0xFFF5EEF0));
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
