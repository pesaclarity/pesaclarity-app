import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/sms/application/message_recheck.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../helpers/fake_sms_source.dart';
import '../../helpers/sms_samples.dart';
import '../../helpers/test_app.dart';

/// Amounts read as KES before Equity's USD messages were known (synthetic).
void main() {
  late AppDatabase db;
  late int legacy;
  final equity = institutionCatalogue.singleWhere((i) => i.id == 'equity');
  final kes = equityReceived();
  final usd = equityReceived(
    currency: 'USD',
    account: '0170****8765',
    amount: '1,500.00',
    receipt: 'EQB0000000000003',
  );

  setUp(() async {
    db = openTestDatabase();
    // One Equity account from before, holding both, all marked KES.
    legacy = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'Equity Bank',
            type: AccountType.bank,
            openingDate: DateTime.utc(2026),
            institutionId: const Value('equity'),
          ),
        );
    for (final (message, minor) in [(kes, 200000), (usd, 150000)]) {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: legacy,
              occurredAt: DateTime.utc(2026, 9, 12, 11, 5),
              amountMinor: minor,
              currency: const Value('KES'),
              direction: TransactionDirection.inflow,
              source: TransactionSource.sms,
              messageHash: Value(hashMessageBody(message.body)),
              fxRateCurrency: const Value('USD'),
              fxRateMicros: const Value(129000000),
            ),
          );
    }
  });
  tearDown(() => db.close());

  MessageRecheck recheck() => MessageRecheck(
    db: db,
    source: FakeSmsSource(inbox: [kes, usd]),
    accounts: DriftAccountsRepository(db),
    settings: DriftAppSettingsRepository(db),
    parse: (packs, messages) async => parseAll(packs, messages),
  );

  test(
    'moves each amount to the currency and account its message shows',
    () async {
      final notice = await recheck().runIfNeeded([equity]);
      final rows = await (db.select(
        db.transactions,
      )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
      final accounts = await db.select(db.accounts).get();
      expect(accounts, hasLength(2));
      final dollars = accounts.singleWhere((a) => a.currency == 'USD');
      expect(dollars.reference, '0170****8765');
      expect(rows.first.accountId, legacy);
      expect(rows.first.currency, 'KES');
      expect(rows.first.fxRateMicros, 129000000);
      expect((rows.last.accountId, rows.last.currency), (dollars.id, 'USD'));
      expect(rows.last.amountMinor, 150000);
      expect(rows.last.fxRateMicros, isNull);

      expect(notice!.count, 1);
      expect(notice.accountId, dollars.id);
      expect(notice.currency, 'USD');
      expect(notice.currencyChanged, isTrue);
      final saved = await DriftAppSettingsRepository(db)
          .readJson(MessageRecheck.noticeKey);
      expect(RecheckNotice.fromJson(saved)!.accountId, dollars.id);
    },
  );

  test('runs once for the same packs', () async {
    expect(await recheck().runIfNeeded([equity]), isNotNull);
    expect(await recheck().runIfNeeded([equity]), isNull);
  });
}
