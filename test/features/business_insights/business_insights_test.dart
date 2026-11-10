import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/sales_repository.dart';
import 'package:pesaclarity/src/data/repositories/stock_repository.dart';
import 'package:pesaclarity/src/domain/books/business_report.dart';
import 'package:pesaclarity/src/domain/books/report_setup.dart';
import 'package:pesaclarity/src/domain/documents/document_settings.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/business_insights/application/business_report_pdf.dart';
import 'package:pesaclarity/src/features/business_insights/application/report_content.dart';
import 'package:pesaclarity/src/features/business_insights/application/report_maker.dart';
import 'package:pesaclarity/src/features/business_insights/presentation/business_insights_screen.dart';
import 'package:pesaclarity/src/features/business_insights/presentation/full_records_screen.dart';
import 'package:pesaclarity/src/features/business_insights/presentation/make_report_screen.dart';
import 'package:pesaclarity/src/features/documents/application/document_providers.dart';
import 'package:pesaclarity/src/features/insights/application/report_sharer.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

class _FakeSharer implements ReportSharer {
  final files = <({String fileName, String mimeType, Uint8List bytes})>[];

  @override
  Future<void> sharePdf(
    Uint8List bytes, {
    required String fileName,
    required String subject,
  }) async => files.add((
    fileName: fileName,
    mimeType: 'application/pdf',
    bytes: bytes,
  ));

