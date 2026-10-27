import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';
import 'package:pesaclarity/src/theme/brand_tokens.dart';
import 'package:pesaclarity/src/theme/pesa_colors.dart';

/// `test/fixtures/brand/tokens.json` is a copy of `brand/tokens.json` in
/// pesaclarity/docs. Every colour there must match the app's.
void main() {
  final tokens = jsonDecode(
    File('test/fixtures/brand/tokens.json').readAsStringSync(),
  ) as Map<String, Object?>;

  Color token(String group, String name) {
    final entry = (tokens[group]! as Map<String, Object?>)[name];
    final hex = (entry! as Map<String, Object?>)[r'$value']! as String;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  test('light colours match the brand tokens', () {
    final app = {
      'brand': BrandTokens.brand,
      'brandLink': BrandTokens.brandLink,
      'brandSoft': BrandTokens.brandSoft,
      'background': BrandTokens.background,
      'surface': BrandTokens.surface,
      'border': BrandTokens.border,
      'text': BrandTokens.text,
      'textMuted': BrandTokens.textMuted,
      'success': BrandTokens.success,
      'successText': BrandTokens.successText,
      'warning': BrandTokens.warning,
      'danger': BrandTokens.danger,
    };
    final names = (tokens['color']! as Map<String, Object?>).keys.toSet();
    expect(app.keys.toSet(), names, reason: 'every light token is used');
    for (final MapEntry(key: name, value: color) in app.entries) {
      expect(color, token('color', name), reason: name);
    }
  });

  test('dark colours match the brand tokens', () {
    final app = {
      'background': BrandTokens.darkBackground,
      'surface': BrandTokens.darkSurface,
      'border': BrandTokens.darkBorder,
      'text': BrandTokens.darkText,
      'textMuted': BrandTokens.darkTextMuted,
      'brand': BrandTokens.darkBrand,
      'onBrand': BrandTokens.darkOnBrand,
      'brandLink': BrandTokens.darkBrandLink,
      'brandSoft': BrandTokens.darkBrandSoft,
      'success': BrandTokens.darkSuccess,
      'successText': BrandTokens.darkSuccessText,
      'warning': BrandTokens.darkWarning,
      'danger': BrandTokens.darkDanger,
    };
    final names = (tokens['dark']! as Map<String, Object?>).keys.toSet();
    expect(app.keys.toSet(), names, reason: 'every dark token is used');
    for (final MapEntry(key: name, value: color) in app.entries) {
      expect(color, token('dark', name), reason: name);
    }
  });

  test('the dark theme uses the dark link, success text and danger', () {
    final theme = AppTheme.dark;
    final colors = theme.extension<PesaColors>()!;
    expect(colors.link, token('dark', 'brandLink'));
    expect(colors.successText, token('dark', 'successText'));
    expect(colors.brandSoft, token('dark', 'brandSoft'));
    expect(colors.border, token('dark', 'border'));
    expect(colors.warning, token('dark', 'warning'));
    expect(theme.colorScheme.error, token('dark', 'danger'));
    expect(theme.colorScheme.onPrimary, token('dark', 'onBrand'));
  });

  test('shapes and fonts match the brand tokens', () {
    final radius = tokens['radius']! as Map<String, Object?>;
    String value(Map<String, Object?> group, String name) =>
        (group[name]! as Map<String, Object?>)[r'$value']! as String;
    expect('${BrandTokens.cardRadius.toInt()}px', value(radius, 'card'));
    expect('${BrandTokens.pillRadius.toInt()}px', value(radius, 'pill'));
    final size = tokens['size']! as Map<String, Object?>;
    expect('${BrandTokens.touchTarget.toInt()}px', value(size, 'touchTarget'));
  });
}
