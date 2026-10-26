import 'package:flutter/material.dart';

import 'brand_tokens.dart';

/// Text styles: Space Grotesk with tabular figures for numbers and titles,
/// Inter for body text and labels. Both ship as bundled variable fonts.
abstract final class AppTypography {
  static TextTheme textTheme(Color text, Color muted) => TextTheme(
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
