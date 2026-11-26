import 'package:drift/drift.dart' show Value;
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/share_repository.dart';
import 'package:pesaclarity/src/domain/sharing/share_model.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';

import '../domain/fixtures.dart';
import 'test_app.dart';

/// One simulated phone in a shared space, with its own clock.
class Phone {
  Phone(this.name, {SpaceKind kind = SpaceKind.household})
    : db = openTestDatabase() {
    repo = ShareRepository(db, kind: kind, nowMillis: () => now);
  }

  final String name;
  final AppDatabase db;
  late final ShareRepository repo;

  /// Sat 21 Nov 2026, 9:00 in Nairobi, until a test moves it.
  int now = eat(2026, 11, 21, 9).millisecondsSinceEpoch;

  Future<String> get id async => (await repo.state())!.myMemberId;

  Future<int> account(String name) => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: name,
          type: AccountType.cash,
          openingDate: eat(2026, 1, 1),
          openingBalanceMinor: Value(kes(5000)),
        ),
      );

  /// Money out on [account] to [payee], under Groceries and household.
  Future<int> spend(int account, String payee, int amount) async {
    final groceries = await (db.select(
      db.categories,
    )..where((c) => c.key.equals('groceries'))).getSingleOrNull();
    return db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: account,
            occurredAt: eat(2026, 11, 21, 10),
            amountMinor: kes(amount),
            direction: TransactionDirection.outflow,
            source: TransactionSource.manual,
            counterpartyName: Value(payee),
            categoryOverrideId: Value(groceries?.id),
          ),
        );
  }

  Future<List<String>> payees() async => [
    for (final t in await (db.select(db.transactions)).get())
      t.counterpartyName ?? '',
  ]..sort();

  /// Sends everything new to [to], and [to] applies it.
  Future<void> sendTo(Phone to) async {
    final out = await repo.buildUpdate(
      await to.id,
      spaceName: 'Home at Kilimani',
    );
    await repo.markSent(out);
    await to.repo.apply(out.bytes);
  }
}

/// [owner] makes the space and invites each of [others] as [role] … and
/// sends them the space.
Future<void> share(
  Phone owner,
  Map<Phone, ShareRole> others, {
  Set<Phone> withAccount = const {},
}) async {
  if (await owner.repo.state() == null) {
    await owner.repo.start(myName: owner.name);
  }
  for (final MapEntry(key: phone, value: role) in others.entries) {
    // Their phone makes its own key and a join request; the Owner's phone
    // makes the invite from it.
    final (request, pair, _) = await ShareRepository.makeJoinRequest(
      phone.name,
    );
    final (invite, _, _) = await owner.repo.invite(
      request: request,
      role: role,
      spaceName: 'Home at Kilimani',
    );
    await phone.repo.join(
      invite,
      mine: pair,
      myName: phone.name,
      hasAccount: withAccount.contains(phone),
    );
    await owner.sendTo(phone);
  }
}

