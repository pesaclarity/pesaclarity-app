import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/categories_repository.dart';
import 'package:pesaclarity/src/data/repositories/export_repository.dart';
import 'package:pesaclarity/src/data/repositories/payees_repository.dart';
import 'package:pesaclarity/src/data/repositories/tags_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/payees/payee_identifier.dart';

void main() {
  late AppDatabase db;
  late DriftTransactionsRepository transactions;
  late DriftPayeesRepository payees;
  late DriftCategoriesRepository categories;
  late DriftTagsRepository tags;
  late DriftExportRepository exports;
  late int account;
  final brother = PayeeIdentifier.phone('0700 000 001')!;
  final shop = PayeeIdentifier.till('Mama Mboga Shop')!;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    transactions = DriftTransactionsRepository(db);
    payees = DriftPayeesRepository(db);
    categories = DriftCategoriesRepository(db);
    tags = DriftTagsRepository(db);
    exports = DriftExportRepository(db);
    account = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: DateTime.utc(2026),
          ),
        );
  });

  tearDown(() => db.close());

  Future<int> spend(
    int day,
    int amount,
    PayeeIdentifier who, {
    String? printed,
  }) => transactions.add(
    TransactionsCompanion.insert(
      accountId: account,
      occurredAt: DateTime.utc(2026, 10, day, 9),
      amountMinor: amount,
      direction: TransactionDirection.outflow,
      kind: const Value(TransactionKind.sent),
      source: TransactionSource.sms,
      counterpartyKind: Value(who.kind),
      counterpartyValue: Value(who.value),
      counterpartyName: Value(printed),
    ),
  );

  test('unnamed parties list until named, then the payee lists', () async {
    await spend(1, 30000, brother, printed: 'JOHN KAMAU');
    await spend(2, 20000, brother, printed: 'JOHN KAMAU');
    await spend(3, 5000, shop);

    final unnamed = await payees.watchUnnamed().first;
    expect(unnamed.map((p) => p.identifier), [brother, shop]);
    expect(unnamed.first.printedName, 'JOHN KAMAU');
    expect(unnamed.first.transactionCount, 2);
    expect(unnamed.first.outMinor, 50000);

    final friends = (await categories.byKey('friends_social'))!.id;
    await payees.name(
      brother,
      displayName: 'John (brother)',
      defaultCategoryId: friends,
      leakType: LeakType.family,
    );
    expect((await payees.watchUnnamed().first).map((p) => p.identifier), [
      shop,
    ]);
    final summary = (await payees.watchSummaries().first).single;
    expect(summary.payee.displayName, 'John (brother)');
    expect(summary.identifiers, [brother]);
    expect(summary.transactionCount, 2);
    expect(summary.categoryName, 'Friends and social');
  });

  test('the detail follows payee, override and tags as they change', () async {
    final id = await spend(1, 30000, brother);
    final details = transactions.watchDetail(id);
    var detail = (await details.first)!;
    expect(detail.payee, isNull);
    expect(detail.category, isNull);
    expect(detail.counterparty, brother);
    expect(detail.account.name, 'M-Pesa');

    final family = (await categories.byKey('family_support'))!.id;
    await payees.name(brother, displayName: 'John', defaultCategoryId: family);
    detail = (await transactions.watchDetail(id).first)!;
    expect(detail.payee!.displayName, 'John');
    expect(detail.category!.id, family);
    expect(detail.isCategoryOverridden, isFalse);

    final own = await categories.createForTransaction(
      id,
      name: 'Harusi contributions',
      type: CategoryType.expense,
    );
    detail = (await transactions.watchDetail(id).first)!;
    expect(detail.category!.id, own);
    expect(detail.payeeCategory!.id, family);
    expect(detail.isCategoryOverridden, isTrue);

    final wedding = await tags.findOrCreate('#Wedding');
    final reimburse = await tags.findOrCreate('reimbursable');
    await tags.tag(id, wedding);
    await tags.tag(id, reimburse);
    expect((await tags.watchTagsOf(id).first).map((t) => t.name), [
      'reimbursable',
      'wedding',
    ]);
    final usage = await tags.watchUsage().first;
    expect(usage.map((u) => (u.tag.name, u.count)), [
      ('reimbursable', 1),
      ('wedding', 1),
    ]);
  });

  test('export rows carry names, categories and tags', () async {
    final a = await spend(1, 30000, brother, printed: 'JOHN KAMAU');
    final b = await spend(15, 5000, shop);
    await spend(20, 7000, shop);
    final groceries = (await categories.byKey('groceries'))!.id;
    await payees.name(
      shop,
      displayName: 'Mama Mboga',
      defaultCategoryId: groceries,
      leakType: LeakType.lifestyle,
    );
    final trip = await tags.findOrCreate('roadtrip');
    await tags.tag(a, trip);
    await tags.tag(b, trip);

    final all = await exports.transactions();
    expect(all, hasLength(3));
    expect(all.first.party, 'JOHN KAMAU');
    expect(all.first.categoryName, isNull);
    expect(all.first.tags, ['roadtrip']);
    expect(all[1].payeeName, 'Mama Mboga');
    expect(all[1].categoryName, 'Groceries and household');
    expect(all[1].leakType, LeakType.lifestyle);

    final tagged = await exports.transactions(tagId: trip);
    expect(tagged.map((t) => t.id), [a, b]);
    final october = await exports.transactions(
      from: DateTime.utc(2026, 10, 10),
      to: DateTime.utc(2026, 10, 18),
    );
    expect(october.map((t) => t.id), [b]);

    final payeeRows = await exports.payees();
    expect(payeeRows.single.name, 'Mama Mboga');
    expect(payeeRows.single.identifiers, ['Till MAMA MBOGA SHOP']);
    expect(payeeRows.single.transactionCount, 2);
    expect(await exports.tags(), [(name: 'roadtrip', count: 2)]);
    expect((await exports.accounts()).single.name, 'M-Pesa');
    expect(await exports.categories(), isNotEmpty);
  });

  test('identifiers have readable labels', () {
    expect(PayeeIdentifier.phone('0712***945')!.label, '0712***945');
    expect(PayeeIdentifier.till('Naivas Juja')!.label, 'Till NAIVAS JUJA');
    expect(PayeeIdentifier.paybill('KPLC')!.label, 'Paybill KPLC');
    expect(
      PayeeIdentifier.paybill('KPLC', '1234')!.label,
      'Paybill KPLC, account 1234',
    );
  });
}
