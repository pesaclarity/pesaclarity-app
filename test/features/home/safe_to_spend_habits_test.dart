import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/income/application/income_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    UserTimeZone.set(nairobiUtcOffset);
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // Monday 26 October 2026, 08:00 EAT.
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 26, 5)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    UserTimeZone.resetToDevice();
  });

  test('a lot on hand: safe to spend is a usual day, not all of it', () async {
    final mpesa = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingBalanceMinor: const Value(10000000),
            openingDate: DateTime.utc(2026, 9),
          ),
        );
    // KES 1,000 at a till each day for the last four weeks.
    for (var d = 1; d <= 28; d++) {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: mpesa,
              occurredAt: DateTime.utc(2026, 10, 26 - d, 9),
              amountMinor: 100000,
              direction: TransactionDirection.outflow,
              kind: const Value(TransactionKind.till),
              source: TransactionSource.sms,
            ),
          );
    }

    final plan = (await container.read(untilNextMoneyProvider.future))!;
    // 72,000 on hand. Spread over a week it would be over 9,000 a day.
    expect(plan.onHandMinor, 7200000);
    expect(plan.dailyMinor, 100000);
    expect(plan.fromUsualDay, isTrue);
    expect(plan.spareMinor, greaterThan(5000000));
  });
}
