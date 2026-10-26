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
  });

  static const light = PesaColors(
    brandSoft: BrandTokens.brandSoft,
    link: BrandTokens.brandLink,
    border: BrandTokens.border,
    textMuted: BrandTokens.textMuted,
    success: BrandTokens.success,
    successText: BrandTokens.successText,
    warning: BrandTokens.warning,
  );

  static const dark = PesaColors(
    brandSoft: BrandTokens.darkBrandSoft,
    link: BrandTokens.darkBrand,
    border: BrandTokens.darkBorder,
    textMuted: BrandTokens.darkTextMuted,
    success: BrandTokens.darkSuccess,
    successText: BrandTokens.darkSuccess,
    warning: BrandTokens.darkWarning,
  );

  final Color brandSoft;
  final Color link;
  final Color border;
  final Color textMuted;
  final Color success;
  final Color successText;
  final Color warning;

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
  }) => PesaColors(
    brandSoft: brandSoft ?? this.brandSoft,
    link: link ?? this.link,
    border: border ?? this.border,
    textMuted: textMuted ?? this.textMuted,
    success: success ?? this.success,
    successText: successText ?? this.successText,
    warning: warning ?? this.warning,
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
    );
  }
}
