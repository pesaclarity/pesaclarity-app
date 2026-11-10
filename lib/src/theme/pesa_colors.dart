import 'package:flutter/material.dart';

import 'brand_tokens.dart';

/// Brand colours that have no slot in Material's [ColorScheme].
@immutable
class PesaColors extends ThemeExtension<PesaColors> {
  const PesaColors({
    required this.brandSoft,
    required this.link,
    required this.border,
    required this.textMuted,
    required this.success,
    required this.successText,
    required this.warning,
    required this.markBlue,
    required this.markPurple,
    required this.markTeal,
  });

  static const light = PesaColors(
    brandSoft: BrandTokens.brandSoft,
    link: BrandTokens.brandLink,
    border: BrandTokens.border,
    textMuted: BrandTokens.textMuted,
    success: BrandTokens.success,
    successText: BrandTokens.successText,
    warning: BrandTokens.warning,
    markBlue: BrandTokens.markBlue,
    markPurple: BrandTokens.markPurple,
    markTeal: BrandTokens.markTeal,
  );

  static const dark = PesaColors(
    brandSoft: BrandTokens.darkBrandSoft,
    link: BrandTokens.darkBrandLink,
    border: BrandTokens.darkBorder,
    textMuted: BrandTokens.darkTextMuted,
    success: BrandTokens.darkSuccess,
    successText: BrandTokens.darkSuccessText,
    warning: BrandTokens.darkWarning,
    markBlue: BrandTokens.darkMarkBlue,
    markPurple: BrandTokens.darkMarkPurple,
    markTeal: BrandTokens.darkMarkTeal,
  );

  final Color brandSoft;
  final Color link;
  final Color border;
  final Color textMuted;
  final Color success;
  final Color successText;
  final Color warning;

  /// Only for marking the parts of a message, each its own colour.
  final Color markBlue;
  final Color markPurple;
  final Color markTeal;

  /// A light fill behind good news, such as a matched payment.
  Color get successSoft => success.withValues(alpha: 0.10);

  /// A light fill behind something to check, such as an item running low.
  Color get warningSoft => warning.withValues(alpha: 0.12);

  static PesaColors of(BuildContext context) =>
      Theme.of(context).extension<PesaColors>()!;

  @override
  PesaColors copyWith({
    Color? brandSoft,
    Color? link,
    Color? border,
    Color? textMuted,
    Color? success,
    Color? successText,
    Color? warning,
    Color? markBlue,
    Color? markPurple,
    Color? markTeal,
  }) => PesaColors(
    brandSoft: brandSoft ?? this.brandSoft,
    link: link ?? this.link,
    border: border ?? this.border,
    textMuted: textMuted ?? this.textMuted,
    success: success ?? this.success,
    successText: successText ?? this.successText,
    warning: warning ?? this.warning,
    markBlue: markBlue ?? this.markBlue,
    markPurple: markPurple ?? this.markPurple,
    markTeal: markTeal ?? this.markTeal,
  );

  @override
  PesaColors lerp(PesaColors? other, double t) {
    if (other == null) return this;
    return PesaColors(
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      link: Color.lerp(link, other.link, t)!,
      border: Color.lerp(border, other.border, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      successText: Color.lerp(successText, other.successText, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      markBlue: Color.lerp(markBlue, other.markBlue, t)!,
      markPurple: Color.lerp(markPurple, other.markPurple, t)!,
      markTeal: Color.lerp(markTeal, other.markTeal, t)!,
    );
  }
}
