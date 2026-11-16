import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/ask/context.dart';
import 'package:pesaclarity/src/features/ask/application/ask_providers.dart';
import 'package:pesaclarity/src/features/balances/application/balances_providers.dart';
import 'package:pesaclarity/src/features/insights/application/insights_providers.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';
import '../balances/balances_harness.dart';

void main() {
  late AppDatabase db;
  late ScenarioAccounts ids;
  late ProviderContainer c;

  setUp(() async {
    db = openTestDatabase();
    ids = await seedScenario(db);
    c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => scenarioNow),
        askReaderRuntimeOpenerProvider.overrideWithValue(null),
      ],
    );
    addTearDown(c.dispose);
    addTearDown(db.close);
  });

  test(
    "Ask's M-Pesa balance is the Balances screen's, from the journal",
    () async {
      final engine = await c.read(askEngineProvider.future);
      final turn = await engine.ask(
        "what's my M-Pesa balance",
        context: AskContext.empty,
        now: scenarioNow,
      );

      final overview = await c.read(balancesOverviewProvider.future);
      final mpesa = overview.byId(ids.mpesa)!;
      // The wallet is at 0 and 1,300 is owed to Fuliza: Balances shows
      // -1,300, and so does Ask.
      expect(mpesa.heldMinor, kes(-1300));
      expect(turn.answer.figureMinor, mpesa.heldMinor);
    },
  );

  test('the total is the Balances total, savings left out', () async {
    final engine = await c.read(askEngineProvider.future);
    final turn = await engine.ask(
      'How much money do I have?',
      context: AskContext.empty,
      now: scenarioNow,
    );
    final overview = await c.read(balancesOverviewProvider.future);
    // -1,300 + 50 + 100: the Sacco's savings are listed but not added.
    expect(overview.totalMinor('KES'), kes(-1150));
    expect(turn.answer.figureMinor, overview.totalMinor('KES'));
    expect(turn.answer.totalRows, 4);
  });

  test(
    "this month's charges are Insights', Fuliza's from the journal",
    () async {
      final engine = await c.read(askEngineProvider.future);
      final turn = await engine.ask(
        'How much did I pay in charges this month?',
        context: AskContext.empty,
        now: scenarioNow,
      );
      final leakage = (await c.read(insightsSummaryProvider.future))
          .current
          .leakage;
      expect(leakage.fulizaMinor, greaterThan(0));
      expect(turn.answer.figureMinor, leakage.feesMinor + leakage.fulizaMinor);
    },
  );

  test('every balance Ask lists matches the Balances screen', () async {
    final lines = await c.read(askDataSourceProvider).balances();
    final overview = await c.read(balancesOverviewProvider.future);
    expect(
      {for (final l in lines) l.name: l.amountMinor},
      {for (final a in overview.accounts) a.account.name: a.heldMinor},
    );
  });
}
