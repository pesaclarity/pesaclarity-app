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
  // A Bluetooth receipt printer at the counter (business spaces).
  'android.permission.BLUETOOTH',
  'android.permission.BLUETOOTH_CONNECT',
  // Scanning a shared space's join request or invite (decision 0031):
  // only while the scanner is open, with a file as the fallback.
  'android.permission.CAMERA',
};

/// Asked for by the camera plugin, never used, and removed from the
/// merged manifest.
const _removed = {
  'android.permission.RECORD_AUDIO',
  'android.permission.WRITE_EXTERNAL_STORAGE',
};

Set<String> _permissionsIn(String path, {bool removed = false}) {
  final xml = File(path).readAsStringSync();
  return RegExp(r'<uses-permission[^>]*>')
      .allMatches(xml)
      .map((m) => m.group(0)!)
      .where((tag) => tag.contains('tools:node="remove"') == removed)
      .map(
        (tag) => RegExp(r'android:name="([^"]+)"').firstMatch(tag)!.group(1)!,
      )
      .toSet();
}

void main() {
  test('the main manifest asks only for the allowed permissions', () {
    expect(
      _permissionsIn('android/app/src/main/AndroidManifest.xml'),
      _allowed,
    );
  });

  test("the camera plugin's microphone and storage are removed", () {
    expect(
      _permissionsIn('android/app/src/main/AndroidManifest.xml', removed: true),
      _removed,
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
