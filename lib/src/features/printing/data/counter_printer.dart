import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A Bluetooth printer paired with the phone.
class PairedPrinter {
  const PairedPrinter({required this.name, required this.address});

  final String name;
  final String address;
}

/// Small Bluetooth receipt printers at the counter: the ones paired with
/// the phone, and sending a slip to one.
abstract interface class CounterPrinters {
  /// Whether this phone can print on one: Android with Bluetooth.
  Future<bool> supported();

  /// Whether the app may talk to paired devices; asks when [ask].
  Future<bool> access({bool ask = false});

  Future<List<PairedPrinter>> paired();

  /// Sends [bytes] to the printer at [address]. Throws when it can't.
  Future<void> print(String address, Uint8List bytes);

  /// Opens the phone's Bluetooth settings, to pair a printer.
  Future<void> openSettings();
}

class ChannelCounterPrinters implements CounterPrinters {
  const ChannelCounterPrinters();

  static const _channel = MethodChannel('com.pesaclarity.app/printer');

  @override
  Future<bool> supported() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('supported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> access({bool ask = false}) async =>
      await _channel.invokeMethod<bool>(ask ? 'requestAccess' : 'access') ??
      false;

  @override
  Future<List<PairedPrinter>> paired() async {
    final rows =
        await _channel.invokeListMethod<Map<Object?, Object?>>('paired') ??
        const [];
    return [
      for (final row in rows)
        PairedPrinter(name: '${row['name']}', address: '${row['address']}'),
    ];
  }

  @override
  Future<void> print(String address, Uint8List bytes) => _channel
      .invokeMethod<void>('print', {'address': address, 'bytes': bytes});

  @override
  Future<void> openSettings() => _channel.invokeMethod<void>('openSettings');
}

final counterPrintersProvider = Provider<CounterPrinters>(
  (ref) => const ChannelCounterPrinters(),
);
