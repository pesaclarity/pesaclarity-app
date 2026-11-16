import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/ledger/not_yet_sorted.dart';
import 'package:pesaclarity/src/domain/reader/rule_reader.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/home/application/not_yet_sorted_provider.dart';
import 'package:pesaclarity/src/features/review/application/review_providers.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late int mpesa;

  setUp(() async {
    db = openTestDatabase();
    mpesa = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: eat(2026, 10, 1),
          ),
        );
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        messageReaderProvider.overrideWith(
          (ref) async => const RuleMessageReader(),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// What the provider gives while something watches it, as Home does.
  Future<NotYetSorted> read() {
    final c = container()..listen(notYetSortedProvider, (_, _) {});
    return c.read(notYetSortedProvider.future);
  }

  Future<void> received(int shillings, String phone, {int day = 10}) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: mpesa,
          occurredAt: eat(2026, 11, day),
          amountMinor: kes(shillings),
          direction: TransactionDirection.inflow,
          kind: const Value(TransactionKind.received),
          source: TransactionSource.sms,
          counterpartyName: const Value('TEST PERSON'),
          counterpartyKind: const Value(PayeeIdentifierKind.phone),
          counterpartyValue: Value(phone),
        ),
      );

  Future<void> toCheck(String body, String hash) => db
      .into(db.reviewItems)
      .insert(
        ReviewItemsCompanion.insert(
          institutionId: 'mpesa',
          sender: 'MPESA',
          receivedAt: eat(2026, 11, 12),
          messageHash: hash,
          body: Value(body),
          reason: 'no rule matched',
        ),
      );

  test('empty when nothing waits', () async {
    final sorted = await read();
    expect(sorted.isEmpty, isTrue);
  });

  test('adds unnamed money in and the messages the reader reads', () async {
    await received(3000, '0700000000', day: 8);
    await received(1000, '0700000000');
    await received(500, '0711000000');
    await toCheck(
      'Dear Customer, KES 1,250.00 has been paid to EXAMPLE GROCERS on '
          '12/11/26 at 14:05. Ref QW12ER34TY.',
      'a',
    );
    await toCheck('Your verification code is 482913. Do not share it.', 'b');

    final sorted = await read();
    expect(sorted.peopleNotNamed, 2);
    expect(sorted.messagesToCheck, 2);
    expect(sorted.amountMinor, kes(3000 + 1000 + 500 + 1250));
    expect(sorted.firstNotNamed, CalendarDate(2026, 11, 8));
  });

  test('a message with no amount is counted, not added', () async {
    await toCheck('Your verification code is 482913. Do not share it.', 'b');
    final sorted = await read();
    expect(sorted.messagesToCheck, 1);
    expect(sorted.hasAmount, isFalse);
  });
}
