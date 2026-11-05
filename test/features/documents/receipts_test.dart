import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/documents_repository.dart';
import 'package:pesaclarity/src/data/repositories/sales_repository.dart';
import 'package:pesaclarity/src/data/repositories/stock_repository.dart';
import 'package:pesaclarity/src/domain/documents/document_settings.dart';
import 'package:pesaclarity/src/domain/documents/receipt.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/documents/application/document_providers.dart';
import 'package:pesaclarity/src/features/documents/application/receipt_pdf.dart';
import 'package:pesaclarity/src/features/documents/presentation/document_settings_screen.dart';
import 'package:pesaclarity/src/features/documents/presentation/receipt_sheet.dart';
import 'package:pesaclarity/src/features/insights/application/report_sharer.dart';
import 'package:pesaclarity/src/features/lending/data/reminder_sharer.dart';
import 'package:pesaclarity/src/features/reminders/application/business_reminders.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/features/sales/presentation/pay_sheet.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

class _Files implements ReportSharer {
  final files = <({String fileName, String mimeType})>[];

  @override
  Future<void> sharePdf(
    Uint8List bytes, {
    required String fileName,
    required String subject,
  }) async => files.add((fileName: fileName, mimeType: 'application/pdf'));

  @override
  Future<void> shareFile(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    required String subject,
  }) async => files.add((fileName: fileName, mimeType: mimeType));

  @override
  Future<void> shareFiles(
    List<SharedFile> files, {
    required String subject,
  }) async {
    for (final f in files) {
      await shareFile(
        f.bytes,
        fileName: f.fileName,
        mimeType: f.mimeType,
        subject: subject,
      );
    }
  }
}

class _Launcher implements MessageLauncher {
  final opened = <(SendWith, String, String)>[];

  @override
  Future<bool> open(SendWith app, String international, String text) async {
    opened.add((app, international, text));
    return true;
  }
}

class _Sharer implements ReminderSharer {
  final shared = <String>[];

  @override
  Future<void> share(String message) async => shared.add(message);
}

class _Picker implements DocumentPicker {
  @override
  Future<PickedDocument?> pickImage() async => PickedDocument(
    name: 'logo.png',
    mimeType: 'image/png',
    bytes: Uint8List.fromList(_png),
  );

  @override
  Future<List<PickedDocument>> pickDocuments() async => const [];
}

/// A 1×1 PNG.
const _png = [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, //
  0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84,
  120, 156, 99, 248, 255, 255, 63, 0, 5, 254, 2, 254, 167, 53, 129, 132, 0, 0,
  0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
];

const _stall = Space(
  id: 'stall',
  name: 'Vegetable stall',
  kind: SpaceKind.business,
);

