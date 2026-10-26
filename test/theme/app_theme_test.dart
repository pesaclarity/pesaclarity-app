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
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFBF8F8));
      expect(theme.colorScheme.surface, const Color(0xFFFFFFFF));
      expect(theme.colorScheme.onSurface, const Color(0xFF1C1215));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFF6F6064));
    });

    test('exposes brand colours outside the Material scheme', () {
      final colors = theme.extension<PesaColors>()!;
      expect(colors.brandSoft, const Color(0xFFFDECEE));
      expect(colors.link, const Color(0xFFB81D2F));
      expect(colors.border, const Color(0xFFEFE6E7));
      expect(colors.successText, const Color(0xFF047857));
      expect(colors.warning, const Color(0xFFB45309));
    });
  });

  group('dark theme', () {
    final theme = AppTheme.dark;

    test('uses the dark brand tokens', () {
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, const Color(0xFFFF6B7A));
      expect(theme.scaffoldBackgroundColor, const Color(0xFF1A1214));
      expect(theme.colorScheme.surface, const Color(0xFF251B1E));
      expect(theme.colorScheme.onSurface, const Color(0xFFEDE4E6));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFFB3A5A9));
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
