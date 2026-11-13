import 'package:flutter/material.dart';

import 'brand_tokens.dart';
import 'layout.dart';

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
    required this.selected,
    required this.field,
    required this.floating,
    required this.shadow,
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
    selected: BrandTokens.selected,
    field: BrandTokens.surface,
    floating: BrandTokens.surface,
    shadow: BrandTokens.shadow,
  );

  /// [light] for the phone's high-contrast setting.
  static final lightHighContrast = light.copyWith(
    link: BrandTokens.hcText,
    border: BrandTokens.hcBorder,
    textMuted: BrandTokens.hcTextMuted,
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
    selected: BrandTokens.darkSelected,
    field: BrandTokens.darkField,
    floating: BrandTokens.darkFloating,
    // No shadows in dark: the floating surface is lighter instead.
    shadow: BrandTokens.darkShadow,
  );

  /// [dark] for the phone's high-contrast setting.
  static final darkHighContrast = dark.copyWith(
    link: BrandTokens.darkHcText,
    border: BrandTokens.darkHcBorder,
    textMuted: BrandTokens.darkHcTextMuted,
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

  /// A selected chip or menu choice: a neutral tint.
  final Color selected;

  /// The fill of a chip or a field, a step above a card in dark.
  final Color field;

  /// Parts that float over the page: the tab bar, sheets, menus, popups.
  final Color floating;

  /// The shadow under [floating] parts; clear in dark.
  final Color shadow;

  /// The Material elevation of a floating part: none in dark.
  double get floatingElevation => shadow.a == 0 ? 0 : Layout.floatingElevation;

  /// A soft shadow for a floating part, or none in dark.
  List<BoxShadow> get floatingShadow => shadow.a == 0
      ? const []
      : [
          BoxShadow(
            color: shadow,
            blurRadius: Layout.shadowBlur,
            offset: const Offset(0, Layout.shadowDrop),
          ),
        ];

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
    Color? selected,
    Color? field,
    Color? floating,
    Color? shadow,
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
    selected: selected ?? this.selected,
    field: field ?? this.field,
    floating: floating ?? this.floating,
    shadow: shadow ?? this.shadow,
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
      selected: Color.lerp(selected, other.selected, t)!,
      field: Color.lerp(field, other.field, t)!,
      floating: Color.lerp(floating, other.floating, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}
