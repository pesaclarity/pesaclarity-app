import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/hours_repository.dart';
import 'package:pesaclarity/src/data/repositories/invoices_repository.dart';
import 'package:pesaclarity/src/data/repositories/sales_repository.dart';
import 'package:pesaclarity/src/data/repositories/tax_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/documents/document_settings.dart';
import 'package:pesaclarity/src/domain/documents/invoice.dart';
import 'package:pesaclarity/src/domain/hours/hours.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/books/application/books_providers.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/insights/application/report_sharer.dart';
import 'package:pesaclarity/src/features/invoices/application/invoice_pdf.dart';
import 'package:pesaclarity/src/features/invoices/application/invoice_providers.dart';
import 'package:pesaclarity/src/features/invoices/application/invoice_sender.dart';
import 'package:pesaclarity/src/features/invoices/presentation/invoices_screen.dart';
import 'package:pesaclarity/src/features/invoices/presentation/make_invoice_screen.dart';
import 'package:pesaclarity/src/features/people/application/people_providers.dart';
import 'package:pesaclarity/src/features/people/application/statement_pdf.dart';
import 'package:pesaclarity/src/features/people/presentation/remind_sheet.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

class _Files implements ReportSharer {
  final files = <String>[];
  final texts = <String?>[];

  @override
  Future<void> sharePdf(
    Uint8List bytes, {
    required String fileName,
    required String subject,
  }) async => files.add(fileName);

  @override
  Future<void> shareFile(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    required String subject,
  }) async => files.add(fileName);

  @override
  Future<void> shareFiles(
    List<SharedFile> files, {
    required String subject,
    String? text,
  }) async {
    this.files.addAll(files.map((f) => f.fileName));
    texts.add(text);
  }
}

const _amina = Space(
  id: 'amina',
  name: 'Amina Consulting',
  kind: SpaceKind.business,
);

