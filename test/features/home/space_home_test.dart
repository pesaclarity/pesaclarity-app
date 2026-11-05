import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/domain/income/income_sources.dart';
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
import 'package:pesaclarity/src/features/spaces/application/routing_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

class _Sources extends IncomeSourcesController {
  @override
  Future<IncomeSources> build() async => const IncomeSources({});
}

void main() {
  testWidgets('a business space leads with profit, not safe to spend', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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

    expect(find.text('Vegetable stall'), findsOneWidget);
    expect(find.text('Profit this month'), findsOneWidget);
    expect(find.text('KES 8,300'), findsOneWidget);
    expect(find.text('Sales 24,500 · costs 16,200'), findsOneWidget);
    expect(find.text('Stock and supplies'), findsOneWidget);
    expect(find.byKey(const Key('space-paid-yourself')), findsOneWidget);
    expect(find.text('Safe to spend today'), findsNothing);
    expect(find.text('Runway at this pace'), findsNothing);
  });
}
