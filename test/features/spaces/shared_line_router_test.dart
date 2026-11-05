import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/data/repositories/space_move_repository.dart';
import 'package:pesaclarity/src/domain/spaces/line_routing.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/spaces/application/routing_providers.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase personal;
  late AppDatabase business;
  late RoutingRules rules;
  late SharedLineRouter router;
  const shop = 'shop1';
  final now = eat(2026, 11, 20);

  setUp(() {
    personal = openTestDatabase();
    business = openTestDatabase();
    rules = const RoutingRules(sharedLines: {'mpesa': shop});
    router = SharedLineRouter(
      personal: personal,
      moveFromPersonal: DriftSpaceMoveRepository(
        personal,
        (id) async => (business, false),
      ),
      rules: () async => rules,
      remember: (key, spaceId) async => rules = rules.withPerson(key, spaceId),
      now: () => now,
    );
  });

  Future<int> account(AppDatabase db, String institution) => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: institution,
          type: AccountType.mpesa,
          openingDate: eat(2026, 10, 1, 0),
          institutionId: Value(institution),
        ),
      );

  var receipt = 0;
  Future<int> received(
    int accountId,
    String phone,
    String name, {
    int daysAgo = 1,
    int shillings = 650,
  }) => personal
      .into(personal.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: accountId,
          occurredAt: now.subtract(Duration(days: daysAgo)),
          amountMinor: kes(shillings),
          direction: TransactionDirection.inflow,
          kind: const Value(TransactionKind.received),
          counterpartyKind: const Value(PayeeIdentifierKind.phone),
          counterpartyValue: Value(phone),
          counterpartyName: Value(name),
          dedupeKey: Value('R${receipt++}'),
          source: TransactionSource.sms,
        ),
      );

  Future<int> count(AppDatabase db) async =>
      (await db.select(db.transactions).get()).length;

  test('asks about recent payments on a shared line only', () async {
    final mpesa = await account(personal, 'mpesa');
    final bank = await account(personal, 'equity');
    await received(mpesa, '254700000001', 'GRACE WAMBUI');
    await received(mpesa, '254700000002', 'PETER K', daysAgo: 40); // too old
    await received(bank, '254700000003', 'SALARY'); // not shared
    final questions = await router.pending(shop);
    expect(questions.map((q) => q.name), ['GRACE WAMBUI']);
    expect(questions.single.isInflow, isTrue);
    expect(await router.pending('another-business'), isEmpty);
  });

  test('a business sale moves to the business; personal stays', () async {
    final mpesa = await account(personal, 'mpesa');
    await received(mpesa, '254700000001', 'GRACE WAMBUI');
    await received(mpesa, '254700000009', 'MUM', shillings: 2000);
    final [mum, grace] = await router.pending(shop);
    expect(grace.name, 'GRACE WAMBUI');

    await router.answer(
      grace,
      businessId: shop,
      forBusiness: true,
      always: false,
    );
    await router.answer(
      mum,
      businessId: shop,
      forBusiness: false,
      always: false,
    );
    expect(await count(business), 1);
    expect(await count(personal), 1);
    expect(await router.pending(shop), isEmpty);
    // Nothing is remembered without "Always".
    expect(rules.people, isEmpty);
  });

  test('"Always" sorts the same person on their own from then on', () async {
    final mpesa = await account(personal, 'mpesa');
    await received(mpesa, '254700000001', 'GRACE WAMBUI', daysAgo: 3);
    final [first] = await router.pending(shop);
    await router.answer(
      first,
      businessId: shop,
      forBusiness: true,
      always: true,
    );
    expect(rules.people, {'phone:254700000001': shop});
    expect(rules.learntFor(shop), (business: 1, personal: 0));

    await received(mpesa, '254700000001', 'GRACE WAMBUI');
    await received(mpesa, '254700000009', 'MUM');
    final left = await router.pending(shop);
    expect(left.map((q) => q.name), ['MUM']);
    expect(await count(business), 2);

    await router.answer(
      left.single,
      businessId: shop,
      forBusiness: false,
      always: true,
    );
    await received(mpesa, '254700000009', 'MUM', daysAgo: 0);
    expect(await router.pending(shop), isEmpty);
    expect(await count(personal), 2);
  });

  test('moved payments are not read back into Personal', () async {
    final mpesa = await account(personal, 'mpesa');
    await received(mpesa, '254700000001', 'GRACE WAMBUI');
    final [q] = await router.pending(shop);
    await router.answer(q, businessId: shop, forBusiness: true, always: false);
    final moved = await personal.select(personal.movedTransactions).get();
    expect(moved.single.spaceId, shop);
  });

  test('choosing where a line is read', () async {
    final businessLines = DriftInstitutionsRepository(business);
    final personalLines = DriftInstitutionsRepository(personal);
    Future<void> choose(LineChoice choice) async {
      // The controller's line logic, without Riverpod.
      await businessLines.setSelected(
        'mpesa',
        selected: choice == LineChoice.thisBusiness,
      );
      await personalLines.setSelected(
        'mpesa',
        selected: choice != LineChoice.thisBusiness,
      );
      rules = rules.withLine('mpesa', choice == LineChoice.both ? shop : null);
    }

    await choose(LineChoice.thisBusiness);
    expect(await businessLines.selectedIds(), {'mpesa'});
    expect(await personalLines.selectedIds(), isEmpty);
    expect(rules.sharedWith(shop), isEmpty);

    await choose(LineChoice.both);
    expect(await businessLines.selectedIds(), isEmpty);
    expect(await personalLines.selectedIds(), {'mpesa'});
    expect(rules.sharedWith(shop), {'mpesa'});
    expect(
      lineChoiceOf(inBusiness: false, inPersonal: true, shared: true),
      LineChoice.both,
    );

    await choose(LineChoice.personal);
    expect(rules.sharedWith(shop), isEmpty);
    expect(
      lineChoiceOf(inBusiness: false, inPersonal: true, shared: false),
      LineChoice.personal,
    );
  });

  test('person keys are the same in every space', () {
    expect(
      personKey(kind: PayeeIdentifierKind.phone, value: '254700000001'),
      'phone:254700000001',
    );
    expect(personKey(name: '  Grace   Wambui '), 'name:grace wambui');
    expect(personKey(), isNull);
    expect(personalSpaceId, 'personal');
  });
}