void main() {
  group('totals', () {
    test('the client deducts 5% of the fees, not the costs', () {
      final t = invoiceTotals(
        feesMinor: 11000000,
        costsMinor: 390000,
        withholding: Withholding.deducts,
        withholdingRate: 500,
      );
      expect(t.withheldMinor, 550000);
      expect(t.totalMinor, 11390000);
      expect(t.toPayMinor, 10840000);
    });

    test('paid on top: fees are grossed up so the fees still arrive', () {
      final t = invoiceTotals(
        feesMinor: 11000000,
        costsMinor: 0,
        withholding: Withholding.onTop,
        withholdingRate: 500,
      );
      expect(t.feesShownMinor, 11579000);
      expect(t.withheldMinor, 579000);
      expect(t.toPayMinor, 11000000);
    });

    test('VAT on fees and costs when registered', () {
      final t = invoiceTotals(
        feesMinor: 1000000,
        costsMinor: 0,
        withholding: Withholding.none,
        withholdingRate: 500,
        vatRate: 1600,
      );
      expect(t.vatMinor, 160000);
      expect(t.toPayMinor, 1160000);
    });

    test('status follows payments and the due date', () {
      final today = CalendarDate(2026, 11, 30);
      InvoiceStatus s(int paid, CalendarDate? due) => invoiceStatus(
        toPayMinor: 100,
        paidMinor: paid,
        dueOn: due,
        today: today,
      );
      expect(s(0, today.addDays(3)), InvoiceStatus.unpaid);
      expect(s(40, today.addDays(3)), InvoiceStatus.partPaid);
      expect(s(40, today.addDays(-1)), InvoiceStatus.overdue);
      expect(s(100, today.addDays(-1)), InvoiceStatus.paid);
    });

    test('hours show as total, by project or day by day', () {
      final mon = CalendarDate(2026, 11, 2);
      final entries = [
        HourEntry(
          id: 1,
          client: 'Bidii Traders Ltd',
          project: 'Website revamp',
          what: 'Discovery workshop',
          day: mon,
          minutes: 240,
          rateMinor: 250000,
        ),
        HourEntry(
          id: 2,
          client: 'Bidii Traders Ltd',
          project: 'Website revamp',
          what: 'Design',
          day: mon.addDays(1),
          minutes: 360,
          rateMinor: 250000,
        ),
      ];
      String plain(int m) => '${m ~/ 100}';
      String day(CalendarDate d) => '${d.day} Nov';
      final total = hoursLines(
        entries,
        HoursDetail.total,
        plain: plain,
        dayName: day,
      );
      expect(total.single.detail, '10 hours');
      expect(total.single.amountMinor, 2500000);
      final project = hoursLines(
        entries,
        HoursDetail.project,
        plain: plain,
        dayName: day,
      );
      expect(project.single.detail, '10 h × 2500');
      final days = hoursLines(
        entries,
        HoursDetail.day,
        plain: plain,
        dayName: day,
      );
      expect(days.map((l) => l.name), ['2 Nov', '3 Nov']);
      expect(days.first.detail, 'Discovery workshop 4 h');
      expect(days.first.amountMinor, 1000000);
    });
  });

  group('invoices', () {
    late AppDatabase db;
    late _Files files;
    final now = eat(2026, 11, 13, 10);

    setUp(() async {
      db = openTestDatabase();
      files = _Files();
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'M-Pesa',
              type: AccountType.mpesa,
              openingDate: eat(2026, 11, 1, 0),
            ),
          );
    });

    List<Override> overrides() => [
      appDatabaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => now),
      activeSpaceProvider.overrideWithValue(_amina),
      reportSharerProvider.overrideWithValue(files),
      deviceRegionProvider.overrideWithValue('KE'),
      invoiceRendererProvider.overrideWithValue(
        (doc, {withInvoice = true, withTimesheet = true}) async =>
            Uint8List.fromList([37, 80]),
      ),
    ];

    Future<void> hours(ProviderContainer c) async {
      final repo = c.read(hoursRepositoryProvider);
      await repo.log(
        client: 'Bidii Traders Ltd',
        project: 'Website revamp',
        what: 'Discovery workshop',
        day: CalendarDate(2026, 11, 2),
        minutes: 24 * 60,
        rateMinor: 250000,
        at: now,
      );
      await repo.log(
        client: 'Bidii Traders Ltd',
        project: 'Website revamp',
        what: 'Design',
        day: CalendarDate(2026, 11, 3),
        minutes: 20 * 60,
        rateMinor: 250000,
        at: now,
      );
    }

    test('an invoice for hours, settled by its payment message', () async {
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      await hours(c);
      final unbilled = await c.read(hoursRepositoryProvider).unbilled();
      final totals = invoiceTotals(
        feesMinor: 11000000,
        costsMinor: 390000,
        withholding: Withholding.deducts,
        withholdingRate: 500,
      );
      final id = await c
          .read(invoicesControllerProvider)
          .create(
            InvoiceDraft(
              client: 'Bidii Traders Ltd',
              issuedOn: CalendarDate(2026, 11, 13),
              dueOn: CalendarDate(2026, 11, 28),
              billBy: BillBy.hours,
              hoursDetail: HoursDetail.total,
              withholding: Withholding.deducts,
              totals: totals,
              timesheet: true,
              lines: const [
                InvoiceLine(
                  kind: InvoiceLineKind.fees,
                  name: 'Website revamp',
                  amountMinor: 11000000,
                ),
                InvoiceLine(
                  kind: InvoiceLineKind.cost,
                  name: 'Design software',
                  amountMinor: 390000,
                ),
              ],
              hourIds: [for (final e in unbilled) e.id],
            ),
          );
      final invoice = (await c.read(invoicesRepositoryProvider).byId(id))!;
      expect(invoice.number, 'AC-INV-0001');
      expect(await c.read(hoursRepositoryProvider).unbilled(), isEmpty);
      var view = (await c.read(invoicesProvider.future)).single;
      expect(view.status, InvoiceStatus.unpaid);
      expect(view.leftMinor, 10840000);

      // The client pays 108,400 by M-Pesa: the rest is tax they withheld.
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: (await (db.select(
                db.accounts,
              )..where((a) => a.name.equals('M-Pesa'))).getSingle()).id,
              occurredAt: now.add(const Duration(hours: 2)),
              amountMinor: 10840000,
              direction: TransactionDirection.inflow,
              kind: const Value(TransactionKind.received),
              source: TransactionSource.sms,
              counterpartyName: const Value('BIDII TRADERS LIMITED'),
            ),
          );
      expect(await c.read(invoicesControllerProvider).matchPayments(), 1);
      view = (await c.refresh(invoicesProvider.future)).single;
      expect(view.status, InvoiceStatus.paid);
      final withheld = (await c.read(taxRepositoryProvider).withheld()).single;
      expect(withheld.amountMinor, 550000);
      final books = await c.read(booksProvider.future);
      expect(books.unbalanced, isEmpty);
      expect(books.balanceOf(BookAccount.owedToYou, currency: 'KES'), 0);
      expect(books.balanceOf(BookAccount.tax, currency: 'KES'), 550000);
    });

    test('the invoice PDF renders with its timesheet page', () async {
      final mon = CalendarDate(2026, 11, 2);
      final pdf = await renderInvoicePdf(
        InvoiceDoc(
          invoice: StoredInvoice(
            id: 1,
            number: 'AC-INV-0018',
            client: 'Bidii Traders Ltd',
            issuedOn: mon.addDays(11),
            dueOn: mon.addDays(26),
            billBy: BillBy.hours,
            hoursDetail: HoursDetail.day,
            timesheet: true,
            withholding: Withholding.deducts,
            totals: invoiceTotals(
              feesMinor: 2500000,
              costsMinor: 390000,
              withholding: Withholding.deducts,
              withholdingRate: 500,
            ),
            currency: 'KES',
            lines: const [
              InvoiceLine(
                kind: InvoiceLineKind.fees,
                name: 'Mon 2 Nov',
                detail: 'Discovery workshop 4 h',
                amountMinor: 1000000,
              ),
              InvoiceLine(
                kind: InvoiceLineKind.cost,
                name: 'Design software',
                amountMinor: 390000,
              ),
            ],
          ),
          business: 'Amina Consulting',
          settings: const DocumentSettings(till: 'Paybill 000000'),
          withholdingRate: 500,
          paid: true,
          hours: [
            HourEntry(
              id: 1,
              client: 'Bidii Traders Ltd',
              project: 'Website revamp',
              what: 'Discovery workshop',
              day: mon,
              minutes: 240,
              rateMinor: 250000,
            ),
          ],
        ),
      );
      expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    });

    test(
      'an invoice with a full band, a place to sign, and no branding',
      () async {
        const settings = DocumentSettings(
          till: 'Paybill 000000',
          invoiceHeader: InvoiceHeader.band,
          signature: true,
          branding: false,
        );
        expect(invoiceFooter(settings), 'This is not an eTIMS tax invoice.');
        expect(
          invoiceFooter(const DocumentSettings()),
          'Made on this phone with Pesa Clarity. This is not an eTIMS tax '
          'invoice.',
        );
        expect(
          statementFooter(settings, CalendarDate(2026, 11, 13)),
          'Made on 13 November 2026.',
        );
        final pdf = await renderInvoicePdf(
          InvoiceDoc(
            invoice: StoredInvoice(
              id: 2,
              number: 'AC-INV-0019',
              client: 'Bidii Traders Ltd',
              issuedOn: CalendarDate(2026, 11, 13),
              billBy: BillBy.items,
              hoursDetail: HoursDetail.total,
              timesheet: false,
              withholding: Withholding.none,
              totals: invoiceTotals(
                feesMinor: 1500000,
                costsMinor: 0,
                withholding: Withholding.none,
                withholdingRate: 500,
              ),
              currency: 'KES',
              lines: const [
                InvoiceLine(
                  kind: InvoiceLineKind.fees,
                  name: 'Website revamp',
                  amountMinor: 1500000,
                ),
              ],
            ),
            business: 'Amina Consulting',
            settings: settings,
            withholdingRate: 500,
          ),
        );
        expect(String.fromCharCodes(pdf.take(4)), '%PDF');
      },
    );

    testAppWidgets('make an invoice from hours, then share it', (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      await tester.runAsync(() => hours(c));
      final router = GoRouter(
        initialLocation: AppRoutes.invoices,
        routes: [
          GoRoute(
            path: AppRoutes.invoices,
            builder: (_, _) => const InvoicesScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, state) => MakeInvoiceScreen(
                  client: state.uri.queryParameters['client'],
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await settleFrames(tester);
      expect(find.text('Invoices you make show here.'), findsOneWidget);
      unawaited(router.push(AppRoutes.newInvoice(client: 'Bidii Traders Ltd')));
      await settleFrames(tester);
      expect(find.text('Website revamp'), findsWidgets);
      expect(
        find.text('44 h on 2 days · 2,500 an hour · 110,000'),
        findsOneWidget,
      );
      Future<void> showHours(String detail) async {
        await tester.tap(find.byKey(const Key('hours-detail')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('hours-detail-$detail')));
        await tester.pumpAndSettle();
      }

      Finder inPreview(String text) => find.descendant(
        of: find.byKey(const Key('invoice-preview')),
        matching: find.text(text),
      );

      expect(inPreview('44 hours'), findsOneWidget);
      await showHours('project');
      expect(inPreview('44 h × 2,500'), findsOneWidget);
      await showHours('total');
      expect(inPreview('44 hours'), findsOneWidget);

      await tester.tap(find.byKey(const Key('invoice-withholding')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'They pay 104,500 for fees and send KRA 5,500. It counts towards '
          'your income tax.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('withholding-deducts')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('withholding-done')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('invoice-to-pay')),
          matching: find.text('104,500'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('invoice-save')));
      await settleFrames(tester);
      expect(find.text('Bidii Traders Ltd'), findsOneWidget);
      expect(find.textContaining('AC-INV-0001'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('invoice-AC-INV-0001')),
          matching: find.text('Unpaid'),
        ),
        findsOneWidget,
      );
      Future<void> show(String filter) async {
        await tester.tap(find.byKey(const Key('invoices-filter')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('invoices-$filter')));
        await tester.pumpAndSettle();
      }

      await show('paid');
      expect(find.byKey(const Key('invoice-AC-INV-0001')), findsNothing);
      await show('unpaid');
      expect(find.byKey(const Key('invoice-AC-INV-0001')), findsOneWidget);

      await tester.tap(find.byKey(const Key('invoice-AC-INV-0001')));
      await settleFrames(tester);
      expect(find.text('Invoice AC-INV-0001'), findsOneWidget);
      await tester.tap(find.byKey(const Key('invoice-share')));
      await settleFrames(tester);
      expect(files.files, ['ac-inv-0001.pdf']);
      final remembered = await tester.runAsync(
        () => c.read(clientWithholdingProvider.future),
      );
      expect(remembered!['bidii traders ltd'], Withholding.deducts);
    });

    test('a statement PDF for a customer', () async {
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      await c.read(salesControllerProvider).sell([
        const SalePart(SalePaymentMethod.credit, 1500000),
      ], credit: const CreditTerms(customer: 'Bidii Traders Ltd'));
      final customer = (await c.read(customersProvider.future)).single;
      final pdf = await renderStatementPdf(
        customer: customer,
        business: 'Amina Consulting',
        settings: const DocumentSettings(till: 'Paybill 000000'),
        today: CalendarDate(2026, 11, 13),
      );
      expect(String.fromCharCodes(pdf.take(4)), '%PDF');
      await c.read(statementSenderProvider).share(customer);
      expect(files.files, ['statement-bidii-traders-ltd-2026-11-13.pdf']);
    });

    testAppWidgets('Remind attaches the open invoice', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      final customer = await tester.runAsync(() async {
        await c
            .read(invoicesControllerProvider)
            .create(
              InvoiceDraft(
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
              ),
            );
        return (await c.read(customersProvider.future)).single;
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showRemindSheet(context, customer!),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await settleFrames(tester);
      expect(find.text('Attach invoice AC-INV-0001'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('remind-send')));
      await tester.tap(find.byKey(const Key('remind-send')));
      // Making the invoice's files reads the database a few times.
      for (var i = 0; i < 40 && files.files.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(files.files, ['ac-inv-0001.pdf']);
      expect(files.texts.single, contains('AC-INV-0001'));
    });
  });
}