/// "Home at Kilimani": You, Jane (Member) and Brian (Viewer, no account),
/// with Jane's Naivas, a Mama Mboga typed in for Brian, a water bill whose
/// category you changed, and the Food plan you and Jane both changed.
/// Returns your phone, with Jane's latest file not yet applied, and that
/// file.
Future<(Phone, List<int>)> kilimani() async {
  final me = Phone('You');
  final jane = Phone('Jane Wairimu');
  final brian = Phone('Brian');
  final cash = await me.account('Cash box');
  await me.db
      .into(me.db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'Household M-Pesa',
          type: AccountType.mpesa,
          openingDate: eat(2026, 1, 1),
        ),
      );
  await me.db
      .into(me.db.budgetItems)
      .insert(
        BudgetItemsCompanion.insert(
          month: 202611,
          name: 'Food',
          amountMinor: kes(15000),
          kind: BudgetItemKind.values.first,
        ),
      );
  me.now = eat(2026, 11, 3, 9).millisecondsSinceEpoch;
  await share(me, {jane: ShareRole.member}, withAccount: {jane});
  jane.now = eat(2026, 11, 3, 10).millisecondsSinceEpoch;
  await jane.sendTo(me);
  me.now = eat(2026, 11, 9, 9).millisecondsSinceEpoch;
  await share(me, {brian: ShareRole.viewer});
  await me.spend(cash, 'KPLC tokens', 1000);
  final taxi = await me.spend(cash, 'Taxi', 600);
  me.now = eat(2026, 11, 20, 18).millisecondsSinceEpoch;
  await me.sendTo(jane);

  // Sat: Jane adds and records for Brian; you remove the taxi and set
  // Food to 18,000.
  jane.now = eat(2026, 11, 21, 8).millisecondsSinceEpoch;
  final janeMpesa = (await (jane.db.select(
    jane.db.accounts,
  )..where((a) => a.name.equals('Household M-Pesa'))).getSingle()).id;
  final janeCash = (await (jane.db.select(
    jane.db.accounts,
  )..where((a) => a.name.equals('Cash box'))).getSingle()).id;
  final water = await jane.spend(janeMpesa, 'Water bill', 1200);
  final mboga = await jane.spend(janeCash, 'Mama Mboga', 450);
  await jane.repo.recordLocalChanges();
  await jane.repo.addedFor(mboga, await brian.id);
  me.now = eat(2026, 11, 21, 9).millisecondsSinceEpoch;
  await jane.sendTo(me);
  me.now = eat(2026, 11, 21).millisecondsSinceEpoch;
  final bills = await (me.db.select(
    me.db.categories,
  )..where((c) => c.key.equals('utilities'))).getSingleOrNull();
  if (bills != null) {
    await me.db.customStatement(
      'UPDATE transactions SET category_override_id = ? '
      "WHERE counterparty_name = 'Water bill'",
      [bills.id],
    );
  }
  await me.db.customStatement('DELETE FROM transactions WHERE id = ?', [taxi]);
  await me.db.customStatement(
    "UPDATE budget_items SET amount_minor = ? WHERE name = 'Food'",
    [kes(18000)],
  );
  await me.repo.recordLocalChanges();

  // Sun: Jane sets Food to 20,000 and adds 13 more.
  jane.now = eat(2026, 11, 22, 8).millisecondsSinceEpoch;
  await jane.db.customStatement(
    "UPDATE budget_items SET amount_minor = ? WHERE name = 'Food'",
    [kes(20000)],
  );
  await jane.spend(janeMpesa, 'Naivas', 2340);
  for (var i = 1; i <= 13; i++) {
    await jane.spend(janeCash, 'Shop $i', 100 + i);
  }
  await jane.db.customStatement(
    "UPDATE transactions SET item = 'Water, November' WHERE id = ?",
    [water],
  );
  final out = await jane.repo.buildUpdate(await me.id, spaceName: 'Home');
  await jane.repo.markSent(out);
  me.now = eat(2026, 11, 22, 9, 41).millisecondsSinceEpoch;
  return (me, out.bytes);
}

/// A join request from a phone that is never used again.
Future<String> joinRequest(String name) async =>
    (await ShareRepository.makeJoinRequest(name)).$1;

/// Home at Kilimani with changes that wait (group approvals): Wanjiku
/// (Owner) added a taxi, Brian a Mama Mboga; Jane asks to delete the taxi
/// and to change Mama Mboga from 450 to 540, in a file Wanjiku has
/// applied. Returns Wanjiku's phone, then Jane's.
Future<(Phone, Phone)> waitingKilimani() async {
  final me = Phone('Wanjiku');
  final jane = Phone('Jane Wairimu');
  final brian = Phone('Brian');
  final cash = await me.account('Cash box');
  me.now = eat(2026, 11, 3, 9).millisecondsSinceEpoch;
  await share(me, {jane: ShareRole.member, brian: ShareRole.member});
  me.now = eat(2026, 11, 21, 9).millisecondsSinceEpoch;
  await me.spend(cash, 'Taxi', 600);
  await me.sendTo(brian);
  brian.now = eat(2026, 11, 21, 10).millisecondsSinceEpoch;
  final brianCash = (await (brian.db.select(
    brian.db.accounts,
  )..where((a) => a.name.equals('Cash box'))).getSingle()).id;
  await brian.spend(brianCash, 'Mama Mboga', 450);
  await brian.sendTo(me);
  me.now = eat(2026, 11, 21, 13).millisecondsSinceEpoch;
  await me.sendTo(jane);
  jane.now = eat(2026, 11, 22, 8).millisecondsSinceEpoch;
  await jane.db.customStatement(
    "DELETE FROM transactions WHERE counterparty_name = 'Taxi'",
  );
  await jane.db.customStatement(
    'UPDATE transactions SET amount_minor = ? '
    "WHERE counterparty_name = 'Mama Mboga'",
    [kes(540)],
  );
  await jane.repo.recordLocalChanges();
  me.now = eat(2026, 11, 22, 9).millisecondsSinceEpoch;
  await jane.sendTo(me);
  me.now = eat(2026, 11, 22, 9, 41).millisecondsSinceEpoch;
  return (me, jane);
}
