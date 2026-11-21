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
      // Links, the current tab and real problems are in the link red.
      expect(colors.link, const Color(0xFFC8102E));
      expect(colors.problem, colors.link);
      expect(colors.border, const Color(0xFFE5E5E5));
      // Good news is plain text: no green.
      expect(colors.good, theme.colorScheme.onSurface);
    });

    test('charts are greys told apart by lightness, never red', () {
      final colors = theme.extension<PesaColors>()!;
      final greys = colors.chartGreys;
      expect(greys, hasLength(5));
      for (final c in greys) {
        expect(HSLColor.fromColor(c).saturation, 0, reason: '$c');
      }
      final lightness = [for (final c in greys) c.computeLuminance()];
      expect(lightness, orderedEquals([...lightness]..sort()));
    });
  });

  group('dark theme', () {
    final theme = AppTheme.dark;

    test('uses the dark brand tokens', () {
      expect(theme.brightness, Brightness.dark);
      // The same red as light, with white text on it.
      expect(theme.colorScheme.primary, const Color(0xFFC8102E));
      expect(theme.colorScheme.onPrimary, const Color(0xFFFFFFFF));
      // One plain dark surface: the page and the cards are the same.
      expect(theme.scaffoldBackgroundColor, const Color(0xFF121212));
      expect(theme.colorScheme.surface, const Color(0xFF121212));
      expect(theme.colorScheme.onSurface, const Color(0xFFE0E0E0));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFFA3A3A3));
    });

    test('sheets and menus sit on the same plain surface, set apart by an '
        'edge', () {
      final colors = theme.extension<PesaColors>()!;
      final surface = theme.scaffoldBackgroundColor;
      expect(colors.border, const Color(0xFF2E2E2E));
      expect(theme.bottomSheetTheme.backgroundColor, surface);
      expect(theme.bottomSheetTheme.modalElevation, 0);
      expect(theme.dialogTheme.backgroundColor, surface);
      expect(theme.popupMenuTheme.color, surface);
      expect(theme.menuTheme.style!.backgroundColor!.resolve({}), surface);
      final sheet = theme.bottomSheetTheme.shape! as RoundedRectangleBorder;
      expect(sheet.side.color, colors.border);
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
      ]) {
        expect(
          contrast(BrandTokens.darkTextMuted, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('focus, cursor and chosen controls are in the link red', () {
      expect(theme.textSelectionTheme.cursorColor, colors.link);
      // Progress is in the text colour: red is for actions and problems.
      expect(theme.progressIndicatorTheme.color, theme.colorScheme.onSurface);
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

    test('tints behind red are neutral, not pink: there are none', () {
      // Containers that once took a tint are the plain surface now, in
      // light and dark: nothing behind red is pink, or any tint at all.
      for (final t in [AppTheme.light, AppTheme.dark]) {
        final scheme = t.colorScheme;
        for (final tint in [
          scheme.primaryContainer,
          scheme.surfaceContainer,
          scheme.surfaceContainerHigh,
        ]) {
          expect(tint, scheme.surface, reason: '$tint');
          final hsl = HSLColor.fromColor(tint);
          expect(hsl.saturation, lessThan(0.06), reason: '$tint');
          expect(tint.b, lessThanOrEqualTo(tint.g), reason: '$tint');
        }
        expect(t.chipTheme.backgroundColor, Colors.transparent);
        expect(t.chipTheme.selectedColor, Colors.transparent);
      }
    });

    test('light keeps its reds', () {
      final light = AppTheme.light;
      expect(light.colorScheme.error, const Color(0xFFC8102E));
      expect(light.extension<PesaColors>()!.danger, const Color(0xFFC8102E));
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
    test('a switch that is on is a link-red track under a plain thumb', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final colors = theme.extension<PesaColors>()!;
        final on = {WidgetState.selected};
        expect(theme.switchTheme.trackColor!.resolve(on), colors.link);
        expect(
          theme.switchTheme.thumbColor!.resolve(on),
          theme.colorScheme.surface,
        );
        // Off: a plain track inside a grey edge, no grey fill.
        expect(
          theme.switchTheme.trackColor!.resolve({}),
          theme.colorScheme.surface,
        );
      }
    });

    test('nothing floats on a shadow: menus, sheets and dialogs are flat', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        expect(theme.popupMenuTheme.elevation, 0);
        expect(theme.menuTheme.style!.elevation!.resolve({}), 0);
        expect(theme.bottomSheetTheme.elevation, 0);
        expect(theme.bottomSheetTheme.modalElevation, 0);
        expect(theme.dialogTheme.elevation, 0);
        expect(theme.chipTheme.elevation, 0);
        // Sheets and dialogs keep the default plain dim behind them (no
        // shadow), so the screen behind reads as paused.
        expect(theme.bottomSheetTheme.modalBarrierColor, isNull);
        expect(theme.dialogTheme.barrierColor, isNull);
      }
    });

    test('a chosen chip says so with its label in red, with no tick', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final colors = theme.extension<PesaColors>()!;
        final label = theme.chipTheme.labelStyle!.color! as WidgetStateColor;
        expect(label.resolve({WidgetState.selected}), colors.link);
        expect(label.resolve({}), theme.colorScheme.onSurface);
        expect(theme.chipTheme.showCheckmark, isFalse);
        expect(theme.chipTheme.iconTheme!.color, colors.link);
      }
    });

    test('a chosen segment is red text on the plain background', () {
      double contrast(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
      }

      for (final theme in [
        AppTheme.light,
        AppTheme.dark,
        AppTheme.lightHighContrast,
        AppTheme.darkHighContrast,
      ]) {
        final colors = theme.extension<PesaColors>()!;
        final style = theme.segmentedButtonTheme.style!;
        const on = {WidgetState.selected};
        // No fill, chosen or not: never a solid black, grey or red block.
        expect(style.backgroundColor!.resolve(on), Colors.transparent);
        expect(style.backgroundColor!.resolve({}), Colors.transparent);
        expect(style.foregroundColor!.resolve(on), colors.link);
        expect(style.foregroundColor!.resolve({}), theme.colorScheme.onSurface);
        // Red text reads at 4.5:1 on the page, a card and a sheet.
        for (final surface in [
          theme.scaffoldBackgroundColor,
          // Sheets and menus share the plain surface now.
          theme.colorScheme.surface,
        ]) {
          expect(
            contrast(colors.link, surface),
            greaterThanOrEqualTo(4.5),
            reason: '${theme.brightness} on $surface',
          );
        }
      }
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
