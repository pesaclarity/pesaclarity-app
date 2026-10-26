import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/device_integrity.dart';

/// Looks for signs of a rooted phone or a tampered build.
abstract interface class DeviceIntegrityChecker {
  Future<DeviceIntegrityReport> check();
}

/// Asks the Android side over a method channel. Any failure reads as
/// [DeviceIntegrityReport.clean], since the result is only a warning.
class MethodChannelDeviceIntegrityChecker implements DeviceIntegrityChecker {
  const MethodChannelDeviceIntegrityChecker({
    this.channel = const MethodChannel('com.pesaclarity.app/device_integrity'),
    this.releaseBuild = kReleaseMode,
  });

  final MethodChannel channel;
  final bool releaseBuild;

  @override
  Future<DeviceIntegrityReport> check() async {
    try {
      final values = await channel.invokeMapMethod<Object?, Object?>('check');
      if (values == null) return DeviceIntegrityReport.clean;
      return DeviceIntegrityReport.fromPlatform(
        values,
        releaseBuild: releaseBuild,
      );
    } on PlatformException {
      return DeviceIntegrityReport.clean;
    } on MissingPluginException {
      return DeviceIntegrityReport.clean;
    }
  }
}
