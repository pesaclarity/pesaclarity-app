import 'package:flutter/material.dart';

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
      error: BrandTokens.darkBrand,
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
    const pill = StadiumBorder();

    return ThemeData(
      useMaterial3: true,
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
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minTouch,
          shape: pill,
          side: BorderSide(color: colors.border),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: minTouch,
          foregroundColor: colors.link,
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: colors.brandSoft,
        side: BorderSide(color: colors.border),
        shape: pill,
        labelStyle: textTheme.labelMedium,
      ),
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 12,
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: colors.brandSoft,
        indicatorShape: pill,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall!.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
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
