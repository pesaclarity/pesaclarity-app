import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/look/look_settings.dart';
import 'app_typography.dart';
import 'brand_tokens.dart';
import 'layout.dart';
import 'pesa_colors.dart';

/// Light and dark Material themes built from the brand tokens.
abstract final class AppTheme {
  static ThemeData get light => _build(
    scheme: _lightScheme,
    background: BrandTokens.background,
    colors: PesaColors.light,
  );

  static ThemeData get dark => _build(
    scheme: _darkScheme,
    background: BrandTokens.darkBackground,
    colors: PesaColors.dark,
  );

  /// [light] with stronger text and edges, for the phone's high-contrast
  /// setting.
  static ThemeData get lightHighContrast => _build(
    scheme: _lightScheme.copyWith(
      onSurface: BrandTokens.hcText,
      onSurfaceVariant: BrandTokens.hcTextMuted,
      onPrimaryContainer: BrandTokens.hcText,
      secondary: BrandTokens.hcText,
      outline: BrandTokens.hcTextMuted,
      outlineVariant: BrandTokens.hcBorder,
    ),
    background: BrandTokens.background,
    colors: PesaColors.lightHighContrast,
  );

  /// [dark] with stronger text and edges, for the phone's high-contrast
  /// setting.
  static ThemeData get darkHighContrast => _build(
    scheme: _darkScheme.copyWith(
      onSurface: BrandTokens.darkHcText,
      onSurfaceVariant: BrandTokens.darkHcTextMuted,
      onPrimaryContainer: BrandTokens.darkHcText,
      secondary: BrandTokens.darkHcText,
      outline: BrandTokens.darkHcTextMuted,
      outlineVariant: BrandTokens.darkHcBorder,
    ),
    background: BrandTokens.darkBackground,
    colors: PesaColors.darkHighContrast,
  );

  static const _lightScheme = ColorScheme(
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
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: BrandTokens.darkBrand,
    onPrimary: BrandTokens.darkOnBrand,
    primaryContainer: BrandTokens.darkBrandSoft,
    onPrimaryContainer: BrandTokens.darkText,
    secondary: BrandTokens.darkText,
    onSecondary: BrandTokens.darkSurface,
    tertiary: BrandTokens.darkSuccess,
    onTertiary: BrandTokens.darkBackground,
    error: BrandTokens.darkDanger,
    onError: BrandTokens.darkBackground,
    surface: BrandTokens.darkSurface,
    onSurface: BrandTokens.darkText,
    onSurfaceVariant: BrandTokens.darkTextMuted,
    surfaceContainerLowest: BrandTokens.darkBackground,
    surfaceContainerLow: BrandTokens.darkSurface,
    surfaceContainer: BrandTokens.darkField,
    surfaceContainerHigh: BrandTokens.darkFloating,
    surfaceContainerHighest: BrandTokens.darkFloating,
    outline: BrandTokens.darkTextMuted,
    outlineVariant: BrandTokens.darkBorder,
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
    required ColorScheme scheme,
    required Color background,
    required PesaColors colors,
  }) {
    final brightness = scheme.brightness;
    final dark = brightness == Brightness.dark;
    // Floating parts sit on a lighter surface in dark and on a soft shadow
    // in light.
    final floatingElevation = colors.floatingElevation;
    final floatingShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Layout.panelRadius),
      side: BorderSide(color: colors.border),
    );
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
      // One back arrow on every pushed screen and sheet.
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (context) => const Icon(Icons.arrow_back),
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
      // Chips sit a step above the card; a selected one takes a neutral
      // tint. The theme's padded tap target keeps each one, and its ×,
      // at least 48 dp tall.
      chipTheme: ChipThemeData(
        backgroundColor: colors.field,
        selectedColor: colors.selected,
        checkmarkColor: scheme.onSurface,
        deleteIconColor: scheme.onSurfaceVariant,
        side: BorderSide(color: colors.border),
        shape: const StadiumBorder(),
        labelStyle: textTheme.labelMedium,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.floating,
        surfaceTintColor: Colors.transparent,
        elevation: floatingElevation,
        shadowColor: colors.shadow,
        shape: floatingShape,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.floating),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: WidgetStatePropertyAll(floatingElevation),
          shadowColor: WidgetStatePropertyAll(colors.shadow),
          shape: WidgetStatePropertyAll(floatingShape),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.floating,
        modalBackgroundColor: colors.floating,
        surfaceTintColor: Colors.transparent,
        elevation: floatingElevation,
        modalElevation: floatingElevation,
        shadowColor: colors.shadow,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.floating,
        surfaceTintColor: Colors.transparent,
        elevation: floatingElevation,
        shadowColor: colors.shadow,
      ),
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 12,
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall,
      ),
      // On is calm green, so red stays for danger and the main action.
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? colors.success : null,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (dark ? BrandTokens.darkBackground : BrandTokens.surface)
              : null,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? colors.success : null,
        ),
      ),
    );
  }
}
