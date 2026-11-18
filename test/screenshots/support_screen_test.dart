// The Support screen of the F-Droid build for the marketing screenshots,
// with a made-up payee and links (README, Screenshots).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/domain/budget/safe_to_spend.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/home/application/cash_flow_forecast_provider.dart';
import 'package:pesaclarity/src/features/home/application/health_index_provider.dart';
import 'package:pesaclarity/src/features/home/application/safe_to_spend_provider.dart';
import 'package:pesaclarity/src/features/home/application/upcoming_bills_provider.dart';
import 'package:pesaclarity/src/features/review/application/review_providers.dart';
import 'package:pesaclarity/src/features/support/application/support_providers.dart';
import 'package:pesaclarity/src/features/support/domain/support.dart';
import 'package:pesaclarity/src/features/support/presentation/support_screen.dart';

import '../helpers/test_app.dart';
import 'harness.dart';

final _now = DateTime.utc(2026, 11, 14, 6);

List<Override> _overrides(AppDatabase db) => [
  appDatabaseProvider.overrideWithValue(db),
  clockProvider.overrideWithValue(() => _now),
  appFlavorProvider.overrideWithValue(AppFlavor.foss),
  supportDefinesProvider.overrideWithValue((
    url: 'https://pay.example.org/pay/@test?amount={amount}',
    payees: 'Test Payee',
    costs: 'https://example.org/sponsor/',
  )),
  pendingReviewProvider.overrideWith((ref) => Stream.value(const [])),
  safeToSpendTodayProvider.overrideWith(
    (ref) async => SafeToSpend(
      today: CalendarDate(2026, 11, 14),
      budgetMinor: 3000000,
      spentBeforeTodayMinor: 1950000,
      spentTodayMinor: 20000,
      weekdaysLeft: 11,
      weekendDaysLeft: 5,
      weekdayLimitMinor: 100000,
      weekendLimitMinor: 81000,
    ),
  ),
  cashFlowForecastProvider.overrideWith((ref) async => null),
  healthIndexProvider.overrideWith((ref) async => null),
  upcomingBillsProvider.overrideWith((ref) async => []),
];

Future<void> _seed(AppDatabase db) => DriftAppSettingsRepository(db).writeJson(
  SupportStateController.settingsKey,
  SupportState(firstSeenAt: _now.subtract(const Duration(days: 40))).toJson(),
);

void main() {
  screenshot('support', statusBar: false, (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => _seed(db));
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(db),
        child: shotApp(const SupportScreen()),
      ),
    );
    await settleFrames(tester);
    await snap(tester);
  });
}
