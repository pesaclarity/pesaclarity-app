import 'package:flutter/services.dart';
import 'package:pesaclarity/src/theme/brand_tokens.dart';

/// Loads the app's bundled fonts in place of the test font, whose every
/// glyph is a square, so text takes the widths it takes on a phone.
Future<void> loadAppFonts() async {
  for (final (family, file) in [
    (BrandTokens.displayFont, 'SpaceGrotesk-Variable.ttf'),
    (BrandTokens.bodyFont, 'Inter-Variable.ttf'),
  ]) {
    await (FontLoader(
      family,
    )..addFont(rootBundle.load('assets/fonts/$file'))).load();
  }
}
