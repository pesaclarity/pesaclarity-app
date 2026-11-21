import 'package:flutter/material.dart';

import 'brand_tokens.dart';

/// Brand colours that have no slot in Material's [ColorScheme].
///
/// The app is grey and red only, on plain backgrounds: no tints, no shades
/// and no shadows. Red is for the main action, what is chosen and real
/// problems; everything else is the text colour or the muted grey, and
/// parts are told apart by a thin [border].
@immutable
class PesaColors extends ThemeExtension<PesaColors> {
  const PesaColors({
    required this.link,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.danger,
    required this.markBlue,
    required this.markPurple,
    required this.markTeal,
    required this.isDark,
  });

  static const light = PesaColors(
    link: BrandTokens.brandLink,
    border: BrandTokens.border,
    text: BrandTokens.text,
    textMuted: BrandTokens.textMuted,
    danger: BrandTokens.danger,
    markBlue: BrandTokens.markBlue,
    markPurple: BrandTokens.markPurple,
    markTeal: BrandTokens.markTeal,
    isDark: false,
  );

  /// [light] for the phone's high-contrast setting.
  static final lightHighContrast = light.copyWith(
    border: BrandTokens.hcBorder,
    text: BrandTokens.hcText,
    textMuted: BrandTokens.hcTextMuted,
  );

  static const dark = PesaColors(
    link: BrandTokens.darkBrandLink,
    border: BrandTokens.darkBorder,
    text: BrandTokens.darkText,
    textMuted: BrandTokens.darkTextMuted,
    danger: BrandTokens.darkDanger,
    markBlue: BrandTokens.darkMarkBlue,
    markPurple: BrandTokens.darkMarkPurple,
    markTeal: BrandTokens.darkMarkTeal,
    isDark: true,
  );

  /// [dark] for the phone's high-contrast setting.
  static final darkHighContrast = dark.copyWith(
    border: BrandTokens.darkHcBorder,
    text: BrandTokens.darkHcText,
    textMuted: BrandTokens.darkHcTextMuted,
  );

  /// Red that reads on the plain background: a link, the current tab, a
  /// chosen option, a focused field, and a real problem.
  final Color link;
  final Color border;

  /// The body text colour, the colorScheme's `onSurface`.
  final Color text;
  final Color textMuted;

  /// A destructive button's fill: brand red in light and dark, with white
  /// text on it. Red text, including a large figure below zero, takes the
  /// colour scheme's `error`, and a red edge takes [link]; dark brightens
  /// both to read on the dark background.
  final Color danger;

  /// Only for marking the parts of a message, each its own colour.
  final Color markBlue;
  final Color markPurple;
  final Color markTeal;

  final bool isDark;

  /// Good news, money in, done: plain text, never green. Say it in words
  /// or with a ✓ or a "+", not with a colour.
  Color get good => text;

  /// A real problem: over the plan, overdue, tax past due, running low,
  /// below zero. The link red, on the plain background.
  Color get problem => link;

  /// Muted small print (12 px) where [textMuted] measures under 4.5:1, such
  /// as a note under a button or a list: [textMuted] taken 45% of the way
  /// to [text], the body text colour.
  Color mutedSmall(Color text) => Color.lerp(textMuted, text, 0.45)!;

  /// The colours of a chart's series, told apart by lightness: five greys
  /// from the text colour down, darkest first. Red is kept for a series
  /// that is a problem, such as spending over the plan.
  List<Color> get chartGreys => isDark
      ? const [
          BrandTokens.darkText,
          Color(0xFFA3A3A3),
          Color(0xFF777777),
          Color(0xFF505050),
          Color(0xFF333333),
        ]
      : const [
          BrandTokens.text,
          Color(0xFF525252),
          Color(0xFF7A7A7A),
          Color(0xFFA3A3A3),
          Color(0xFFCCCCCC),
        ];

  static PesaColors of(BuildContext context) =>
      Theme.of(context).extension<PesaColors>()!;

  @override
  PesaColors copyWith({
    Color? link,
    Color? border,
    Color? text,
    Color? textMuted,
    Color? danger,
    Color? markBlue,
    Color? markPurple,
    Color? markTeal,
    bool? isDark,
  }) => PesaColors(
    link: link ?? this.link,
    border: border ?? this.border,
    text: text ?? this.text,
    textMuted: textMuted ?? this.textMuted,
    danger: danger ?? this.danger,
    markBlue: markBlue ?? this.markBlue,
    markPurple: markPurple ?? this.markPurple,
    markTeal: markTeal ?? this.markTeal,
    isDark: isDark ?? this.isDark,
  );

  @override
  PesaColors lerp(PesaColors? other, double t) {
    if (other == null) return this;
    return PesaColors(
      link: Color.lerp(link, other.link, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      markBlue: Color.lerp(markBlue, other.markBlue, t)!,
      markPurple: Color.lerp(markPurple, other.markPurple, t)!,
      markTeal: Color.lerp(markTeal, other.markTeal, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}
