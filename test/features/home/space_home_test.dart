import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/income/income_sources.dart';
import 'package:pesaclarity/src/domain/sales/sales_summary.dart';
import 'package:pesaclarity/src/domain/spaces/business_setup.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/spaces/space_summary.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
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
  Future<void> pumpBusiness(WidgetTester tester, BusinessSells sells) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          businessSetupProvider.overrideWith(() => _Setup(sells)),
          salesTodayProvider.overrideWith(
            (ref) async => SalesToday(
              day: SalesDay(
                date: CalendarDate(2026, 11, 20),
                byWay: const {
                  SalePaymentMethod.cash: 80000,
                  SalePaymentMethod.mpesa: 290000,
                  SalePaymentMethod.credit: 115000,
                },
              ),
              usualMinor: 433000,
            ),
          ),
          waitingPaymentsProvider.overrideWith((ref) async => const []),
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
    expect(find.byTooltip('Sell'), findsOneWidget);
  });
}
