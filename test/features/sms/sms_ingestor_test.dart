import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/payees_repository.dart';
import 'package:pesaclarity/src/data/repositories/review_inbox_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/payees/payee_identifier.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../helpers/sms_samples.dart';
import '../../helpers/test_app.dart';

Institution _institution(String id) =>
    institutionCatalogue.singleWhere((i) => i.id == id);

void main() {
  late AppDatabase db;
  late SmsIngestor ingestor;
  late DriftReviewInboxRepository reviewInbox;

  setUp(() {
    db = openTestDatabase();
    reviewInbox = DriftReviewInboxRepository(
      db,
      clock: () => DateTime.utc(2026, 11),
    );
    ingestor = SmsIngestor(
      accounts: DriftAccountsRepository(db),
      transactions: DriftTransactionsRepository(db),
      reviewInbox: reviewInbox,
    );
  });

  Future<List<TransactionRecord>> transactions() => (db.select(
    db.transactions,
  )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  test('parses on a background isolate into an institution account', () async {
    final summary = await ingestor.ingest(
      [mpesaSent(), mpesaTill()],
      [_institution('mpesa')],
    );

    expect(summary, const SmsIngestSummary(added: 2));
    final account = await db.select(db.accounts).getSingle();
    expect(account.name, 'M-Pesa');
    expect(account.type, AccountType.mpesa);
    expect(account.institutionId, 'mpesa');
    expect(account.openingDate.toUtc(), DateTime.utc(2026, 10, 26, 6, 15));

    final rows = await transactions();
    expect(rows.map((r) => r.receiptNo), ['TJA0000001', 'TJA0000004']);
    expect(rows.map((r) => r.accountId).toSet(), {account.id});
    expect(rows.first.messageHash, hashMessageBody(mpesaSent().body));
  });

  test('dedupes by the parser dedupe key, within an account', () async {
    final mpesa = [_institution('mpesa')];
    await ingestor.ingest([mpesaSent()], mpesa);

    // The same transaction read again, a minute's seconds later.
    final again = await ingestor.ingest([
      mpesaSent(receivedAt: DateTime.utc(2026, 10, 26, 6, 15, 40)),
      mpesaSent(),
    ], mpesa);
    expect(again, const SmsIngestSummary(duplicates: 2));

    final other = await ingestor.ingest([
      mpesaSent(receipt: 'TJA0000011'),
    ], mpesa);
    expect(other.added, 1);
    expect(await transactions(), hasLength(2));
    expect(await db.select(db.accounts).get(), hasLength(1));
  });

  test('drops messages from senders that are not selected', () async {
    final summary = await ingestor.ingest(
      [personal(), kcbDebit(), mpesaSent()],
      [_institution('mpesa')],
    );

    expect(summary, const SmsIngestSummary(added: 1, ignored: 2));
    expect(await transactions(), hasLength(1));
    expect(await db.select(db.reviewItems).get(), isEmpty);
    expect(
      await ingestor.ingest([mpesaSent()], const []),
      const SmsIngestSummary(ignored: 1),
    );
  });

  test('keeps a separate account per institution', () async {
    final summary = await ingestor.ingest(
      [mpesaSent(), kcbDebit()],
      [_institution('mpesa'), _institution('kcb')],
    );
    expect(summary.added, 2);
    final accounts = await db.select(db.accounts).get();
    expect(accounts.map((a) => (a.institutionId, a.type)), [
      ('mpesa', AccountType.mpesa),
      ('kcb', AccountType.bank),
    ]);
    final kcb = (await transactions()).last;
    expect(kcb.counterpartyKind, isNull);
    expect(kcb.balanceAfterMinor, 700000);
  });

  test('applies a named payee to new transactions', () async {
    final payees = DriftPayeesRepository(db);
    final payeeId = await payees.name(
      PayeeIdentifier.phone('0700 ***001')!,
      displayName: 'Jane (sister)',
    );

    await ingestor.ingest([mpesaSent()], [_institution('mpesa')]);
    expect((await transactions()).single.payeeId, payeeId);
  });

  test('sends unmatched messages to the review inbox once', () async {
    final mpesa = [_institution('mpesa')];
    final summary = await ingestor.ingest([mpesaNotice(), mpesaSent()], mpesa);
    expect(summary, const SmsIngestSummary(added: 1, forReview: 1));

    final item = (await reviewInbox.watchPending().first).single;
    expect(item.institutionId, 'mpesa');
    expect(item.sender, 'MPESA');
    expect(item.body, mpesaNotice().body);
    expect(item.messageHash, hashMessageBody(mpesaNotice().body));
    expect(item.reason, contains('No rule'));

    expect(
      (await ingestor.ingest([mpesaNotice()], mpesa)).forReview,
      0,
      reason: 'already waiting',
    );

    await reviewInbox.resolve(item.id);
    expect(await reviewInbox.watchPending().first, isEmpty);
    final resolved = await db.select(db.reviewItems).getSingle();
    expect(resolved.body, isNull, reason: 'text is deleted once resolved');
    expect(resolved.resolvedAt?.toUtc(), DateTime.utc(2026, 11));

    expect(
      (await ingestor.ingest([mpesaNotice()], mpesa)).forReview,
      0,
      reason: 'a resolved message does not come back',
    );
    expect(await db.select(db.reviewItems).get(), hasLength(1));
  });
}
