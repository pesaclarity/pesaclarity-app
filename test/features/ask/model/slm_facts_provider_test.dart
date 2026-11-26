import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/domain/ask/data_source.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/features/ask/application/ask_providers.dart';
import 'package:pesaclarity/src/features/ask/model/slm_facts_loader.dart';
import 'package:pesaclarity/src/features/income/application/income_providers.dart';
import 'package:pesaclarity/src/features/insights/application/insights_providers.dart';
import 'package:pesaclarity/src/features/plan/application/budget_alert_providers.dart';
import 'package:pesaclarity/src/features/plan/application/plan_providers.dart'
    hide paydayProvider;

/// Answers every read after a real async gap, with nothing in the space.
class _SlowSource implements AskDataSource {
  @override
  Future<List<LedgerEntry>> entries(DateTime from, DateTime to) =>
      Future.delayed(const Duration(milliseconds: 10), () => const []);

  @override
  Future<List<AskLine>> balances() async => const [];

  @override
  Future<List<AskLine>> billsDue() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  test(
    'the facts load when read with no listener (no Ref after dispose)',
    () async {
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 20)),
          askDataSourceProvider.overrideWithValue(_SlowSource()),
          paydayProvider.overrideWith((ref) async => null),
          categoryNamesProvider.overrideWithValue(const AsyncData({})),
          planViewProvider.overrideWith((ref, month) => Future.error('none')),
          planCategoryNamesProvider.overrideWithValue(const {}),
        ],
      );
      addTearDown(container.dispose);

      // As the screen's Ask did: a read of the future, nothing listening.
      final facts = await container.read(slmFactsProvider.future);
      expect(facts.sections, isA<List<Object>>());
    },
  );
}
