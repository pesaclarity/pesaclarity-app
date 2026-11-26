import 'package:flutter/services.dart';

/// What the phone can tell about running and fetching a model.
abstract interface class AskModelDevice {
  /// The phone's memory in bytes, or null when unknown.
  Future<int?> memoryBytes();

  /// Free space where [directory] is, in bytes, or null when unknown.
  Future<int?> freeBytes(String directory);

  /// Whether the phone is on Wi-Fi or another network that is not metered.
  Future<bool> onUnmeteredNetwork();

  /// Keeps [path] out of the phone's own backups (iCloud on iPhone; Android
  /// already leaves every app file out).
  Future<void> excludeFromBackup(String path);
}

/// [AskModelDevice] through `com.pesaclarity.app/device`. Anything the
/// platform cannot say counts as unknown, so no model is offered.
class PlatformAskModelDevice implements AskModelDevice {
  const PlatformAskModelDevice([
    this._channel = const MethodChannel('com.pesaclarity.app/device'),
  ]);

  final MethodChannel _channel;

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<int?> memoryBytes() => _call<int>('memory');

  @override
  Future<int?> freeBytes(String directory) =>
      _call<int>('freeSpace', directory);

  @override
  Future<bool> onUnmeteredNetwork() async =>
      await _call<bool>('unmetered') ?? false;

  @override
  Future<void> excludeFromBackup(String path) =>
      _call<bool>('excludeFromBackup', path);
}
