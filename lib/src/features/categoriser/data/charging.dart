import 'package:flutter/services.dart';

/// Whether the phone is charging, from the platform. False when it cannot
/// tell, so learning waits rather than running on battery.
class PlatformChargingSource {
  const PlatformChargingSource([
    this._channel = const MethodChannel('com.pesaclarity.app/device'),
  ]);

  final MethodChannel _channel;

  Future<bool> isCharging() async {
    try {
      return await _channel.invokeMethod<bool>('charging') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
