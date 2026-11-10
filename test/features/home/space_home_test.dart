import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/domain/books/business_report.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/income/income_sources.dart';
import 'package:pesaclarity/src/domain/sales/sale_matching.dart';
import 'package:pesaclarity/src/domain/sales/sales_summary.dart';
import 'package:pesaclarity/src/domain/spaces/business_setup.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/spaces/space_summary.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/business_insights/application/business_report_providers.dart';
import 'package:pesaclarity/src/features/home/application/cash_flow_forecast_provider.dart';
import 'package:pesaclarity/src/features/home/application/health_index_provider.dart';
import 'package:pesaclarity/src/features/home/application/safe_to_spend_provider.dart';
import 'package:pesaclarity/src/features/home/application/upcoming_bills_provider.dart';
import 'package:pesaclarity/src/features/home/presentation/home_screen.dart';
import 'package:pesaclarity/src/features/income/application/income_providers.dart';
import 'package:pesaclarity/src/features/review/application/review_providers.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/business_setup_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/routing_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

class _Sources extends IncomeSourcesController {
  @override
  Future<IncomeSources> build() async => const IncomeSources({});
}

class _Setup extends BusinessSetupController {
  _Setup(this.sells);

  final BusinessSells sells;

  @override
  Future<BusinessSetup> build() async =>
      BusinessSetup(sells: sells, recordsStartedAt: DateTime.utc(2026, 11));
}

