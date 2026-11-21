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
      surfaceContainerLowest: BrandTokens.darkHcBackground,
    ),
    background: BrandTokens.darkHcBackground,
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
    error: BrandTokens.dangerText,
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
    error: BrandTokens.darkDangerText,
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
        focusedBorder: box(colors.link, 2),
        errorBorder: box(base.colorScheme.error),
        focusedErrorBorder: box(base.colorScheme.error, 2),
      ),
    );
  }

  /// An iPhone field's outline: rounded, and only drawn when [side] is.
  static OutlineInputBorder _row([BorderSide side = BorderSide.none]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(BrandTokens.fieldRadius),
        borderSide: side,
      );

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
    // Read when the theme is built, so tests can override the platform.
    final iPhone = defaultTargetPlatform == TargetPlatform.iOS;
    final textTheme = AppTypography.textTheme(
      scheme.onSurface,
      scheme.onSurfaceVariant,
      iPhone: iPhone,
    );
    const minTouch = Size(BrandTokens.touchTarget, BrandTokens.touchTarget);
    const OutlinedBorder pill = StadiumBorder();

    return ThemeData(
      useMaterial3: true,
      // One design on Android and iPhone (decision 0011). iPhone keeps its
      // swipe-back page transition and takes the iOS conventions people
      // expect: a 34 bold tab title, a back chevron with a centred title,
      // and text fields drawn as filled rows.
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
        centerTitle: iPhone,
        titleTextStyle: iPhone ? textTheme.titleMedium : textTheme.titleLarge,
      ),
      // One back arrow on every pushed screen and sheet: a chevron on
      // iPhone.
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (context) =>
            Icon(iPhone ? Icons.arrow_back_ios_new : Icons.arrow_back),
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
      // Chips sit a step above the card; a selected one takes the soft
      // brand tint. The theme's padded tap target keeps each
      // one, and its ×, at least 48 dp tall.
      chipTheme: ChipThemeData(
        backgroundColor: colors.field,
        selectedColor: colors.brandSoft,
        checkmarkColor: scheme.onSurface,
        deleteIconColor: scheme.onSurfaceVariant,
        side: BorderSide(color: colors.border),
        shape: const StadiumBorder(),
        labelStyle: textTheme.labelMedium,
      ),
      // The chosen segment has no fill: its label is in the link red (brand
      // red in light, brightened in dark) on the same plain background as
      // the others, whose labels are in the text colour. Red only ever sits
      // on a plain background; the outline and divider stay as they are.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: 0.38)
                : states.contains(WidgetState.selected)
                ? colors.link
                : scheme.onSurface,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.link
                : scheme.onSurface,
          ),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.focused)) {
              return scheme.onSurface.withValues(alpha: 0.1);
            }
            if (states.contains(WidgetState.hovered)) {
              return scheme.onSurface.withValues(alpha: 0.08);
            }
            return null;
          }),
        ),
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
      // A focused field, the text cursor, a chosen radio or box and progress
      // take the link red: brand red in light, brightened in dark, where
      // brand red is a fill only (2.9:1 on a card).
      inputDecorationTheme: InputDecorationTheme(
        // On iPhone a field is a filled row with no line under it.
        filled: iPhone,
        fillColor: iPhone ? colors.selected : null,
        border: iPhone ? _row() : null,
        enabledBorder: iPhone ? _row() : null,
        disabledBorder: iPhone ? _row() : null,
        contentPadding: iPhone
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
            : null,
        focusedBorder: iPhone
            ? _row(BorderSide(color: colors.link, width: 2))
            : UnderlineInputBorder(
                borderSide: BorderSide(color: colors.link, width: 2),
              ),
        errorBorder: iPhone ? _row(BorderSide(color: scheme.error)) : null,
        focusedErrorBorder: iPhone
            ? _row(BorderSide(color: scheme.error, width: 2))
            : null,
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.error)
                ? scheme.error
                : states.contains(WidgetState.focused)
                ? colors.link
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.link,
        selectionHandleColor: colors.link,
        selectionColor: colors.link.withValues(alpha: 0.4),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? colors.link : null,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? colors.link : null,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.link),
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.link,
        thumbColor: colors.link,
      ),
      // Today's ring in the calendar; the chosen day stays a brand-red fill
      // with white on it.
      datePickerTheme: DatePickerThemeData(
        todayForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : states.contains(WidgetState.disabled)
              ? colors.link.withValues(alpha: 0.38)
              : colors.link,
        ),
        todayBorder: BorderSide(color: colors.link),
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
