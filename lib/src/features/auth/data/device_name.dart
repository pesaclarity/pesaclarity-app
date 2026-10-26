import 'package:flutter/services.dart';

/// Names this phone in the account's device list, such as "Tecno Spark 20".
abstract interface class DeviceNameSource {
  Future<String> deviceName();
}

/// Reads the maker and model from Android, falling back to a generic name.
class PlatformDeviceNameSource implements DeviceNameSource {
  const PlatformDeviceNameSource([
    this._channel = const MethodChannel('com.pesaclarity.app/device'),
  ]);

  final MethodChannel _channel;

  static const fallback = 'Android phone';

  @override
  Future<String> deviceName() async {
    try {
      return cleanDeviceName(await _channel.invokeMethod<String>('name'));
    } on PlatformException {
      return fallback;
    } on MissingPluginException {
      return fallback;
    }
  }
}

/// Trims [raw] to the server's 1 to 64 characters, or returns the fallback.
String cleanDeviceName(String? raw) {
  final name = (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.isEmpty) return PlatformDeviceNameSource.fallback;
  return name.length > 64 ? name.substring(0, 64).trimRight() : name;
}
