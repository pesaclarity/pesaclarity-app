import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/documents_repository.dart';
import 'package:pesaclarity/src/data/repositories/invoices_repository.dart';
import 'package:pesaclarity/src/domain/documents/document_settings.dart';
import 'package:pesaclarity/src/domain/documents/invoice.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/documents/application/document_providers.dart';
import 'package:pesaclarity/src/features/invoices/application/invoice_pdf.dart';
import 'package:pesaclarity/src/features/invoices/application/invoice_providers.dart';
import 'package:pesaclarity/src/features/invoices/application/invoice_sender.dart';
import 'package:pesaclarity/src/features/invoices/presentation/make_invoice_screen.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

/// A 1×1 PNG.
final _png = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, //
  0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84,
  120, 156, 99, 56, 33, 160, 247, 31, 0, 4, 176, 2, 6, 132, 48, 119, 254, 0, 0,
  0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

final _receipt = PickedDocument(
  name: 'Design software receipt.pdf',
  mimeType: 'application/pdf',
  bytes: Uint8List.fromList(List.filled(84 * 1024, 1)),
);

final _photo = PickedDocument(
  name: 'eTIMS invoice.png',
  mimeType: 'image/png',
  bytes: _png,
);

class _Picker implements DocumentPicker {
  @override
  Future<PickedDocument?> pickImage() async => null;

  @override
  Future<PickedDocument?> takePhoto() async => PickedDocument(
    name: 'Receipt photo.jpg',
    mimeType: 'image/jpeg',
    bytes: Uint8List.fromList(const [1, 2, 3]),
  );

  @override
  Future<List<PickedDocument>> pickDocuments() async => [_receipt];
}

void main() {
  late AppDatabase db;
  final now = eat(2026, 11, 13, 10);

  setUp(() => db = openTestDatabase());

  List<Override> overrides() => [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(() => now),
    activeSpaceProvider.overrideWithValue(
      const Space(id: 'a', name: 'Amina Consulting', kind: SpaceKind.business),
    ),
    documentPickerProvider.overrideWithValue(_Picker()),
    invoiceRendererProvider.overrideWithValue(
      (doc, {withInvoice = true, withTimesheet = true}) async =>
          Uint8List.fromList([37, 80, doc.attachedPages.length]),
    ),
    // Each attached PDF reads as two pages.
    pdfPagesProvider.overrideWithValue((pdf) async => [_png, _png]),
  ];

  InvoiceDraft draft() => InvoiceDraft(
    client: 'Bidii Traders Ltd',
    issuedOn: CalendarDate(2026, 11, 13),
    billBy: BillBy.items,
    hoursDetail: HoursDetail.total,
    withholding: Withholding.none,
    totals: invoiceTotals(
      feesMinor: 1500000,
      costsMinor: 0,
      withholding: Withholding.none,
      withholdingRate: 500,
    ),
    lines: const [
      InvoiceLine(
        kind: InvoiceLineKind.fees,
        name: 'Strategy session',
        amountMinor: 1500000,
      ),
    ],
  );

  test('attachments go with the invoice, in order, and into one PDF', () async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    final id = await c
        .read(invoicesControllerProvider)
        .create(draft(), attachments: [_receipt, _photo]);
    final kept = await c.read(documentsRepositoryProvider).attachments(id);
    expect(kept.map((f) => f.name), [
      'Design software receipt.pdf',
      'eTIMS invoice.png',
    ]);
    final view = (await c.read(invoicesProvider.future)).single;
    expect(view.attached, 2);

    final sender = c.read(invoiceSenderProvider);
    final doc = await sender.docFor(view);
    // Two pages from the PDF, one from the picture.
    expect(doc.attachedPages, hasLength(3));
    final one = await sender.files(doc, one: true);
    expect(one.single.fileName, 'ac-inv-0001.pdf');
    expect(one.single.bytes.last, 3);
    final separate = await sender.files(doc, one: false);
    expect(separate.map((f) => f.fileName), [
      'ac-inv-0001.pdf',
      'Design software receipt.pdf',
      'eTIMS invoice.png',
    ]);
    // The invoice on its own carries no attached pages.
    expect(separate.first.bytes.last, 0);
  });

  test('attached pictures print as pages after the invoice', () async {
    final pdf = await renderInvoicePdf(
      InvoiceDoc(
        invoice: StoredInvoice(
          id: 1,
          number: 'AC-INV-0018',
          client: 'Bidii Traders Ltd',
          issuedOn: CalendarDate(2026, 11, 13),
          billBy: BillBy.items,
          hoursDetail: HoursDetail.total,
          timesheet: false,
          withholding: Withholding.none,
          totals: draft().totals,
          currency: 'KES',
          lines: draft().lines,
        ),
        business: 'Amina Consulting',
        settings: const DocumentSettings(),
        withholdingRate: 500,
        attachedPages: [_png],
      ),
    );
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });

  testAppWidgets('attach a receipt and charge it to the client', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const MakeInvoiceScreen(client: 'Bidii Traders Ltd'),
        ),
      ),
    );
    await settleFrames(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('invoice-bill-by')),
        matching: find.text('Items'),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byKey(const Key('item-name-0')), 'Strategy');
    await tester.enterText(find.byKey(const Key('item-price-0')), '15000');
    await tester.pump();

    await tester.tap(find.byKey(const Key('invoice-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attach-files')));
    await settleFrames(tester);
    expect(find.text('Design software receipt.pdf'), findsOneWidget);
    expect(find.text('84 KB'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('attach-charge-Design software receipt.pdf')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('attach-name-Design software receipt.pdf')),
      'Design software',
    );
    await tester.enterText(
      find.byKey(const Key('attach-amount-Design software receipt.pdf')),
      '3900',
    );
    await tester.pump();
    expect(
      find.text('Adds a cost line: Design software, 3,900'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('attach-done')));
    await tester.pumpAndSettle();
    expect(find.text('ATTACHED'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('invoice-to-pay')),
        matching: find.text('18,900'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('invoice-save')));
    await settleFrames(tester);
    final invoice = (await tester.runAsync(
      () => c.read(invoicesRepositoryProvider).all(),
    ))!.single;
    expect(invoice.totals.costsMinor, 390000);
    final files = await tester.runAsync(
      () => c.read(documentsRepositoryProvider).attachments(invoice.id),
    );
    expect(files!.single.name, 'Design software receipt.pdf');
  });

  testAppWidgets('a photo of a receipt, recorded as a business cost', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const MakeInvoiceScreen(client: 'Bidii Traders Ltd'),
        ),
      ),
    );
    await settleFrames(tester);
    await tester.tap(find.byKey(const Key('invoice-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attach-photo')));
    await settleFrames(tester);
    expect(find.text('Receipt photo.jpg'), findsOneWidget);
    await tester.tap(find.byKey(const Key('attach-charge-Receipt photo.jpg')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('attach-amount-Receipt photo.jpg')),
      '1200',
    );
    await tester.tap(find.byKey(const Key('attach-record-Receipt photo.jpg')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('attach-done')));
    await settleFrames(tester);
    // Spent opens with the amount and what it was for filled in.
    expect(find.text('1200'), findsOneWidget);
    expect(find.text('Receipt photo'), findsWidgets);
  });
}
