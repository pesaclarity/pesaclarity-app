import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/domain/categoriser/rule_categoriser.dart';
import 'package:pesaclarity/src/domain/categoriser/suggester.dart';
import 'package:pesaclarity/src/features/categoriser/application/auto_categoriser.dart';

void main() {
  late AppDatabase db;
  late AutoCategoriser autoCategoriser;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    autoCategoriser = AutoCategoriser(db);

    // Seed an account
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(
        id: const Value(1),
        name: 'M-Pesa',
        type: AccountType.mpesa,
        openingDate: DateTime(2026),
      ),
    );

  });

  tearDown(() => db.close());

  test('auto-categorise writes confident predictions to transactions in local db', () async {
    final categories = await db.select(db.categories).get();
    final airtimeCat = categories.firstWhere((c) => c.key == 'airtime_data');

    // Airtime transaction (RuleCategoriser gives 0.9 confidence for airtime kind)
    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        id: const Value(101),
        accountId: 1,
        occurredAt: DateTime(2026, 10, 15, 12),
        amountMinor: 10000,
        direction: TransactionDirection.outflow,
        kind: const Value(TransactionKind.airtime),
        counterpartyName: const Value('SAFARICOM AIRTIME'),
        source: TransactionSource.sms,
      ),
    );

    final suggester = CategorySuggester(
      categoriser: const RuleCategoriser(),
      categories: [
        for (final c in categories)
          CategoryOption(id: c.id, type: c.type, key: c.key),
      ],
      corrections: const {},
    );

    final changed = await autoCategoriser.autoCategorise(suggester);
    expect(changed, 1);

    final tx = await (db.select(db.transactions)..where((t) => t.id.equals(101))).getSingle();
    expect(tx.autoCategoryId, airtimeCat.id);
    expect(tx.autoCategorySource, SuggestionSource.rules);
    expect(tx.autoCategoryConfidence, greaterThanOrEqualTo(0.6));
  });

  test('auto-categorise respects manual overrides and payee defaults', () async {
    // Transaction with manual override
    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        id: const Value(102),
        accountId: 1,
        occurredAt: DateTime(2026, 10, 15, 12),
        amountMinor: 10000,
        direction: TransactionDirection.outflow,
        kind: const Value(TransactionKind.airtime),
        categoryOverrideId: const Value(10),
        source: TransactionSource.sms,
      ),
    );

    final categories = await db.select(db.categories).get();
    final suggester = CategorySuggester(
      categoriser: const RuleCategoriser(),
      categories: [
        for (final c in categories)
          CategoryOption(id: c.id, type: c.type, key: c.key),
      ],
      corrections: const {},
    );

    final changed = await autoCategoriser.autoCategorise(suggester);
    expect(changed, 0);

    final tx = await (db.select(db.transactions)..where((t) => t.id.equals(102))).getSingle();
    expect(tx.autoCategoryId, isNull);
    expect(tx.categoryOverrideId, 10);
  });
}
