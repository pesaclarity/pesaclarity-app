import 'package:flutter/painting.dart';

/// Colour and shape values from the brand tokens
/// (https://github.com/pesaclarity/docs, `brand/tokens.json`).
///
/// `test/fixtures/brand/tokens.json` is a copy of that file, and
/// `test/theme/brand_tokens_test.dart` fails if a value here differs from
/// it. When the brand tokens change, copy the new file and update these.
abstract final class BrandTokens {
  static const brand = Color(0xFFC8102E);
  static const brandLink = Color(0xFFB81D2F);
  static const brandSoft = Color(0xFFFDECEE);
  static const background = Color(0xFFFBF8F8);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFEFE6E7);
  static const text = Color(0xFF1C1215);
  static const textMuted = Color(0xFF6F6064);
  static const success = Color(0xFF059669);
  static const successText = Color(0xFF047857);
  static const warning = Color(0xFFB45309);
  static const danger = Color(0xFFC8102E);
  static const onBrand = Color(0xFFFFFFFF);

  static const darkBackground = Color(0xFF1A1214);
  static const darkSurface = Color(0xFF251B1E);
  static const darkBorder = Color(0xFF3D2E32);
  static const darkText = Color(0xFFEDE4E6);
  static const darkTextMuted = Color(0xFFB3A5A9);
  static const darkBrand = Color(0xFFFF6B7A);
  static const darkOnBrand = Color(0xFF1A1214);
  static const darkBrandLink = Color(0xFFFF8592);
  static const darkBrandSoft = Color(0xFF3A1D23);
  static const darkSuccess = Color(0xFF34D399);
  static const darkSuccessText = Color(0xFF6EE7B7);
  static const darkWarning = Color(0xFFFBBF24);
  static const darkDanger = Color(0xFFFF6B7A);

  static const cardRadius = 24.0;

  /// Corner radius of grouped lists, buttons and sheets on iPhone, as in
  /// Apple's own apps. Not part of the brand tokens file.
  static const iosRadius = 12.0;
  static const pillRadius = 999.0;
  static const touchTarget = 44.0;

  static const displayFont = 'SpaceGrotesk';
  static const bodyFont = 'Inter';
}
