import 'package:flutter/material.dart';

import 'brand_tokens.dart';

/// Text styles: Space Grotesk with tabular figures for numbers and titles,
/// Inter for body text and labels. Both ship as bundled variable fonts.
///
/// On iPhone, titles and body text use the system font at iOS sizes; only
/// figures keep Space Grotesk.
abstract final class AppTypography {
  static TextTheme textTheme(Color text, Color muted, {bool ios = false}) =>
      ios ? _ios(text, muted) : _android(text, muted);

  static TextTheme _android(Color text, Color muted) => TextTheme(
    displayLarge: _display(57, FontWeight.w600, text, height: 1.1),
    displayMedium: _display(45, FontWeight.w600, text, height: 1.1),
    displaySmall: _display(36, FontWeight.w600, text, height: 1.15),
    headlineLarge: _display(32, FontWeight.w600, text),
    headlineMedium: _display(28, FontWeight.w600, text),
    headlineSmall: _display(24, FontWeight.w600, text),
    titleLarge: _display(22, FontWeight.w600, text),
    titleMedium: _body(16, FontWeight.w600, text),
    titleSmall: _body(14, FontWeight.w600, text),
    bodyLarge: _body(16, FontWeight.w400, text),
    bodyMedium: _body(14, FontWeight.w400, text),
    bodySmall: _body(12, FontWeight.w400, muted),
    labelLarge: _body(14, FontWeight.w600, text),
    labelMedium: _body(12, FontWeight.w500, text),
    labelSmall: _body(11, FontWeight.w500, muted),
  );

  // iOS text styles: Large Title 34, Title 1 28, Title 2 22, Title 3 20,
  // Headline 17 semibold, Body 17, Subheadline 15, Footnote 13, Caption 12.
  static TextTheme _ios(Color text, Color muted) => TextTheme(
    displayLarge: _display(57, FontWeight.w600, text, height: 1.1),
    displayMedium: _display(45, FontWeight.w600, text, height: 1.1),
    displaySmall: _display(36, FontWeight.w600, text, height: 1.15),
    headlineLarge: _system(34, FontWeight.w700, text, height: 1.2),
    headlineMedium: _system(28, FontWeight.w700, text, height: 1.2),
    headlineSmall: _system(22, FontWeight.w700, text, height: 1.25),
    titleLarge: _system(20, FontWeight.w600, text, height: 1.25),
    titleMedium: _system(17, FontWeight.w600, text),
    titleSmall: _system(15, FontWeight.w600, text),
    bodyLarge: _system(17, FontWeight.w400, text),
    bodyMedium: _system(15, FontWeight.w400, text),
    bodySmall: _system(13, FontWeight.w400, muted),
    labelLarge: _system(17, FontWeight.w600, text),
    labelMedium: _system(13, FontWeight.w500, text),
    labelSmall: _system(11, FontWeight.w500, muted),
  );

  /// The iPhone system font: left unnamed so the platform default applies.
  static TextStyle _system(
    double size,
    FontWeight weight,
    Color color, {
    double height = 1.3,
  }) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: color,
    letterSpacing: _tracking[size.round()] ?? 0,
  );

  /// Apple's tracking for the system font at each size, in points.
  static const _tracking = {
    34: 0.37,
    28: 0.36,
    22: 0.35,
    20: 0.38,
    17: -0.41,
    15: -0.24,
    13: -0.08,
    11: 0.07,
  };

  /// Style for a standalone amount, such as the hero "safe to spend" figure.
  static TextStyle amount({
    required double size,
    required Color color,
    FontWeight weight = FontWeight.w600,
  }) => _display(size, weight, color, height: 1.1);

  static TextStyle _display(
    double size,
    FontWeight weight,
    Color color, {
    double height = 1.2,
  }) => TextStyle(
    fontFamily: BrandTokens.displayFont,
    fontSize: size,
    fontWeight: weight,
    // Variable fonts need the weight axis set explicitly.
    fontVariations: [FontVariation.weight(weight.value.toDouble())],
    fontFeatures: const [FontFeature.tabularFigures()],
    height: height,
    color: color,
  );

  static TextStyle _body(double size, FontWeight weight, Color color) =>
      TextStyle(
        fontFamily: BrandTokens.bodyFont,
        fontSize: size,
        fontWeight: weight,
        fontVariations: [FontVariation.weight(weight.value.toDouble())],
        height: 1.4,
        color: color,
      );
}