void main() {
  late AppDatabase db;
  late _Files files;
  late _Launcher launcher;
  late _Sharer sharer;
  final now = eat(2026, 11, 5, 14, 41);

  setUp(() async {
    db = openTestDatabase();
    files = _Files();
    launcher = _Launcher();
    sharer = _Sharer();
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
    activeSpaceProvider.overrideWithValue(_stall),
    reportSharerProvider.overrideWithValue(files),
    messageLauncherProvider.overrideWithValue(launcher),
    reminderSharerProvider.overrideWithValue(sharer),
    documentPickerProvider.overrideWithValue(_Picker()),
    deviceRegionProvider.overrideWithValue('KE'),
    receiptRendererProvider.overrideWithValue(
      (r, {required initials, logo}) async => Uint8List.fromList([37, 80]),
    ),
    pdfPictureProvider.overrideWithValue(
      (pdf) async => Uint8List.fromList(_png),
    ),
  ];

  /// Sukuma 3 × 20 and Tomatoes 1 kg, paid in cash.
  Future<int> sale(ProviderContainer c) async {
    final stock = c.read(stockRepositoryProvider);
    final sukuma = await stock.add(
      kind: ItemKind.product,
      name: 'Sukuma',
      priceMinor: 2000,
      stockMilli: 50000,
      at: now,
    );
    final tomatoes = await stock.add(
      kind: ItemKind.product,
      name: 'Tomatoes',
      unit: 'kg',
      priceMinor: 12000,
      stockMilli: 20000,
      at: now,
    );
    final outcome = await c
        .read(salesControllerProvider)
        .sell(
          [const SalePart(SalePaymentMethod.cash, 18000)],
          lines: [
            SaleLine(
              itemId: sukuma,
              name: 'Sukuma',
              quantityMilli: 3000,
              totalMinor: 6000,
            ),
            SaleLine(
              itemId: tomatoes,
              name: 'Tomatoes',
              quantityMilli: 1000,
              totalMinor: 12000,
            ),
          ],
        );
    return outcome.saleId;
  }

  test('numbers and initials as people read them', () {
    const s = DocumentSettings();
    expect(DocumentSettings.initials('Vegetable stall'), 'VS');
    expect(DocumentSettings.initials('Amina'), 'AM');
    expect(s.numberLabel('Vegetable stall', 246), 'VS-000246');
    final back = DocumentSettings.fromJson(
      s
          .copyWith(
            till: () => 'Till 000000',
            bank: () => 'Equity Bank',
            prefix: () => 'STALL/',
            sendAs: ReceiptFormat.text,
          )
          .toJson(),
    );
    expect(back.payLine, 'Till 000000 · Equity Bank');
    expect(back.numberLabel('x', 7), 'STALL/000007');
    expect(back.sendAs, ReceiptFormat.text);
    expect(back.offerReceipt, isTrue);
  });

  test('a receipt for a sale: lines, number once, paid', () async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    final id = await sale(c);
    final maker = c.read(receiptMakerProvider);
    final r = (await maker.receiptFor(id))!;
    expect(r.number, 'VS-000001');
    expect(r.business, 'Vegetable stall');
    String plain(int m) => '${m ~/ 100}';
    expect(r.lines.map((l) => l.label(plain)), [
      'Sukuma 3 × 20',
      'Tomatoes 1 kg',
    ]);
    expect(receiptPaidLine(r, methodLabel, plain), 'PAID · Cash');
    // The same sale keeps its number; the next sale gets the next one.
    expect((await maker.receiptFor(id))!.number, 'VS-000001');
    final second = await sale(c);
    expect((await maker.receiptFor(second))!.number, 'VS-000002');
    final text = maker.text(r);
    expect(text, contains('Receipt VS-000001'));
    expect(text, contains('Total: KES 180'));
    expect(text, endsWith('This is not an eTIMS tax invoice.'));
  });

  test('the receipt PDF renders', () async {
    final pdf = await renderReceiptPdf(
      Receipt(
        number: 'VS-000245',
        at: now,
        business: 'Vegetable stall',
        place: 'Gikomba',
        payTo: 'Till 000000',
        lines: const [
          ReceiptLine(name: 'Sukuma', quantityMilli: 3000, totalMinor: 6000),
        ],
        totalMinor: 6000,
        payments: const [
          ReceiptPayment(
            method: SalePaymentMethod.mpesa,
            amountMinor: 6000,
            code: 'SKL4H7X2QP',
          ),
        ],
        currency: 'KES',
        footer: 'Thank you, come again!',
      ),
      label: methodLabel,
      initials: 'VS',
    );
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });

  Future<ProviderContainer> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    final id = await tester.runAsync(() => sale(c));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showReceiptSheet(context, id!),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await settleFrames(tester);
    return c;
  }

  testAppWidgets('the receipt goes as a picture by default', (tester) async {
    await pumpSheet(tester);
    expect(find.text('Sale saved'), findsOneWidget);
    expect(find.byKey(const Key('receipt-card')), findsOneWidget);
    expect(find.text('Sukuma 3 × 20'), findsOneWidget);
    await tester.tap(find.byKey(const Key('receipt-share')));
    await settleFrames(tester);
    expect(files.files.single.mimeType, 'image/png');
    expect(files.files.single.fileName, 'receipt-vs-000001.png');
  });

  testAppWidgets('as text to a number, it opens WhatsApp', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.byKey(const Key('receipt-as-text')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('phone-number')), '0712345678');
    await tester.pump();
    await tester.tap(find.byKey(const Key('receipt-share')));
    await settleFrames(tester);
    final (app, number, text) = launcher.opened.single;
    expect(app, SendWith.whatsapp);
    expect(number, '+254712345678');
    expect(text, contains('Receipt VS-000001'));
  });

  testAppWidgets('settings: details, numbering, logo and receipts', (
    tester,
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
          home: const DocumentSettingsScreen(),
        ),
      ),
    );
    await settleFrames(tester);
    expect(find.text('VS-000001 next'), findsOneWidget);

    await tester.tap(find.byKey(const Key('documents-details')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-Place')), 'Gikomba');
    await tester.tap(find.byKey(const Key('fields-save')));
    await settleFrames(tester);
    expect(find.text('Vegetable stall · Gikomba'), findsOneWidget);

    await tester.tap(find.byKey(const Key('documents-numbering')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('field-Before each number')),
      'STALL-',
    );
    await tester.tap(find.byKey(const Key('fields-save')));
    await settleFrames(tester);
    expect(find.text('STALL-000001 next'), findsOneWidget);

    await tester.tap(find.byKey(const Key('documents-logo')));
    await settleFrames(tester);
    final logo = await tester.runAsync(
      () => c.read(documentsRepositoryProvider).file(DocumentFileKind.logo),
    );
    expect(logo!.name, 'logo.png');

    await tester.tap(find.byKey(const Key('documents-offer')));
    await settleFrames(tester);
    final settings = await tester.runAsync(
      () => c.read(documentSettingsProvider.future),
    );
    expect(settings!.offerReceipt, isFalse);
    expect(settings.place, 'Gikomba');
  });
}
