import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/ask_repository.dart';
import 'package:pesaclarity/src/domain/ask/context.dart';
import 'package:pesaclarity/src/domain/ask/matcher.dart';
import 'package:pesaclarity/src/domain/ask/understanding.dart';
import 'package:pesaclarity/src/features/ask/application/ask_providers.dart';
import 'package:pesaclarity/src/features/ask/application/ask_settings.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

/// Synthetic records: an M-Pesa account, a food category, two payees.
Future<void> seedAsk(AppDatabase db) async {
  final account = await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingDate: eat(2026, 1, 1, 0),
          openingBalanceMinor: Value(kes(20000)),
        ),
      );
  final food = await db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(name: 'Food', type: CategoryType.expense),
      );
  final shop = await db
      .into(db.payees)
      .insert(PayeesCompanion.insert(displayName: 'Test Supermarket'));
  final market = await db
      .into(db.payees)
      .insert(PayeesCompanion.insert(displayName: 'Test Market'));
  var n = 0;
  Future<void> pay(DateTime at, int shillings, int payee, {int? category}) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: account,
          occurredAt: at,
          amountMinor: kes(shillings),
          direction: TransactionDirection.outflow,
          kind: const Value(TransactionKind.till),
          payeeId: Value(payee),
          categoryOverrideId: Value(category),
          source: TransactionSource.manual,
          receiptNo: Value('TEST${n++}'),
        ),
      );
  await pay(eat(2026, 10, 3), 3000, shop, category: food);
  await pay(eat(2026, 10, 18), 2920, shop, category: food);
  await pay(eat(2026, 10, 20), 4310, market, category: food);
  await pay(eat(2026, 9, 10), 12000, shop, category: food);
  await db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: account,
          occurredAt: eat(2026, 11, 10),
          amountMinor: kes(2500),
          direction: TransactionDirection.inflow,
          kind: const Value(TransactionKind.received),
          counterpartyName: const Value('PERSON A'),
          source: TransactionSource.manual,
        ),
      );
}

void main() {
  late AppDatabase db;
  late ProviderContainer c;

  setUp(() async {
    db = openTestDatabase();
    c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => eat(2026, 11, 13, 10)),
        askReaderRuntimeOpenerProvider.overrideWithValue(null),
      ],
    );
    addTearDown(c.dispose);
    await seedAsk(db);
  });

  test('lookups read the space\'s own records', () async {
    final engine = await c.read(askEngineProvider.future);
    final turn = await engine.ask(
      'How much did I spend on food last month?',
      context: AskContext.empty,
      now: eat(2026, 11, 13, 10),
    );
    expect(turn.answer.figureMinor, kes(10230));
    expect(turn.answer.rows.first.title, 'Test Supermarket');

    final source = c.read(askDataSourceProvider);
    final names = [for (final e in await source.entities()) e.name];
    expect(names, containsAll(['Food', 'Test Market', 'M-Pesa', 'Person A']));
    final balances = await source.balances();
    expect(balances.single.amountMinor, kes(20000 - 22230 + 2500));
  });

  test('a conversation is saved, renamed, updated and deleted', () async {
    final ask = c.read(askControllerProvider.notifier);
    await ask.ask('How much did I spend on food last month?');
    var session = c.read(askControllerProvider);
    expect(session.title, 'Food spending last month');
    expect(session.messages, hasLength(2));
    final repo = c.read(askRepositoryProvider);
    final saved = await repo.messages(session.conversationId!);
    expect(saved.last.answer!.figureMinor, kes(10230));

    await ask.ask('and only Test Market?');
    session = c.read(askControllerProvider);
    expect(
      session.context.entities.keys,
      containsAll([SlotKind.category, SlotKind.payee]),
    );
    expect(session.messages.last.answer!.figureMinor, kes(4310));

    await ask.dropTag(SlotKind.payee);
    expect(
      c.read(askControllerProvider).messages.last.answer!.figureMinor,
      kes(10230),
    );

    await ask.rename('Groceries');
    expect(
      (await repo.conversation(session.conversationId!))!.title,
      'Groceries',
    );
    await ask.updateAll();

    await ask.deleteConversation();
    expect(
      await c.read(askRepositoryProvider).watchConversations().first,
      isEmpty,
    );
  });

  test('with Save conversations off nothing is kept', () async {
    await c
        .read(askSettingsProvider.notifier)
        .save(const AskSettings(save: false));
    final ask = c.read(askControllerProvider.notifier);
    await ask.ask('Food last month');
    expect(c.read(askControllerProvider).messages, hasLength(2));
    expect(await db.select(db.askConversations).get(), isEmpty);
    expect(await db.select(db.askMessages).get(), isEmpty);
  });

  test('old conversations go after the Keep them for time', () async {
    final repo = c.read(askRepositoryProvider);
    await repo.start('Old', eat(2026, 1, 1));
    await repo.start('New', eat(2026, 11, 12));
    expect(
      await repo.purgeBefore(
        eat(2026, 11, 13).subtract(AskKeepFor.days30.duration!),
      ),
      1,
    );
    final left = await repo.watchConversations().first;
    expect(left.map((c) => c.title), ['New']);
  });

  test('shortcuts are learned once per word', () async {
    final repo = c.read(askRepositoryProvider);
    const a = AskEntity(SlotKind.payee, 'p:1', 'Test Supermarket');
    const b = AskEntity(SlotKind.payee, 'p:2', 'Test Market');
    await repo.learn('Test', a, eat(2026, 11, 13));
    await repo.learn('test', b, eat(2026, 11, 13));
    final all = await repo.shortcuts();
    expect(all.single.key, 'p:2');
    await repo.deleteAll();
    expect(await repo.shortcuts(), isEmpty);
  });

  test('Ask tables are among the tables Clear data empties', () {
    final names = {for (final t in db.allTables) t.actualTableName};
    expect(
      names,
      containsAll(['ask_conversations', 'ask_messages', 'ask_shortcuts']),
    );
    expect(db.askTables.map((t) => t.actualTableName), [
      'ask_messages',
      'ask_conversations',
      'ask_shortcuts',
    ]);
  });
}
