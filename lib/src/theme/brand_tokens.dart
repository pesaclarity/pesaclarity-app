import 'package:flutter/painting.dart';

/// Colour and shape values from the brand tokens
/// (https://github.com/pesaclarity/docs, `brand/tokens.json`).
///
/// `test/fixtures/brand/tokens.json` is a copy of that file, and
/// `test/theme/brand_tokens_test.dart` fails if a value here differs from
/// it. When the brand tokens change, copy the new file and update these.
abstract final class BrandTokens {
  static const brand = Color(0xFFC8102E);
  static const brandLink = Color(0xFFC8102E);
  static const brandSoft = Color(0xFFEBEBEB);
  static const background = Color(0xFFF5F5F5);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E5E5);
  static const text = Color(0xFF171717);
  static const textMuted = Color(0xFF525252);
  static const success = Color(0xFF059669);
  static const successText = Color(0xFF047857);
  static const warning = Color(0xFFB45309);
  static const danger = Color(0xFFC8102E);

  /// Danger in small text, such as a destructive button's label or a
  /// field's error. The same red as [danger] in light.
  static const dangerText = Color(0xFFC8102E);

  /// The worse of two warnings, such as a struggling health score beside a
  /// coping one in [warning]: a deeper orange, kept clear of brand red.
  static const warningStrong = Color(0xFFC2410C);
  static const onBrand = Color(0xFFFFFFFF);

  /// Only for marking the parts of a message: who, the balance, the fee.
  static const markBlue = Color(0xFF1D4ED8);
  static const markPurple = Color(0xFF6D28D9);
  static const markTeal = Color(0xFF0F766E);

  /// A selected chip or menu choice: a neutral tint, so red stays for the
  /// lead card and the main action.
  static const selected = Color(0xFFEBEBEB);

  /// Soft shadow under floating parts (the tab bar, sheets, menus) in light
  /// only; dark uses a lighter surface instead.
  static const shadow = Color(0x14000000);

  /// Stronger text and edges for the phone's high-contrast setting.
  static const hcText = Color(0xFF0A0A0A);
  static const hcTextMuted = Color(0xFF404040);
  static const hcBorder = Color(0xFFC4C4C4);

  /// Dark surfaces climb a gentle ladder of neutral near-blacks: page, card,
  /// chip or field, then floating parts (tab bar, sheets, menus).
  static const darkBackground = Color(0xFF0A0A0A);
  static const darkSurface = Color(0xFF171717);
  static const darkField = Color(0xFF1F1F1F);
  static const darkFloating = Color(0xFF242424);
  static const darkBorder = Color(0xFF2E2E2E);

  /// Moderate rather than maximal contrast (both pass 4.5:1), easier on
  /// eyes with astigmatism or light sensitivity.
  static const darkText = Color(0xFFE5E5E5);
  static const darkTextMuted = Color(0xFFA3A3A3);

  /// The same red as light, with white text on it.
  static const darkBrand = Color(0xFFC8102E);
  static const darkOnBrand = Color(0xFFFFFFFF);
  static const darkBrandLink = Color(0xFFFF4D6A);

  /// A soft neutral tint, never pink.
  static const darkBrandSoft = Color(0xFF262626);
  static const darkSuccess = Color(0xFF34D399);
  static const darkSuccessText = Color(0xFF6EE7B7);
  static const darkWarning = Color(0xFFFBBF24);
  static const darkWarningStrong = Color(0xFFFB923C);

  /// Danger in dark is brand red too, for fills and large figures (3.0:1
  /// on a card, 3.4:1 on the page).
  static const darkDanger = Color(0xFFC8102E);

  /// The same hue as brand red, brightened only as far as small text needs:
  /// 4.8:1 on a sheet, 5.6:1 on a card, 6.2:1 on the page.
  static const darkDangerText = Color(0xFFFF4D6A);
  static const darkMarkBlue = Color(0xFF60A5FA);
  static const darkMarkPurple = Color(0xFFA78BFA);
  static const darkMarkTeal = Color(0xFF2DD4BF);
  static const darkSelected = Color(0xFF383838);
  static const darkShadow = Color(0x00000000);

  static const darkHcText = Color(0xFFF5F5F5);
  static const darkHcTextMuted = Color(0xFFCCCCCC);
  static const darkHcBorder = Color(0xFF525252);

  static const cardRadius = 20.0;

  /// Corner of a boxed text field.
  static const fieldRadius = 12.0;

  static const pillRadius = 999.0;
  static const touchTarget = 44.0;

  static const displayFont = 'SpaceGrotesk';
  static const bodyFont = 'Inter';
}
