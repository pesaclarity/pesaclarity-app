import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/look/look_settings.dart';
import 'app_typography.dart';
import 'brand_tokens.dart';
import 'pesa_colors.dart';

/// Light and dark Material themes built from the brand tokens.
abstract final class AppTheme {
  static ThemeData get light => _build(
    brightness: Brightness.light,
    scheme: const ColorScheme(
      brightness: Brightness.light,
      primary: BrandTokens.brand,
      onPrimary: BrandTokens.onBrand,
      primaryContainer: BrandTokens.brandSoft,
      onPrimaryContainer: BrandTokens.text,
      secondary: BrandTokens.text,
      onSecondary: BrandTokens.surface,
      tertiary: BrandTokens.success,
      onTertiary: BrandTokens.onBrand,
      error: BrandTokens.danger,
      onError: BrandTokens.onBrand,
      surface: BrandTokens.surface,
      onSurface: BrandTokens.text,
      onSurfaceVariant: BrandTokens.textMuted,
      surfaceContainerLowest: BrandTokens.surface,
      surfaceContainerLow: BrandTokens.surface,
      surfaceContainer: BrandTokens.surface,
      surfaceContainerHigh: BrandTokens.background,
      surfaceContainerHighest: BrandTokens.border,
      outline: BrandTokens.textMuted,
      outlineVariant: BrandTokens.border,
    ),
    background: BrandTokens.background,
    colors: PesaColors.light,
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    scheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: BrandTokens.darkBrand,
      onPrimary: BrandTokens.darkOnBrand,
      primaryContainer: BrandTokens.darkBrandSoft,
      onPrimaryContainer: BrandTokens.darkText,
      secondary: BrandTokens.darkText,
      onSecondary: BrandTokens.darkSurface,
      tertiary: BrandTokens.darkSuccess,
      onTertiary: BrandTokens.darkOnBrand,
      error: BrandTokens.darkDanger,
      onError: BrandTokens.darkOnBrand,
      surface: BrandTokens.darkSurface,
      onSurface: BrandTokens.darkText,
      onSurfaceVariant: BrandTokens.darkTextMuted,
      surfaceContainerLowest: BrandTokens.darkBackground,
      surfaceContainerLow: BrandTokens.darkSurface,
      surfaceContainer: BrandTokens.darkSurface,
      surfaceContainerHigh: BrandTokens.darkSurface,
      surfaceContainerHighest: BrandTokens.darkBorder,
      outline: BrandTokens.darkTextMuted,
      outlineVariant: BrandTokens.darkBorder,
    ),
    background: BrandTokens.darkBackground,
    colors: PesaColors.dark,
  );

  /// [base] with text fields drawn as [style]: underlined, as the theme
  /// draws them, or boxed.
  static ThemeData withFields(ThemeData base, FieldStyle style) {
    if (style == FieldStyle.underlined) return base;
    final colors = base.extension<PesaColors>()!;
    OutlineInputBorder box(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(BrandTokens.fieldRadius),
          borderSide: BorderSide(color: color, width: width),
        );
    return base.copyWith(
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: box(colors.border),
        enabledBorder: box(colors.border),
        disabledBorder: box(colors.border.withValues(alpha: 0.5)),
        focusedBorder: box(base.colorScheme.primary, 2),
        errorBorder: box(base.colorScheme.error),
        focusedErrorBorder: box(base.colorScheme.error, 2),
      ),
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color background,
    required PesaColors colors,
  }) {
    final textTheme = AppTypography.textTheme(
      scheme.onSurface,
      scheme.onSurfaceVariant,
    );
    const minTouch = Size(BrandTokens.touchTarget, BrandTokens.touchTarget);
    const OutlinedBorder pill = StadiumBorder();
    // Read when the theme is built, so tests can override the platform.
    final iPhone = defaultTargetPlatform == TargetPlatform.iOS;

    return ThemeData(
      useMaterial3: true,
      // One design on Android and iPhone (decision 0011); iPhone keeps its
      // swipe-back page transition.
      platform: TargetPlatform.android,
      pageTransitionsTheme: iPhone
          ? const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: CupertinoPageTransitionsBuilder(),
              },
            )
          : null,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: BrandTokens.bodyFont,
      textTheme: textTheme,
      extensions: [colors],
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        // Keeps a tap's ripple inside the rounded corners.
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
          side: BorderSide(color: colors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: minTouch,
          shape: pill,
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      // Red is kept for the lead card and the one main button on a
      // screen; every other button and link is in the text colour.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minTouch,
          shape: pill,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: colors.border),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: minTouch,
          foregroundColor: scheme.onSurface,
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: colors.brandSoft,
        side: BorderSide(color: colors.border),
        shape: const StadiumBorder(),
        labelStyle: textTheme.labelMedium,
      ),
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 12,
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? scheme.primary : null,
        ),
      ),
    );
  }
}
