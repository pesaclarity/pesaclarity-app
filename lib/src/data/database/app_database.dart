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
    DebtInstalments,
    Goals,
    LentLoans,
    LoanPayments,
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
    CategoryCorrections,
    CategoryConfirmations,
    Subscriptions,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 13;

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
      if (from < 6) await _addDebtPlanner(m);
      // Checks before each change, like the debt planner step, so it is
      // safe to run more than once.
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
      if (from < 8) {
        for (final column in [
          imports.institutionId,
          imports.openingBalanceMinor,
          imports.transactionCount,
          imports.addedCount,
          imports.duplicateCount,
          imports.unreadCount,
          imports.result,
        ]) {
          await _addColumnIfMissing(m, imports, column);
        }
      }
      if (from < 9) await _addGoalsAndLending(m);
      if (from < 10) {
        for (final TableInfo<Table, Object?> table in [
          categoryCorrections,
          categoryConfirmations,
        ]) {
          if (!await _exists('table', table.actualTableName)) {
            await m.createTable(table);
          }
        }
      }
      if (from < 11) {
        if (!await _exists('table', subscriptions.actualTableName)) {
          await m.createTable(subscriptions);
        }
        await _createIndexIfMissing(m, subscriptionsPayee);
      }
      if (from < 12) await _splitLoansAndSnacks();
      if (from < 13) {
        await _addColumnIfMissing(m, transactions, transactions.autoCategoryId);
        await _addColumnIfMissing(m, transactions, transactions.autoCategorySource);
        await _addColumnIfMissing(
          m,
          transactions,
          transactions.autoCategoryConfidence,
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Debt balances, payees, custom order and family instalments.
  ///
  /// Safe to run more than once, so it holds whichever version number it
  /// ends up under when other migrations land beside it.
  Future<void> _addDebtPlanner(Migrator m) async {
    final existing = await customSelect('PRAGMA table_info(debts)')
        .map((row) => row.read<String>('name'))
        .get();
    for (final column in [
      debts.balanceMinor,
      debts.balanceAsOf,
      debts.payeeId,
      debts.customOrder,
    ]) {
      if (!existing.contains(column.name)) await m.addColumn(debts, column);
    }
    await m.createTable(debtInstalments);
  }

  /// Saved amounts on goals, money lent, and part payments on family loans.
  /// Safe to run more than once.
  Future<void> _addGoalsAndLending(Migrator m) async {
    await _addColumnIfMissing(m, goals, goals.savedMinor);
    for (final TableInfo<Table, Object?> table in [lentLoans, loanPayments]) {
      if (!await _exists('table', table.actualTableName)) {
        await m.createTable(table);
      }
    }
  }

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
  /// Categories version 2: Fuliza apart from other loans, and snacks apart
  /// from eating out. The seeded loan category gets its new name unless the
  /// person renamed it, the new ones are added, and Fuliza repayments filed
  /// under loans move to Fuliza.
  Future<void> _splitLoansAndSnacks() async {
    await customStatement(
      "UPDATE categories SET name = 'Loan repayment' "
      "WHERE key = 'loan_repayment' AND name = 'Loan and Fuliza repayment' "
      "AND NOT EXISTS (SELECT 1 FROM categories WHERE name = 'Loan repayment')",
    );
    await seedDefaultCategories();
    await customStatement(
      'UPDATE transactions SET category_override_id = '
      "(SELECT id FROM categories WHERE key = 'fuliza_repayment') "
      "WHERE kind = 'fulizaRepayment' AND category_override_id = "
      "(SELECT id FROM categories WHERE key = 'loan_repayment') "
      "AND EXISTS (SELECT 1 FROM categories WHERE key = 'fuliza_repayment')",
    );
  }

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
