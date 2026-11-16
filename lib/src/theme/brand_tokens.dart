import 'package:flutter/painting.dart';

/// Colour and shape values from the brand tokens
/// (https://github.com/pesaclarity/docs, `brand/tokens.json`).
///
/// `test/fixtures/brand/tokens.json` is a copy of that file, and
/// `test/theme/brand_tokens_test.dart` fails if a value here differs from
/// it. When the brand tokens change, copy the new file and update these.
abstract final class BrandTokens {
  static const brand = Color(0xFFC8102E);
  static const brandLink = Color(0xFF1C1215);
  static const brandSoft = Color(0xFFFDECEE);
  static const background = Color(0xFFF6F1EE);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFEFE6E7);
  static const text = Color(0xFF1C1215);
  static const textMuted = Color(0xFF6F6064);
  static const success = Color(0xFF059669);
  static const successText = Color(0xFF047857);
  static const warning = Color(0xFFB45309);
  static const danger = Color(0xFFC8102E);
  static const onBrand = Color(0xFFFFFFFF);

  /// The label and caption on a red card: white, softened (88%).
  static const onBrandSoft = Color(0xE0FFFFFF);

  /// Only for marking the parts of a message: who, the balance, the fee.
  static const markBlue = Color(0xFF1D4ED8);
  static const markPurple = Color(0xFF6D28D9);
  static const markTeal = Color(0xFF0F766E);

  /// A selected chip or menu choice: a neutral tint, so red stays for the
  /// lead card and the main action.
  static const selected = Color(0xFFECE4E1);

  /// Soft shadow under floating parts (the tab bar, sheets, menus) in light
  /// only; dark uses a lighter surface instead.
  static const shadow = Color(0x141C1215);

  /// Stronger text and edges for the phone's high-contrast setting.
  static const hcText = Color(0xFF120A0D);
  static const hcTextMuted = Color(0xFF4F4246);
  static const hcBorder = Color(0xFFCDBFC2);

  /// Dark surfaces climb a gentle ladder of warm near-blacks: page, card,
  /// chip or field, then floating parts (tab bar, sheets, menus).
  static const darkBackground = Color(0xFF140E10);
  static const darkSurface = Color(0xFF1E1618);
  static const darkField = Color(0xFF241B1E);
  static const darkFloating = Color(0xFF2A2124);
  static const darkBorder = Color(0xFF352B2E);

  /// Moderate rather than maximal contrast (both pass 4.5:1), easier on
  /// eyes with astigmatism or light sensitivity.
  static const darkText = Color(0xFFE3D9DB);
  static const darkTextMuted = Color(0xFFA3969A);

  /// The same red as light, with white text on it.
  static const darkBrand = Color(0xFFC8102E);
  static const darkOnBrand = Color(0xFFFFFFFF);
  static const darkBrandLink = Color(0xFFE3D9DB);
  static const darkBrandSoft = Color(0xFF33272A);
  static const darkSuccess = Color(0xFF34D399);
  static const darkSuccessText = Color(0xFF6EE7B7);
  static const darkWarning = Color(0xFFFBBF24);
  static const darkDanger = Color(0xFFFF6B7A);
  static const darkMarkBlue = Color(0xFF60A5FA);
  static const darkMarkPurple = Color(0xFFA78BFA);
  static const darkMarkTeal = Color(0xFF2DD4BF);
  static const darkSelected = Color(0xFF3A2F32);
  static const darkShadow = Color(0x00000000);

  static const darkHcText = Color(0xFFF5EEF0);
  static const darkHcTextMuted = Color(0xFFCFC3C6);
  static const darkHcBorder = Color(0xFF5A4A4F);

  static const cardRadius = 20.0;

  /// Corner of a boxed text field.
  static const fieldRadius = 12.0;

  static const pillRadius = 999.0;
  static const touchTarget = 44.0;

  static const displayFont = 'SpaceGrotesk';
  static const bodyFont = 'Inter';
}