  @override
  Future<void> shareFile(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    required String subject,
  }) async => files.add((fileName: fileName, mimeType: mimeType, bytes: bytes));

  @override
  Future<void> shareFiles(
    List<SharedFile> files, {
    required String subject,
    String? text,
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

void main() {
  late AppDatabase db;
  late _FakeSharer sharer;
  late List<ReportDocument> previewed;
  final now = eat(2026, 11, 5, 19);

  setUp(() async {
    db = openTestDatabase();
    sharer = _FakeSharer();
    previewed = [];
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'Cash',
            type: AccountType.cash,
            openingDate: eat(2026, 10, 1, 0),
            openingBalanceMinor: const Value(100000),
          ),
        );
  });

  List<Override> overrides() => [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(() => now),
    reportSharerProvider.overrideWithValue(sharer),
    businessReportRendererProvider.overrideWithValue(
      (doc) async => Uint8List.fromList([37, 80, 68, 70]),
    ),
    reportPreviewerProvider.overrideWithValue((context, doc, pdf) async {
      previewed.add(doc);
    }),
  ];

  /// Sukuma sold for cash, a sale on credit to Otieno, and rent.
  Future<void> seed(ProviderContainer c) async {
    final stock = c.read(stockRepositoryProvider);
    final sukuma = await stock.add(
      kind: ItemKind.product,
      name: 'Sukuma',
      unit: 'bunch',
      priceMinor: 2000,
      costMinor: 500,
      stockMilli: 400000,
      at: eat(2026, 11, 1, 6),
    );
    final sales = c.read(salesControllerProvider);
    await sales.sell(
      [const SalePart(SalePaymentMethod.cash, 600000)],
      lines: [
        SaleLine(
          itemId: sukuma,
          name: 'Sukuma',
          quantityMilli: 300000,
          totalMinor: 600000,
        ),
      ],
    );
    await sales.sell([
      const SalePart(SalePaymentMethod.credit, 120000),
    ], credit: const CreditTerms(customer: 'Otieno'));
    final rent = await (db.select(
      db.categories,
    )..where((x) => x.name.equals('Rent'))).getSingleOrNull();
    final cash = (await db.select(db.accounts).getSingle()).id;
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: cash,
            occurredAt: eat(2026, 11, 3, 9),
            amountMinor: 200000,
            direction: TransactionDirection.outflow,
            source: TransactionSource.manual,
            item: const Value('Rent'),
            categoryOverrideId: Value(rent?.id),
          ),
        );
  }

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    String path = AppRoutes.insights,
  }) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    await tester.runAsync(() => seed(c));
    final router = GoRouter(
      initialLocation: path,
      routes: [
        GoRoute(
          path: AppRoutes.insights,
          builder: (_, _) => const BusinessInsightsScreen(),
          routes: [
            GoRoute(
              path: 'records',
              builder: (_, _) => const FullRecordsScreen(),
            ),
            GoRoute(
              path: 'report',
              builder: (_, _) => const MakeReportScreen(),
            ),
          ],
        ),
        GoRoute(
          path: '/people/customer',
          builder: (_, _) => const Scaffold(body: Text('Statement')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await settleFrames(tester);
    return c;
  }

  test('the report counts credit sales, cost of stock and rent', () async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    await seed(c);
    final maker = c.read(reportMakerProvider);
    final doc = await maker.make(
      period: periodFor(ReportRange.thisMonth, CalendarDate(2026, 11, 5)),
      sections: ReportSection.values.toSet(),
    );
    final pnl = doc.blocks.whereType<ReportTable>().first;
    expect(pnl.title, 'Profit and loss');
    // Sales 7,200; stock sold 1,500; rent 2,000.
    expect(pnl.total, ['Profit', 370000]);
    final best = doc.blocks.whereType<ReportTable>().firstWhere(
      (t) => t.title == 'Best sellers',
    );
    expect(best.rows.single.take(2), ['Sukuma', '300 bunches']);
    final customers = doc.blocks.whereType<ReportTable>().firstWhere(
      (t) => t.title == 'Customers who owe you',
    );
    expect(customers.rows.single.first, 'Otieno');
    final book = doc.blocks.whereType<ReportTable>().firstWhere(
      (t) => t.title == 'Cash book',
    );
    expect(book.total, ['', 'Total', '', 600000, 200000]);

    final pdf = await renderBusinessReport(doc);
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });

  test('totals only: the cash book by day, and people as totals', () async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    await seed(c);
    final doc = await c
        .read(reportMakerProvider)
        .make(
          period: periodFor(ReportRange.thisMonth, CalendarDate(2026, 11, 5)),
          sections: ReportSection.values.toSet(),
          detail: ReportDetail.totals,
        );
    final tables = doc.blocks.whereType<ReportTable>().toList();
    final book = tables.firstWhere((t) => t.title == 'Cash book by day');
    expect(book.total, ['Total', 600000, 200000]);
    final customers = tables.firstWhere(
      (t) => t.title == 'Customers who owe you',
    );
    expect(customers.rows.single.first, '1 customer');
    expect(customers.rows.single.last, 120000);
    final pdf = await renderBusinessReport(doc);
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });

  test('a styled report: compared, in accounting terms, with charts', () async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    await seed(c);
    await c
        .read(documentSettingsProvider.notifier)
        .save(const DocumentSettings(kraPin: 'P000000000A', showKraPin: true));
    await c
        .read(reportSettingsProvider.notifier)
        .save(const ReportSettings(cover: ReportCover(permit: 'BP-0001')));
    const style = ReportStyle(
      compare: true,
      wording: ReportWording.formal,
      charts: true,
      kraPin: true,
      permit: true,
      signature: true,
    );
    final doc = await c
        .read(reportMakerProvider)
        .make(
          period: periodFor(ReportRange.thisMonth, CalendarDate(2026, 11, 5)),
          sections: ReportSection.values.toSet(),
          style: style,
        );
    final tables = doc.blocks.whereType<ReportTable>().toList();
    final pnl = tables.first;
    expect(pnl.title, 'Income statement');
    expect(pnl.columns, ['', 'October', 'This period']);
    expect(pnl.total, ['Net profit', 0, 370000]);
    expect(
      tables.map((t) => t.title),
      containsAll(['Accounts receivable', 'Accounts payable']),
    );
    final balance = tables.firstWhere((t) => t.title.startsWith('Balance'));
    expect(balance.title, startsWith('Balance sheet on'));
    expect(balance.total!.first, 'Net assets');

    final charts = doc.blocks.whereType<ReportChart>().toList();
    expect(charts.map((c) => c.title), [
      'Net profit by month',
      'How people paid',
      'Sales by day',
    ]);
    expect(charts.first.points.map((p) => p.label), [
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
    ]);
    expect(charts.first.points.last.valueMinor, 370000);
    final days = charts.last.points;
    expect(days.map((p) => p.label), ['1', '2', '3', '4', '5']);
    expect(days.fold(0, (sum, p) => sum + p.valueMinor), 720000);
    expect(doc.coverNotes, ['KRA PIN P000000000A', 'Business permit BP-0001']);
    expect(reportCsv(doc), contains('KRA PIN P000000000A'));

    for (final cover in ReportCoverStyle.values) {
      for (final colour in ReportColour.values) {
        final styled = ReportDocument(
          title: doc.title,
          business: doc.business,
          coverLine: doc.coverLine,
          period: doc.period,
          made: doc.made,
          currency: doc.currency,
          blocks: doc.blocks,
          coverNotes: doc.coverNotes,
          style: style.copyWith(cover: cover, colour: colour, branding: false),
        );
        final pdf = await renderBusinessReport(styled);
        expect(String.fromCharCodes(pdf.take(4)), '%PDF', reason: '$cover');
      }
    }
  });

  test('a one-page summary of the chosen parts', () async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    await seed(c);
    final doc = await c
        .read(reportMakerProvider)
        .make(
          period: periodFor(ReportRange.thisMonth, CalendarDate(2026, 11, 5)),
          sections: ReportAudience.sacco.sections,
          style: const ReportStyle(length: ReportLength.summary),
        );
    final summary = doc.blocks.single as ReportTable;
    expect(summary.title, 'Summary');
    expect(summary.columns, ['', 'Amount']);
    expect(summary.rows.take(3), [
      ['Sales', 720000],
      ['Costs', -350000],
      ['Profit', 370000],
    ]);
    expect(summary.rows.last.first, 'What the business is worth');
    final pdf = await renderBusinessReport(doc);
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });

  testAppWidgets('Insights shows profit, how people pay and best sellers', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('How it is doing'), findsOneWidget);
    expect(find.text('KES 3,700'), findsOneWidget);
    expect(find.textContaining('Sales 7,200 · costs 3,500'), findsOneWidget);
    expect(find.text('How people pay'), findsOneWidget);
    expect(find.text('On credit'), findsOneWidget);
    expect(find.text('Sukuma'), findsOneWidget);
    expect(find.text('300 bunches · profit 15 / bunch'), findsOneWidget);
    expect(find.byKey(const Key('insights-by-day')), findsOneWidget);

    await tester.tap(find.byKey(const Key('range')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('range-dates')), findsNothing);
    await tester.tap(find.byKey(const Key('range-lastMonth')));
    await settleFrames(tester);
    expect(find.text('Profit last month'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('range')),
        matching: find.text('Last month'),
      ),
      findsOneWidget,
    );
    expect(find.text('KES 0'), findsOneWidget);
  });

  testAppWidgets('Full records shows the books and shares them', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('insights-full-records')));
    await settleFrames(tester);
    expect(find.text('1 to 5 November'), findsOneWidget);
    expect(find.text('Cash, M-Pesa and bank'), findsOneWidget);
    expect(find.text('Customers owe you'), findsOneWidget);
    expect(find.text('Cash, credit'), findsOneWidget);

    Future<void> show(String view) async {
      await tester.tap(find.byKey(const Key('records-view')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('records-$view')));
      await settleFrames(tester);
    }

    await show('cashBook');
    expect(find.textContaining('In 6,000'), findsOneWidget);

    await show('customers');
    expect(find.text('Otieno'), findsOneWidget);

    await tester.tap(find.byKey(const Key('records-share-pdf')));
    await settleFrames(tester);
    await tester.tap(find.byKey(const Key('records-csv')));
    await settleFrames(tester);
    expect(sharer.files.map((f) => f.mimeType), [
      'application/pdf',
      'text/csv',
    ]);
    final csv = String.fromCharCodes(sharer.files.last.bytes);
    expect(csv, contains('Profit,3700.00'));
    expect(csv, contains('Otieno'));
  });

  testAppWidgets('Make a report: who it is for, saved, previewed', (
    tester,
  ) async {
    final c = await pump(tester, path: AppRoutes.makeReport);
    expect(find.text('Make a report'), findsOneWidget);
    await tester.tap(find.byKey(const Key('range')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('range-dates')), findsOneWidget);
    await tester.tap(find.byKey(const Key('range-thisMonth')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('section-cashBook')))
          .value,
      isFalse,
    );
    ReportDetail detail() => tester
        .widget<SegmentedButton<ReportDetail>>(
          find.ancestor(
            of: find.byKey(const Key('detail-totals')),
            matching: find.byType(SegmentedButton<ReportDetail>),
          ),
        )
        .selected
        .single;
    expect(detail(), ReportDetail.totals);
    await tester.tap(find.byKey(const Key('report-audience')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('audience-accountant')));
    await tester.pumpAndSettle();
    expect(detail(), ReportDetail.everyEntry);
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('section-cashBook')))
          .value,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('report-cover')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cover-owner')), 'Wanjiru K.');
    await tester.enterText(find.byKey(const Key('cover-place')), 'Gikomba');
    await tester.tap(find.byKey(const Key('cover-save')));
    await settleFrames(tester);
    expect(find.textContaining('Wanjiru K. · Gikomba'), findsOneWidget);

    await tester.tap(find.byKey(const Key('report-save')));
    await tester.pumpAndSettle();
    expect(find.text('Monthly report for the accountant'), findsOneWidget);
    await tester.tap(find.byKey(const Key('report-name-save')));
    await settleFrames(tester);
    final settings = await tester.runAsync(
      () => c.read(reportSettingsProvider.future),
    );
    expect(settings!.saved.single.audience, ReportAudience.accountant);
    expect(settings.saved.single.detail, ReportDetail.everyEntry);
    expect(
      find.byKey(const Key('saved-Monthly report for the accountant')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('report-preview')));
    await settleFrames(tester);
    final doc = previewed.single;
    expect(doc.title, 'Monthly report for the accountant');
    expect(doc.coverLine, contains('Wanjiru K. · Gikomba'));
    expect(doc.blocks.map((b) => b.title), contains('Cash book'));

    await tester.tap(find.byKey(const Key('report-csv')));
    await settleFrames(tester);
    expect(sharer.files.single.fileName, endsWith('.csv'));
  });

  testAppWidgets('Make a report: choose a style and keep it with the report', (
    tester,
  ) async {
    final c = await pump(tester, path: AppRoutes.makeReport);
    expect(find.text('The usual look'), findsOneWidget);
    await tester.tap(find.byKey(const Key('report-style')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('style-cover')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('style-cover-band')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('style-words-formal')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('style-compare')));
    await tester.tap(find.byKey(const Key('style-compare')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('style-done')));
    await tester.tap(find.byKey(const Key('style-done')));
    await tester.pumpAndSettle();
    expect(
      find.text('Full band · Accounting terms · Compared'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('report-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-name-save')));
    await settleFrames(tester);
    final settings = await tester.runAsync(
      () => c.read(reportSettingsProvider.future),
    );
    final saved = settings!.saved.single.style;
    expect(saved.cover, ReportCoverStyle.band);
    expect(saved.wording, ReportWording.formal);
    expect(saved.compare, isTrue);

    await tester.tap(find.byKey(const Key('report-preview')));
    await settleFrames(tester);
    final doc = previewed.single;
    expect(doc.style, saved);
    expect(doc.blocks.first.title, 'Income statement');
  });
}
