import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every permission the release app asks for. Adding one is a privacy
/// decision: update the spec, the privacy policy and the Play forms first.
const _allowed = {
  'android.permission.INTERNET',
  'android.permission.READ_SMS',
  'android.permission.RECEIVE_SMS',
  'android.permission.POST_NOTIFICATIONS',
  'android.permission.RECEIVE_BOOT_COMPLETED',
};

Set<String> _permissionsIn(String path) {
  final xml = File(path).readAsStringSync();
  return RegExp(r'<uses-permission[^>]*android:name="([^"]+)"')
      .allMatches(xml)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  test('the main manifest asks only for the allowed permissions', () {
    expect(
      _permissionsIn('android/app/src/main/AndroidManifest.xml'),
      _allowed,
    );
  });

  test('flavour manifests add no permissions', () {
    for (final flavour in ['play', 'foss']) {
      final path = 'android/app/src/$flavour/AndroidManifest.xml';
      if (!File(path).existsSync()) continue;
      expect(_permissionsIn(path), isEmpty, reason: path);
    }
  });
}
