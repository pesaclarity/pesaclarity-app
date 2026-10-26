import 'package:flutter/painting.dart';

/// Colour and shape values from the brand tokens
/// (https://github.com/pesaclarity/docs, `brand/tokens.json`).
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
  static const darkText = Color(0xFFEDE4E6);
  static const darkTextMuted = Color(0xFFB3A5A9);
  static const darkBrand = Color(0xFFFF6B7A);

  // Not yet in tokens.json; chosen to keep contrast on the dark surface.
  // TODO(docs): add these dark values to brand/tokens.json.
  static const darkBrandSoft = Color(0xFF3D2228);
  static const darkBorder = Color(0xFF3A2C30);
  static const darkSuccess = Color(0xFF34D399);
  static const darkWarning = Color(0xFFF59E0B);
  static const darkOnBrand = Color(0xFF1A1214);

  static const cardRadius = 24.0;
  static const pillRadius = 999.0;
  static const touchTarget = 44.0;

  static const displayFont = 'SpaceGrotesk';
  static const bodyFont = 'Inter';
}
