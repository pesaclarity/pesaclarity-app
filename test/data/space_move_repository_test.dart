import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/space_move_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';

void main() {
  late AppDatabase personal;
  late AppDatabase business;
  late DriftSpaceMoveRepository moves;
  late int mpesa;

  TransactionsCompanion sale(int accountId, {String key = 'QK1|150000|t'}) =>
      TransactionsCompanion.insert(
        accountId: accountId,
        occurredAt: DateTime.utc(2026, 11, 3, 9),
        amountMinor: 150000,
        direction: TransactionDirection.inflow,
        kind: const Value(TransactionKind.received),
        source: TransactionSource.sms,
        counterpartyName: const Value('TEST CUSTOMER'),
        receiptNo: const Value('QK1'),
        dedupeKey: Value(key),
      );

  setUp(() async {
    personal = AppDatabase(NativeDatabase.memory());
    business = AppDatabase(NativeDatabase.memory());
    await business.becomeSpace(SpaceKind.business);
    moves = DriftSpaceMoveRepository(
      personal,
      (spaceId) async => (business, false),
    );
    mpesa = await personal
        .into(personal.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: DateTime.utc(2026),
            institutionId: const Value('mpesa'),
          ),
        );
  });

  tearDown(() async {
    await personal.close();
    await business.close();
  });

  test('moves a transaction, its account and its category key', () async {
    final id = await DriftTransactionsRepository(personal).add(sale(mpesa));
    final received = await (personal.select(
      personal.categories,
    )..where((c) => c.key.equals('money_received'))).getSingle();
    await (personal.update(personal.transactions)
          ..where((t) => t.id.equals(id)))
        .write(TransactionsCompanion(categoryOverrideId: Value(received.id)));

    await moves.move(id, 'abc123');

    expect(await personal.select(personal.transactions).get(), isEmpty);
    final moved = await business.select(business.transactions).getSingle();
    expect(moved.amountMinor, 150000);
    expect(moved.receiptNo, 'QK1');
    final account = await business.select(business.accounts).getSingle();
    expect(account.institutionId, 'mpesa');
    expect(moved.accountId, account.id);
    final category = await (business.select(
      business.categories,
    )..where((c) => c.id.equals(moved.categoryOverrideId!))).getSingle();
    expect(category.key, 'money_received');

    // Reading the same message again in Personal does not bring it back.
    final added = await DriftTransactionsRepository(personal)
        .addNew([sale(mpesa)]);
    expect(added, 0);
    final other = await DriftTransactionsRepository(personal)
        .addNew([sale(mpesa, key: 'QK2|150000|t')]);
    expect(other, 1);
  });

  test('a category the other space lacks is left unset', () async {
    final id = await DriftTransactionsRepository(personal).add(sale(mpesa));
    final betting = await (personal.select(
      personal.categories,
    )..where((c) => c.key.equals('betting'))).getSingle();
    await (personal.update(personal.transactions)
          ..where((t) => t.id.equals(id)))
        .write(TransactionsCompanion(categoryOverrideId: Value(betting.id)));

    await moves.move(id, 'abc123');
    final moved = await business.select(business.transactions).getSingle();
    expect(moved.categoryOverrideId, isNull);
  });
}
