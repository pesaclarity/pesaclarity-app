import 'dart:typed_data';

import 'package:pesaclarity/src/features/printing/data/counter_printer.dart';

/// Counter printers in memory: records what was sent to which printer.
class FakeCounterPrinters implements CounterPrinters {
  FakeCounterPrinters({
    this.isSupported = true,
    this.allowed = true,
    this.printers = const [
      PairedPrinter(name: 'Counter printer', address: '00:00:00:00:00:01'),
      PairedPrinter(name: 'Store printer', address: '00:00:00:00:00:02'),
    ],
    this.fails = false,
  });

  bool isSupported;
  bool allowed;
  List<PairedPrinter> printers;
  bool fails;
  final sent = <(String, Uint8List)>[];
  var settingsOpened = 0;

  @override
  Future<bool> supported() async => isSupported;

  @override
  Future<bool> access({bool ask = false}) async {
    if (ask) allowed = true;
    return allowed;
  }

  @override
  Future<List<PairedPrinter>> paired() async => printers;

  @override
  Future<void> print(String address, Uint8List bytes) async {
    if (fails) throw StateError('out of reach');
    sent.add((address, bytes));
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}
