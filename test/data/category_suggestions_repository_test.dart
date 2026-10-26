import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/category_suggestions_repository.dart';
import 'package:pesaclarity/src/domain/categoriser/features.dart';
import 'package:pesaclarity/src/domain/categoriser/suggester.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';

void main() {
  late AppDatabase db;
  late DriftCategorySuggestionsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftCategorySuggestionsRepository(db);
  });
  tearDown(() => db.close());

  Future<int> category(String key) async => (await (db.select(
    db.categories,
  )..where((c) => c.key.equals(key))).getSingle()).id;

  test(
    'confirming sets the category, remembers the payee and logs it',
    () async {
      final account = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'M-Pesa',
              type: AccountType.mpesa,
              openingDate: DateTime.utc(2026, 9),
            ),
          );
      final at = DateTime.utc(2026, 10, 27, 6);
      final id = await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: account,
              occurredAt: at,
              amountMinor: 30000,
              direction: TransactionDirection.outflow,
              source: TransactionSource.sms,
              counterpartyName: const Value('Tamu Tamu Hotel'),
              counterpartyKind: const Value(PayeeIdentifierKind.till),
              counterpartyValue: const Value('000111'),
            ),
          );
      final entry = LedgerEntry(
        id: id,
        accountId: account,
        occurredAt: at,
        amountMinor: 30000,
        direction: TransactionDirection.outflow,
        kind: TransactionKind.till,
        counterpartyName: 'Tamu Tamu Hotel',
        counterpartyKind: PayeeIdentifierKind.till,
        counterpartyValue: '000111',
      );
      final eatingOut = await category('eating_out');
      final groceries = await category('groceries');

      await repo.confirm(
        entry,
        categoryId: eatingOut,
        at: at,
        suggestion: CategorySuggestion(
          categoryId: groceries,
          key: 'groceries',
          confidence: 0.6,
          source: SuggestionSource.rules,
        ),
      );

      final stored = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(stored.categoryOverrideId, eatingOut);
      expect(await repo.watchCorrections().first, {
        'id:till:000111': eatingOut,
        'name:tamu tamu hotel': eatingOut,
      });

      final log = await db.select(db.categoryConfirmations).getSingle();
      expect(log.accepted, isFalse);
      expect(log.suggestedCategoryId, groceries);
      expect(log.suggestionSource, SuggestionSource.rules);
      expect(log.features, isNot(contains('amu')));

      final examples = await repo.trainingExamples();
      expect(examples.single.label, 'eating_out');
      expect(examples.single.featureSchemaVersion, featureSchemaVersion);
      expect(
        examples.single.features,
        encodeFeatures(categoriserInput(entry).features),
      );

      // A later choice for the same payee replaces the earlier one.
      await repo.confirm(entry, categoryId: groceries, at: at);
      expect((await repo.watchCorrections().first).values.toSet(), {groceries});
    },
  );
}
