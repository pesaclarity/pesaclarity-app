import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/categories_repository.dart';
import 'package:pesaclarity/src/data/repositories/payees_repository.dart';
import 'package:pesaclarity/src/data/repositories/tags_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/categories/default_categories.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/payees/payee_identifier.dart';
import 'package:pesaclarity/src/domain/tags/tag_totals.dart';

void main() {
  late AppDatabase db;
  late DriftTransactionsRepository transactions;
  late DriftPayeesRepository payees;
  late DriftCategoriesRepository categories;
  late DriftTagsRepository tags;
  late int account;

  final from = DateTime.utc(2026, 10);
  final to = DateTime.utc(2026, 11);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    transactions = DriftTransactionsRepository(db);
    payees = DriftPayeesRepository(db);
    categories = DriftCategoriesRepository(db);
    tags = DriftTagsRepository(db);
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
    int amount, {
    PayeeIdentifier? counterparty,
    TransactionKind kind = TransactionKind.till,
  }) => transactions.add(
    TransactionsCompanion.insert(
      accountId: account,
      occurredAt: DateTime.utc(2026, 10, day, 9),
      amountMinor: amount,
      direction: TransactionDirection.outflow,
      kind: Value(kind),
      source: TransactionSource.sms,
      counterpartyKind: Value(counterparty?.kind),
      counterpartyValue: Value(counterparty?.value),
    ),
  );

  Future<LedgerEntry> entryOf(int id) async =>
      (await transactions.ledgerEntries(
        from: from,
        to: to,
      )).singleWhere((e) => e.id == id);

  group('categories', () {
    test('a new database starts with the default Kenyan set', () async {
      final all = await categories.watchAll().first;
      expect(all, hasLength(defaultCategories.length));
      final groceries = await categories.byKey('groceries');
      expect(groceries!.name, 'Groceries and household');
      expect(groceries.isDailySpending, isTrue);
      expect(await categories.byKey(uncategorisedKey), isNull);
    });

    test('seeding again adds nothing', () async {
      await db.seedDefaultCategories();
      await db.seedDefaultCategories();
      expect(
        await categories.watchAll().first,
        hasLength(defaultCategories.length),
      );
    });

    test('creates a category inline from a transaction', () async {
      final tx = await spend(3, 20000);
      final id = await categories.createForTransaction(
        tx,
        name: '  Boda  boda ',
        type: CategoryType.expense,
        isDailySpending: true,
      );
      final entry = await entryOf(tx);
      expect(entry.categoryId, id);
      expect(entry.isDailySpending, isTrue);
      expect(
        (await categories.watchAll().first).singleWhere((c) => c.id == id).name,
        'Boda boda',
      );

      expect(
        await categories.create(name: 'boda BODA', type: CategoryType.expense),
        id,
        reason: 'same name reuses the category',
      );
      await expectLater(
        categories.create(name: '  ', type: CategoryType.expense),
        throwsArgumentError,
      );
      await expectLater(categories.setOverride(9999, id), throwsArgumentError);
    });
  });

  group('payees', () {
    test('naming a payee reaches past and future transactions', () async {
      final groceries = (await categories.byKey('groceries'))!.id;
      final eatingOut = (await categories.byKey('eating_out'))!.id;
      final till = PayeeIdentifier.till('Test Grocer')!;

      final before = await spend(2, 50000, counterparty: till);
      final overridden = await spend(3, 30000, counterparty: till);
      await categories.setOverride(overridden, eatingOut);
      final other = await spend(
        3,
        10000,
        counterparty: PayeeIdentifier.till('Other Shop'),
      );

      final grocer = await payees.name(
        till,
        displayName: ' Test  Grocer ',
        defaultCategoryId: groceries,
        leakType: LeakType.lifestyle,
      );
      final after = await spend(5, 40000, counterparty: till);

      for (final id in [before, after]) {
        final entry = await entryOf(id);
        expect(entry.payeeId, grocer);
        expect(entry.payeeName, 'Test Grocer');
        expect(entry.categoryId, groceries);
        expect(entry.leakType, LeakType.lifestyle);
      }
      final kept = await entryOf(overridden);
      expect(kept.payeeId, grocer);
      expect(kept.categoryId, eatingOut, reason: 'override wins');
      expect(kept.leakType, LeakType.lifestyle);
      expect((await entryOf(other)).payeeId, isNull);
      expect((await entryOf(other)).categoryId, isNull);

      await payees.update(
        grocer,
        defaultCategoryId: const Value(null),
        leakType: LeakType.none,
      );
      final cleared = await entryOf(before);
      expect(cleared.categoryId, isNull, reason: 'now Uncategorised');
      expect(cleared.leakType, LeakType.none);
      expect((await entryOf(overridden)).categoryId, eatingOut);
    });

    test('masked numbers link only when one payee fits', () async {
      final masked = await spend(
        4,
        100000,
        kind: TransactionKind.sent,
        counterparty: PayeeIdentifier.phone('0700***001'),
      );
      final friend = await payees.name(
        PayeeIdentifier.phone('0700000001')!,
        displayName: 'Test Friend',
        leakType: LeakType.friends,
      );
      expect((await entryOf(masked)).payeeId, friend);

      await payees.name(
        PayeeIdentifier.phone('0700999001')!,
        displayName: 'Another Friend',
      );
      expect(
        (await entryOf(masked)).payeeId,
        isNull,
        reason: 'two payees fit the masked number',
      );
    });

    test(
      'moving an identifier to another payee relinks its transactions',
      () async {
        final till = PayeeIdentifier.till('Test Grocer')!;
        final tx = await spend(2, 50000, counterparty: till);
        await payees.name(till, displayName: 'First');
        final second = await payees.name(
          PayeeIdentifier.till('Test Grocer Two')!,
          displayName: 'Second',
        );
        await payees.addIdentifier(second, till);
        expect((await entryOf(tx)).payeeId, second);
        expect((await payees.directory()).resolve(till)?.id, second);
      },
    );
  });

  group('tags', () {
    test('tag, filter and total, uncategorised included', () async {
      final fuel = (await categories.byKey('fuel'))!.id;
      final trip = await tags.findOrCreate('#RoadTrip');
      expect(await tags.findOrCreate('roadtrip'), trip);
      final wedding = await tags.findOrCreate('wedding');

      final petrol = await spend(3, 400000);
      await categories.setOverride(petrol, fuel);
      final snacks = await spend(3, 15000);
      final untagged = await spend(4, 70000);
      await tags.tag(petrol, trip);
      await tags.tag(snacks, trip);
      await tags.tag(snacks, wedding);
      await tags.tag(snacks, wedding);

      expect((await tags.tagsOf(snacks)).map((t) => t.name), [
        'roadtrip',
        'wedding',
      ]);
      expect(
        (await transactions.ledgerEntries(
          from: from,
          to: to,
          tagId: trip,
        )).map((e) => e.id),
        [petrol, snacks],
      );
      expect(
        (await transactions.watchRecent(tagId: wedding).first).map((r) => r.id),
        [snacks],
      );

      final entries = await transactions.ledgerEntries(from: from, to: to);
      expect(entries.singleWhere((e) => e.id == untagged).tagIds, isEmpty);
      final totals = tagTotals(entries, from: from, to: to);
      expect(totals[trip]!.totals.spendingMinor, 415000);
      expect(totals[trip]!.spendingByCategory, {fuel: 400000, null: 15000});
      expect(totals[wedding]!.spendingByCategory, {null: 15000});

      await tags.untag(snacks, wedding);
      expect((await tags.tagsOf(snacks)).map((t) => t.name), ['roadtrip']);
      await expectLater(tags.findOrCreate('#'), throwsArgumentError);
    });
  });
}
