import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/security/data/device_integrity_checker.dart';
import 'package:pesaclarity/src/features/security/domain/device_integrity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/device_integrity');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void answer(Object? Function(MethodCall call) handler) => messenger
      .setMockMethodCallHandler(channel, (call) async => handler(call));

  group('DeviceIntegrityReport.fromPlatform', () {
    test('a clean phone', () {
      final report = DeviceIntegrityReport.fromPlatform({
        'suBinary': false,
        'testKeys': false,
        'appDebuggable': false,
      }, releaseBuild: true);
      expect(report.looksModified, isFalse);
    });

    test('su or test keys look modified', () {
      expect(
        DeviceIntegrityReport.fromPlatform({
          'suBinary': true,
        }, releaseBuild: true).looksModified,
        isTrue,
      );
      expect(
        DeviceIntegrityReport.fromPlatform({
          'testKeys': true,
        }, releaseBuild: false).looksModified,
        isTrue,
      );
    });

    test('debuggable counts only in a release build', () {
      final values = {'appDebuggable': true};
      expect(
        DeviceIntegrityReport.fromPlatform(
          values,
          releaseBuild: true,
        ).debuggableRelease,
        isTrue,
      );
      expect(
        DeviceIntegrityReport.fromPlatform(
          values,
          releaseBuild: false,
        ).looksModified,
        isFalse,
      );
    });
  });

  group('MethodChannelDeviceIntegrityChecker', () {
    const checker = MethodChannelDeviceIntegrityChecker(
      channel: channel,
      releaseBuild: true,
    );

    test('reads the platform answer', () async {
      answer(
        (call) => call.method == 'check'
            ? {'suBinary': true, 'testKeys': false, 'appDebuggable': false}
            : null,
      );
      final report = await checker.check();
      expect(report.suBinary, isTrue);
      expect(report.looksModified, isTrue);
    });

    test('a missing or failing channel reads as clean', () async {
      expect((await checker.check()).looksModified, isFalse);
      answer((_) => throw PlatformException(code: 'boom'));
      expect((await checker.check()).looksModified, isFalse);
    });
  });
}
