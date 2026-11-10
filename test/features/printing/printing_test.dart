import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/sales_repository.dart';
import 'package:pesaclarity/src/data/repositories/stock_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/close/presentation/close_day_screen.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/documents/application/document_providers.dart';
import 'package:pesaclarity/src/features/documents/presentation/receipt_sheet.dart';
import 'package:pesaclarity/src/features/printing/application/printing_providers.dart';
import 'package:pesaclarity/src/features/printing/data/counter_printer.dart';
import 'package:pesaclarity/src/features/printing/presentation/receipt_printer_screen.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/fake_printers.dart';
import '../../helpers/test_app.dart';

const _shop = Space(
  id: 'shop',
  name: 'Green Basket Grocers',
  kind: SpaceKind.business,
);

/// Printing on the counter printer and on the phone's printers (synthetic
/// data, no real printer).
void main() {
  late AppDatabase db;
  late FakeCounterPrinters printers;
  late List<String> phonePrints;
  final now = eat(2026, 11, 10, 14, 41);

  setUp(() async {
    db = openTestDatabase();
    printers = FakeCounterPrinters();
    phonePrints = [];
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'Cash',
            type: AccountType.cash,
            openingDate: eat(2026, 11, 1, 0),
          ),
        );
  });

  List<Override> overrides() => [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(() => now),
    activeSpaceProvider.overrideWithValue(_shop),
    deviceRegionProvider.overrideWithValue('KE'),
    counterPrintersProvider.overrideWithValue(printers),
    pdfPrinterProvider.overrideWithValue((pdf, name) async {
      phonePrints.add(name);
      return true;
    }),
    receiptRendererProvider.overrideWithValue(
      (r, {required initials, logo}) async => Uint8List.fromList([37, 80]),
    ),
  ];

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget Function(BuildContext context, ProviderContainer c) button,
  ) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(body: button(context, c)),
          ),
        ),
      ),
    );
    return c;
  }

  Future<int> sale(ProviderContainer c) async =>
      (await c
              .read(salesControllerProvider)
              .sell(
                [const SalePart(SalePaymentMethod.cash, 18000)],
                lines: const [
                  SaleLine(name: 'Kale', quantityMilli: 3000, totalMinor: 6000),
                  SaleLine(
                    name: 'Tomatoes',
                    quantityMilli: 1000,
                    totalMinor: 12000,
                  ),
                ],
              ))
          .saleId;

  Future<void> chooseCounterPrinter(ProviderContainer c) => c
      .read(printerSettingsProvider.notifier)
      .save(
        const PrinterSettings(
          address: '00:00:00:00:00:01',
          name: 'Counter printer',
        ),
      );

  Future<void> openReceipt(WidgetTester tester, {bool printer = true}) async {
    int? id;
    final c = await pump(
      tester,
      (context, c) => TextButton(
        onPressed: () => showReceiptSheet(context, id!),
        child: const Text('Open'),
      ),
    );
    await tester.runAsync(() async {
      id = await sale(c);
      if (printer) await chooseCounterPrinter(c);
    });
    await tester.tap(find.text('Open'));
    await settleFrames(tester);
    await tester.tap(find.byKey(const Key('receipt-print')));
    await settleFrames(tester);
  }

  String printed(int i) =>
      latin1.decode(printers.sent[i].$2, allowInvalid: true);

  testAppWidgets('a receipt prints on the counter printer, in copies', (
    tester,
  ) async {
    await openReceipt(tester);
    expect(find.text('Print receipt'), findsOneWidget);
    expect(find.text('Bluetooth · 58 mm'), findsOneWidget);
    await tester.tap(find.byKey(const Key('print-more')));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('print-go')));
    await settleFrames(tester);
    expect(printers.sent, hasLength(2));
    expect(printers.sent.first.$1, '00:00:00:00:00:01');
    expect(printed(0), contains('Kale 3 x 20'));
    expect(printed(0), contains('Green Basket'));
    expect(find.text('Printed 2 copies.'), findsOneWidget);
  });

  testAppWidgets('or on any printer, as a PDF', (tester) async {
    await openReceipt(tester, printer: false);
    expect(
      find.text('Choose your Bluetooth printer to use it'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('print-go')));
    await settleFrames(tester);
    expect(phonePrints.single, startsWith('Receipt '));
    expect(printers.sent, isEmpty);
  });

  testAppWidgets('a phone without a counter printer prints on the others', (
    tester,
  ) async {
    printers.isSupported = false;
    await openReceipt(tester);
    expect(find.byKey(const Key('print-on-counter')), findsNothing);
    expect(find.text('Other printers or PDF'), findsOneWidget);
  });

  testAppWidgets('a printer that is off says what to do', (tester) async {
    printers.fails = true;
    await openReceipt(tester);
    await tester.tap(find.byKey(const Key('print-go')));
    await settleFrames(tester);
    expect(
      find.text(
        'Turn the printer on and keep it close to the phone, then try again.',
      ),
      findsOneWidget,
    );
  });

  testAppWidgets('Receipt printer: choose it, its paper and a test', (
    tester,
  ) async {
    printers.allowed = false;
    final c = await pump(tester, (context, c) => const ReceiptPrinterScreen());
    await settleFrames(tester);
    await tester.tap(find.byKey(const Key('printer-allow')));
    await settleFrames(tester);
    expect(find.text('Counter printer'), findsOneWidget);
    expect(find.text('Store printer'), findsOneWidget);

    await tester.tap(find.text('Store printer'));
    await settleFrames(tester);
    await tester.tap(find.text('80 mm'));
    await settleFrames(tester);
    await tester.tap(find.byKey(const Key('printer-after-sale')));
    await settleFrames(tester);
    final saved = await tester.runAsync(
      () => c.read(printerSettingsProvider.future),
    );
    expect(saved!.address, '00:00:00:00:00:02');
    expect(saved.paperMm, 80);
    expect(saved.printAfterSale, isTrue);
    expect(
      await tester.runAsync(
        () => c.read(slipPrinterProvider).printsAfterSale(),
      ),
      isTrue,
    );

    await tester.tap(find.byKey(const Key('printer-test')));
    await settleFrames(tester);
    expect(printed(0), contains('Test print'));
    expect(find.text('Test printed.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('printer-bluetooth')));
    await settleFrames(tester);
    expect(printers.settingsOpened, 1);
  });

  testAppWidgets("Close the day prints the day's summary", (tester) async {
    final c = await pump(
      tester,
      (context, c) => TextButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const CloseDayScreen())),
        child: const Text('Open'),
      ),
    );
    await tester.runAsync(() async {
      await sale(c);
      await chooseCounterPrinter(c);
    });
    await tester.tap(find.text('Open'));
    await settleFrames(tester);
    await tester.enterText(find.byKey(const Key('close-counted')), '180');
    await tester.pump();
    await tester.tap(find.byKey(const Key('close-print')));
    await settleFrames(tester);
    await tester.tap(find.byKey(const Key('print-go')));
    await settleFrames(tester);
    expect(printed(0), contains('Day summary'));
    expect(printed(0), contains('It matches'));
  });
}
