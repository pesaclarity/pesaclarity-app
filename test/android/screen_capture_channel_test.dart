import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/security/data/screen_capture_blocker.dart';

/// The Android side of "Allow screenshots and screen recording" does not run
/// in these tests, so they read its source: screenshots must be blocked
/// before any Dart code runs, and the channel must be the one Dart calls.
const _kotlin = 'android/app/src/main/kotlin/com/pesaclarity/app';

void main() {
  final activity = File('$_kotlin/MainActivity.kt').readAsStringSync();
  final channel = File('$_kotlin/ScreenCaptureChannel.kt').readAsStringSync();

  test('a cold start is blocked before the Flutter engine starts', () {
    final onCreate = RegExp(
      r'override fun onCreate\(.*?\n    \}\n',
      dotAll: true,
    ).firstMatch(activity)!.group(0)!;
    final blocked = onCreate.indexOf('WindowManager.LayoutParams.FLAG_SECURE');
    expect(blocked, isNonNegative, reason: 'onCreate sets FLAG_SECURE');
    expect(
      onCreate.indexOf('super.onCreate('),
      greaterThan(blocked),
      reason: 'before super.onCreate, which starts the engine',
    );
  });

  test('the activity sets the channel up and takes it down', () {
    expect(activity, contains('screenCapture = ScreenCaptureChannel(this, '));
    expect(activity, contains('screenCapture?.dispose()'));
  });

  test('the channel has the name and methods the Dart side calls', () {
    const dart = MethodChannelScreenCaptureBlocker();
    expect(
      channel,
      contains('MethodChannel(messenger, "${dart.channel.name}")'),
    );
    expect(channel, contains('"allow" ->'));
    expect(channel, contains('"block" ->'));
  });
}
