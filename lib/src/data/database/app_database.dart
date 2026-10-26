import 'package:drift/drift.dart';

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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(transactions, transactions.kind);
        await m.addColumn(transactions, transactions.feeMinor);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
