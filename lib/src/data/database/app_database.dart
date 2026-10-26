import 'package:drift/drift.dart';

import '../../domain/categories/default_categories.dart';
import '../../domain/enums.dart';
import 'tables.dart';

export '../../domain/enums.dart';

part 'app_database.g.dart';

/// The on-phone database. Opened through [openEncryptedDatabase] in the app.
@DriftDatabase(
  tables: [
    Accounts,
    Categories,
    Tags,
    Payees,
    PayeeIdentifiers,
    Debts,
    Goals,
    Transactions,
    TransactionTags,
    Recurring,
    BudgetItems,
    BudgetSnapshots,
    Imports,
    ParserPacks,
    SelectedInstitutions,
    AppSettings,
    ReviewItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await seedDefaultCategories();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(transactions, transactions.kind);
        await m.addColumn(transactions, transactions.feeMinor);
      }
      if (from < 3) {
        await m.alterTable(TableMigration(budgetSnapshots));
      }
      if (from < 4) {
        await m.addColumn(categories, categories.key);
        await m.create(categoriesKey);
        await m.alterTable(
          TableMigration(
            payees,
            columnTransformer: {
              payees.leakType: const CustomExpression<String>(
                "COALESCE(leak_type, 'none')",
              ),
            },
          ),
        );
        await m.addColumn(transactions, transactions.counterpartyKind);
        await m.addColumn(transactions, transactions.counterpartyValue);
        await m.create(transactionsCounterparty);
        await seedDefaultCategories();
      }
      if (from < 5) {
        await m.createTable(selectedInstitutions);
        await m.createTable(appSettings);
      }
      // Version 6 belongs to another change; this step checks before each
      // change so it is safe whichever order the two land in.
      if (from < 7) {
        await _addColumnIfMissing(m, accounts, accounts.institutionId);
        await _createIndexIfMissing(m, accountsInstitution);
        await _addColumnIfMissing(
          m,
          transactions,
          transactions.counterpartyName,
        );
        await _addColumnIfMissing(m, transactions, transactions.dedupeKey);
        await _addColumnIfMissing(
          m,
          transactions,
          transactions.balanceAfterMinor,
        );
        await _createIndexIfMissing(m, transactionsDedupe);
        if (!await _exists('table', reviewItems.actualTableName)) {
          await m.createTable(reviewItems);
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<bool> _exists(String type, String name) async => (await customSelect(
    'SELECT 1 FROM sqlite_master WHERE type = ? AND name = ?',
    variables: [Variable(type), Variable(name)],
  ).get()).isNotEmpty;

  Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo<Table, Object?> table,
    GeneratedColumn<Object> column,
  ) async {
    final columns = await customSelect(
      'PRAGMA table_info(${table.actualTableName})',
    ).map((row) => row.read<String>('name')).get();
    if (!columns.contains(column.name)) await m.addColumn(table, column);
  }

  Future<void> _createIndexIfMissing(Migrator m, Index index) async {
    if (!await _exists('index', index.entityName)) await m.create(index);
  }

  /// Adds the default categories that are missing by key or name. Runs once,
  /// when the database is created or upgraded, so a seeded category the user
  /// deletes stays deleted.
  Future<void> seedDefaultCategories() async {
    final existing = await select(categories).get();
    for (final seed in missingSeeds([
      for (final c in existing) (key: c.key, name: c.name),
    ])) {
      await into(categories).insert(
        CategoriesCompanion.insert(
          key: Value(seed.key),
          name: seed.name,
          type: seed.type,
          isDailySpending: Value(seed.isDailySpending),
        ),
      );
    }
  }
}
