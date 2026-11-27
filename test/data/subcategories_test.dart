import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/categories_repository.dart';
import 'package:pesaclarity/src/data/repositories/export_repository.dart';
import 'package:pesaclarity/src/data/repositories/payees_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/export/export_tables.dart';
import 'package:pesaclarity/src/domain/payees/payee_identifier.dart';

void main() {
  late AppDatabase db;
  late DriftTransactionsRepository transactions;
  late DriftCategoriesRepository categories;
  late int account;
  late int transport;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    transactions = DriftTransactionsRepository(db);
    categories = DriftCategoriesRepository(db);
    account = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: DateTime.utc(2026),
          ),
        );
    transport = (await categories.byKey('transport'))!.id;
  });

  tearDown(() => db.close());

  Future<int> spend(int day, int amount, {int? category, String? to}) =>
      transactions.add(
        TransactionsCompanion.insert(
          accountId: account,
          occurredAt: DateTime.utc(2026, 11, day, 9),
          amountMinor: amount,
          direction: TransactionDirection.outflow,
          kind: const Value(TransactionKind.sent),
          source: TransactionSource.sms,
          counterpartyName: Value(to),
          categoryOverrideId: Value(category),
        ),
      );

  Future<List<int?>> categoryIds() async => [
    for (final e in await transactions.ledgerEntries(
      from: DateTime.utc(2026, 11),
      to: DateTime.utc(2026, 12),
    ))
      e.categoryId,
  ];

  test('a subcategory takes its parent type and day-to-day setting', () async {
    final uber = await categories.create(
      name: 'Uber',
      type: CategoryType.income,
      parentId: transport,
    );
    final row = await (db.select(
      db.categories,
    )..where((c) => c.id.equals(uber))).getSingle();
    expect(row.parentId, transport);
    expect(row.type, CategoryType.expense);
    expect(row.isDailySpending, isTrue);
    // The same name under the same parent is the same subcategory.
    expect(
      await categories.create(
        name: ' uber ',
        type: CategoryType.expense,
        parentId: transport,
      ),
      uber,
    );
  });

  test('subcategories go one level deep', () async {
    final uber = await categories.create(
      name: 'Uber',
      type: CategoryType.expense,
      parentId: transport,
    );
    expect(
      () => categories.create(
        name: 'Uber pool',
        type: CategoryType.expense,
        parentId: uber,
      ),
      throwsArgumentError,
    );
    expect(
      () => categories.create(
        name: 'Taxi',
        type: CategoryType.expense,
        parentId: 99999,
      ),
      throwsArgumentError,
    );
  });

  test('a name another category has is refused, unless it can move '
      'under the parent', () async {
    // The seeded Fuel is a top-level spending category: it moves.
    final fuel = (await categories.byKey('fuel'))!.id;
    expect(
      await categories.create(
        name: 'Fuel',
        type: CategoryType.expense,
        parentId: transport,
      ),
      fuel,
    );
    // Salary is income: it cannot sit under Transport.
    final salary = (await (db.select(
      db.categories,
    )..where((c) => c.type.equalsValue(CategoryType.income))).get()).first;
    expect(
      () => categories.create(
        name: salary.name,
        type: CategoryType.expense,
        parentId: transport,
      ),
      throwsA(isA<CategoryNameTaken>()),
    );
  });

  test('money in a subcategory adds up into its parent, and says which '
      'subcategory it was', () async {
    final uber = await categories.create(
      name: 'Uber',
      type: CategoryType.expense,
      parentId: transport,
    );
    await spend(2, 34500, category: uber);
    await spend(3, 13100, category: transport);
    final entries = await transactions.ledgerEntries(
      from: DateTime.utc(2026, 11),
      to: DateTime.utc(2026, 12),
    );
    expect(entries.map((e) => e.categoryId), [transport, transport]);
    expect(entries.map((e) => e.subcategoryId), [uber, null]);
    expect(entries.map((e) => e.ownCategoryId), [uber, transport]);
    expect(entries.every((e) => e.isDailySpending), isTrue);
    expect(entries.first.categoryType, CategoryType.expense);
  });

  test('deleting a subcategory moves its transactions and payees to the '
      'parent', () async {
    final uber = await categories.create(
      name: 'Uber',
      type: CategoryType.expense,
      parentId: transport,
    );
    await spend(2, 34500, category: uber);
    final payees = DriftPayeesRepository(db);
    final driver = PayeeIdentifier.phone('0700 000 002')!;
    await payees.name(driver, displayName: 'Uber', defaultCategoryId: uber);

    await categories.deleteSubcategory(uber);
    expect(await categoryIds(), [transport]);
    final payee = await db.select(db.payees).getSingle();
    expect(payee.defaultCategoryId, transport);
    expect(() => categories.deleteSubcategory(transport), throwsArgumentError);
  });

  test('export: the categories sheet names each parent, and transactions '
      'show the full name', () async {
    final uber = await categories.create(
      name: 'Uber',
      type: CategoryType.expense,
      parentId: transport,
    );
    await spend(2, 34500, category: uber);
    final exports = DriftExportRepository(db);
    final rows = await exports.transactions();
    expect(rows.single.categoryName, 'Transport › Uber');

    final table = categoriesTable(await exports.categories());
    expect(table.columns, [
      'Category',
      'Parent',
      'Type',
      'Day-to-day spending',
      'Added by you',
    ]);
    final uberRow = table.rows.firstWhere((r) => r.first == 'Uber');
    expect(uberRow, ['Uber', 'Transport', 'Spending', 'Yes', 'Yes']);
    final transportRow = table.rows.firstWhere((r) => r.first == 'Transport');
    expect(transportRow[1], '');
  });
}