void main() {
  Future<void> pumpBusiness(
    WidgetTester tester,
    BusinessSells sells, {
    Map<SalePaymentMethod, int> sold = const {
      SalePaymentMethod.cash: 80000,
      SalePaymentMethod.mpesa: 290000,
      SalePaymentMethod.credit: 115000,
    },
    List<WaitingPayment> waiting = const [],
  }) async {
    // Tall enough for the whole of Today.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          businessSetupProvider.overrideWith(() => _Setup(sells)),
          salesTodayProvider.overrideWith(
            (ref) async => SalesToday(
              day: SalesDay(date: CalendarDate(2026, 11, 20), byWay: sold),
              usualMinor: 433000,
            ),
          ),
          waitingPaymentsProvider.overrideWith((ref) async => waiting),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 20, 6)),
          activeSpaceProvider.overrideWithValue(
            const Space(
              id: 'abc123',
              name: 'Vegetable stall',
              kind: SpaceKind.business,
            ),
          ),
          spaceSummaryProvider.overrideWith(
            (ref) async => SpaceSummary(
              kind: SpaceKind.business,
              from: CalendarDate(2026, 11, 1),
              inMinor: 2450000,
              outMinor: 1620000,
              balanceMinor: 400000,
              rows: const [
                SummaryRow(name: 'Sales', amountMinor: 2450000, isIncome: true),
                SummaryRow(
                  name: 'Stock and supplies',
                  amountMinor: 1100000,
                  isIncome: false,
                ),
              ],
              paidYourselfMinor: 600000,
            ),
          ),
          // Today's profit comes from the books in a business.
          businessProfitProvider.overrideWith(
            (ref, period) async => const ProfitAndLoss(
              income: [PnlLine('Sales', 2450000)],
              costs: [PnlLine('Stock and supplies', 1620000)],
            ),
          ),
          incomeSourcesProvider.overrideWith(_Sources.new),
          pendingReviewProvider.overrideWith((ref) => Stream.value(const [])),
          purposeQueueProvider.overrideWith((ref) async => const []),
          safeToSpendTodayProvider.overrideWith((ref) async => null),
          untilNextMoneyProvider.overrideWith((ref) async => null),
          cashFlowForecastProvider.overrideWith((ref) async => null),
          healthIndexProvider.overrideWith((ref) async => null),
          upcomingBillsProvider.overrideWith((ref) async => []),
          sharedLineQuestionsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a services business leads with profit, not safe to spend', (
    tester,
  ) async {
    await pumpBusiness(tester, BusinessSells.services);
    for (final quick in ['Got paid', 'Spent', 'Log hours', 'Billed']) {
      expect(find.text(quick), findsOneWidget);
    }

    expect(find.text('Vegetable stall'), findsOneWidget);
    expect(find.text('Profit this month'), findsOneWidget);
    expect(find.text('KES 8,300'), findsOneWidget);
    expect(find.text('Sales 24,500 · costs 16,200'), findsOneWidget);
    expect(find.text('Stock and supplies'), findsOneWidget);
    expect(find.byKey(const Key('space-paid-yourself')), findsOneWidget);
    expect(find.text('Safe to spend today'), findsNothing);
    expect(find.text('Runway at this pace'), findsNothing);
  });

  testWidgets('a business that sells products leads with sales today', (
    tester,
  ) async {
    await pumpBusiness(tester, BusinessSells.products);

    expect(find.text('Sales today'), findsOneWidget);
    expect(find.text('KES 4,850'), findsOneWidget);
    expect(
      find.text(
        'Cash 800 · M-Pesa 2,900 · On credit 1,150\nUp 12% on a usual '
        'Friday',
      ),
      findsOneWidget,
    );
    // Profit stays below, as a plain card.
    expect(find.text('Profit this month'), findsOneWidget);
    expect(find.text('8,300'), findsOneWidget);
    for (final quick in ['Bought', 'Got paid', 'Paid', 'Close the day']) {
      expect(find.text(quick), findsOneWidget);
    }
    // More ways to record is a card of its own, not a red link.
    expect(
      find.descendant(
        of: find.byKey(const Key('quick-more')),
        matching: find.text('More ways to record'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('More:'), findsNothing);
  });

  testWidgets('before the first sale, Sales today says what will show', (
    tester,
  ) async {
    await pumpBusiness(tester, BusinessSells.products, sold: const {});

    expect(find.text('Sales today'), findsOneWidget);
    expect(find.text('Sales show here as you sell.'), findsOneWidget);
    expect(find.textContaining('—'), findsNothing);
    expect(find.text('KES 0'), findsNothing);
  });

  testWidgets('a payment still to come is one row with its choices', (
    tester,
  ) async {
    await pumpBusiness(
      tester,
      BusinessSells.products,
      waiting: [
        WaitingPayment(
          id: 4,
          kind: WaitingKind.sale,
          method: SalePaymentMethod.mpesa,
          amountMinor: 30000,
          currency: 'KES',
          // 14:30 in Nairobi.
          at: DateTime.utc(2026, 11, 20, 11, 30),
          categoryId: 1,
          note: 'Avocados',
        ),
        WaitingPayment(
          id: 5,
          kind: WaitingKind.bought,
          method: SalePaymentMethod.mpesa,
          amountMinor: 120000,
          currency: 'KES',
          at: DateTime.utc(2026, 11, 20, 6, 5),
          categoryId: 2,
          note: 'Tomatoes',
          party: 'Test Supplier',
        ),
      ],
    );

    final sale = find.byKey(const Key('waiting-sale-4'));
    for (final text in ['Sale by M-Pesa', 'Avocados · 14:30', '300']) {
      expect(
        find.descendant(of: sale, matching: find.text(text)),
        findsOneWidget,
      );
    }
    expect(find.text('To Test Supplier by M-Pesa'), findsOneWidget);
    expect(find.text('1,200'), findsOneWidget);
    expect(find.textContaining('KES 300'), findsNothing);
    expect(find.byTooltip('More'), findsNothing);

    await tester.tap(sale);
    await tester.pumpAndSettle();
    expect(find.text('300 · Avocados · 14:30'), findsOneWidget);
    expect(find.byKey(const Key('waiting-choose')), findsOneWidget);
    expect(find.text('It was paid in cash'), findsOneWidget);
    await tester.tap(find.text('Delete it'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this sale?'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();

    // A purchase has no sale payments to choose.
    await tester.tap(find.byKey(const Key('waiting-bought-5')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('waiting-choose')), findsNothing);
    expect(find.byKey(const Key('waiting-cash')), findsOneWidget);
  });
}
