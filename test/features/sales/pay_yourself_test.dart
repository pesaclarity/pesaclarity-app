import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/spaces/space_categories.dart';
import 'package:pesaclarity/src/features/sales/application/pay_yourself.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase business;
  late AppDatabase personal;
  final now = eat(2026, 11, 1, 10);

  setUp(() {
    business = openTestDatabase();
    personal = openTestDatabase();
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(business),
        personalDatabaseProvider.overrideWithValue(personal),
        mainDatabaseProvider.overrideWithValue(personal),
        clockProvider.overrideWithValue(() => now),
        activeSpaceProvider.overrideWithValue(
          const Space(
            id: 'abc123',
            name: 'Amina Consulting',
            kind: SpaceKind.business,
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<String?> categoryKey(AppDatabase db, int? id) async => id == null
      ? null
      : (await (db.select(
          db.categories,
        )..where((c) => c.id.equals(id))).getSingle()).key;

  test(
    'cash: out of the business as your pay, into Personal at once',
    () async {
      final c = container();
      await c
          .read(payYourselfControllerProvider)
          .payYourself(
            amountMinor: 6000000,
            method: SalePaymentMethod.cash,
            as: PersonalPayAs.salary,
          );
      final out = (await business.select(business.transactions).get()).single;
      expect(out.direction, TransactionDirection.outflow);
      expect(await categoryKey(business, out.categoryOverrideId), ownerPayKey);

      final into = (await personal.select(personal.transactions).get()).single;
      expect(into.direction, TransactionDirection.inflow);
      expect(into.amountMinor, 6000000);
      expect(into.counterpartyName, 'Amina Consulting');
      expect(
        await categoryKey(personal, into.categoryOverrideId),
        payFromBusinessSeed.key,
      );
    },
  );

  test('M-Pesa: both sides file the messages when they come', () async {
    final c = container();
    final bizMpesa = await business
        .into(business.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'Business M-Pesa',
            type: AccountType.mpesa,
            openingDate: eat(2026, 10, 1, 0),
          ),
        );
    final myMpesa = await personal
        .into(personal.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: eat(2026, 10, 1, 0),
          ),
        );
    final pay = c.read(payYourselfControllerProvider);
    await pay.payYourself(
      amountMinor: 6000000,
      method: SalePaymentMethod.mpesa,
      as: PersonalPayAs.other,
    );
    expect(await c.read(salesControllerProvider).waiting(), hasLength(1));

    final sent = await business
        .into(business.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: bizMpesa,
            occurredAt: now.add(const Duration(minutes: 1)),
            amountMinor: 6000000,
            direction: TransactionDirection.outflow,
            kind: const Value(TransactionKind.sent),
            source: TransactionSource.sms,
          ),
        );
    await c.read(salesControllerProvider).matchWaiting();
    final out = await (business.select(
      business.transactions,
    )..where((t) => t.id.equals(sent))).getSingle();
    expect(await categoryKey(business, out.categoryOverrideId), ownerPayKey);

    final got = await personal
        .into(personal.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: myMpesa,
            occurredAt: now.add(const Duration(minutes: 1)),
            amountMinor: 6000000,
            direction: TransactionDirection.inflow,
            kind: const Value(TransactionKind.received),
            source: TransactionSource.sms,
          ),
        );
    expect(await pay.matchInPersonal(), 1);
    final into = await (personal.select(
      personal.transactions,
    )..where((t) => t.id.equals(got))).getSingle();
    expect(
      await categoryKey(personal, into.categoryOverrideId),
      'business_income',
    );
    expect(await pay.matchInPersonal(), 0);
  });
}
