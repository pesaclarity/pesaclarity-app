import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart'
    hide ParserPack;
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/balances_repository.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/sms/application/read_again.dart';
import 'package:pesaclarity/src/features/sms/application/scan_range_provider.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:pesaclarity/src/features/sms/domain/scan_range.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../helpers/fake_sms_source.dart';
import '../../helpers/sms_samples.dart';
import '../../helpers/test_app.dart';

/// An older reader: it misses the till payment, and reads the name in the
/// sent message wrongly (synthetic messages).
List<ParseResult> olderReader(
  List<ParserPack> packs,
  List<SmsMessage> messages,
) => [
  for (final result in parseAll(packs, messages))
    switch (result) {
      ParsedTransaction(receipt: 'TJA0000004') => Unmatched(
        packId: result.packId,
        message: messages.firstWhere(
          (m) => hashMessageBody(m.body) == result.rawHash,
        ),
        rawHash: result.rawHash,
        reason: 'no rule matched',
      ),
      ParsedTransaction(receipt: 'TJA0000001') => ParsedTransaction(
        packId: result.packId,
        packVersion: '0.0.1',
        ruleId: result.ruleId,
        type: result.type,
        direction: result.direction,
        amountMinor: result.amountMinor,
        currency: result.currency,
        time: result.time,
        timeFromMessage: result.timeFromMessage,
        rawHash: result.rawHash,
        feeMinor: result.feeMinor,
        balanceMinor: result.balanceMinor,
        receipt: result.receipt,
        counterparty: 'JANE',
        account: result.account,
        ownAccount: result.ownAccount,
        owedMinor: result.owedMinor,
        due: result.due,
      ),
      _ => result,
    },
];

void main() {
  late AppDatabase db;
  late FakeSmsSource source;
  late bool older;
  final now = DateTime.utc(2026, 11, 17, 9);
  final mpesa = institutionCatalogue.singleWhere((i) => i.id == 'mpesa');

  setUp(() async {
    db = openTestDatabase();
    older = true;
    source = FakeSmsSource(inbox: [mpesaSent(), mpesaTill(), kcbDebit()]);
    addTearDown(source.close);
    await DriftInstitutionsRepository(db).setSelected('mpesa', selected: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        smsSourceProvider.overrideWithValue(source),
        clockProvider.overrideWithValue(() => now),
        smsParseBatchProvider.overrideWithValue(
          (packs, messages) async =>
              older ? olderReader(packs, messages) : parseAll(packs, messages),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// The first scan, by the older reader.
  Future<void> firstScan(ProviderContainer c) async {
    await c.read(smsScanServiceProvider).scan([mpesa]);
    older = false;
  }

  Future<ReadAgainState> readAgain(ProviderContainer c) async {
    await c.read(readAgainControllerProvider.notifier).readAgain();
    return c.read(readAgainControllerProvider);
  }

  Future<List<TransactionRecord>> rows() => (db.select(
    db.transactions,
  )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  test('adds what the older reader missed and updates what it misread, '
      'once', () async {
    final c = container();
    await firstScan(c);
    expect((await rows()).map((r) => r.counterpartyName), ['JANE']);
    expect(await db.select(db.reviewItems).get(), hasLength(1));

    final first = await readAgain(c);
    expect(first.stage, ReadAgainStage.finished);
    expect(first.summary.added, 1);
    expect(first.summary.updated, 1);
    expect(first.total, 2);
    final after = await rows();
    expect(after.map((r) => r.receiptNo), ['TJA0000001', 'TJA0000004']);
    expect(after.first.counterpartyName, 'JANE DOE');
    expect(after.map((r) => r.readBy).toSet(), {
      '$engineVersion mpesa@${mpesa.pack.version}',
    });
    // The missed message leaves review: it is read now.
    final review = await db.select(db.reviewItems).getSingle();
    expect(review.resolvedAt, isNotNull);

    final second = await readAgain(c);
    expect((second.summary.added, second.summary.updated), (0, 0));
    expect(await rows(), hasLength(2));
  });

  test('leaves alone what the person set, and what they set aside', () async {
    final c = container();
    await firstScan(c);
    final row = (await rows()).single;
    final category = (await db.select(db.categories).get()).first.id;
    await (db.update(db.transactions)..where((t) => t.id.equals(row.id))).write(
      TransactionsCompanion(
        categoryOverrideId: Value(category),
        item: const Value('School shoes'),
      ),
    );
    // The person dismissed the till message in review.
    final item = await db.select(db.reviewItems).getSingle();
    await (db.update(db.reviewItems)..where((r) => r.id.equals(item.id))).write(
      ReviewItemsCompanion(resolvedAt: Value(now)),
    );

    final state = await readAgain(c);
    expect((state.summary.added, state.summary.updated), (0, 0));
    final kept = (await rows()).single;
    expect(kept.counterpartyName, 'JANE');
    expect(kept.categoryOverrideId, category);
    expect(kept.item, 'School shoes');
  });

  test('never brings back a copy the person removed', () async {
    final c = container();
    older = false;
    await c.read(smsScanServiceProvider).scan([mpesa]);
    final [sent, till] = await rows();
    await DriftBalancesRepository(db).removeCopy(till.id, keptId: sent.id);

    final state = await readAgain(c);
    expect(state.summary.added, 0);
    expect((await rows()).map((r) => r.id), [sent.id]);
  });

  test(
    'reads the ticked accounts from the chosen start, with progress',
    () async {
      final c = container();
      await firstScan(c);
      await c
          .read(scanRangeProvider.notifier)
          .choose(
            ScanRange(ScanPeriod.since, since: CalendarDate(2026, 10, 1)),
          );
      final seen = <(int, int)>[];
      c.listen(readAgainControllerProvider, (_, next) {
        if (next.reading) seen.add((next.done, next.total));
      });

      await readAgain(c);
      expect(seen.first, (0, 0));
      expect(seen, contains((0, 2)));
      expect(seen.last, (2, 2));
      final read = source.reads.last;
      expect(read.senders, {'MPESA'});
      expect(read.since, CalendarDate(2026, 10, 1).startInstant);
    },
  );

  group('on its own', () {
    Future<void> lastReadBy(String engine) =>
        DriftAppSettingsRepository(db).writeJson(
          ReadAgainController.settingsKey,
          LastRead(
            readers: ReaderVersions(engine, {'mpesa': mpesa.pack.version}),
            at: DateTime.utc(2026, 11, 14),
          ).toJson(),
        );

    test('reads again when the readers are newer, and says what changed '
        'on Home', () async {
      final c = container();
      await firstScan(c);
      await lastReadBy('0.0.1');

      await c.read(readAgainControllerProvider.notifier).readIfNewer([mpesa]);
      final notice = await c.read(readAgainNoticeProvider.future);
      expect(notice!.added, 1);
      expect(notice.updated, 1);
      expect(notice.institutionIds, ['mpesa']);
      expect(c.read(readAgainControllerProvider).stage, ReadAgainStage.idle);
      final last = (await c.read(lastReadProvider.future))!;
      expect(last.readers.engine, engineVersion);
      expect(last.at, now);
      expect((last.added, last.updated, last.messages), (1, 1, 2));
    });

    test('does nothing with the same readers', () async {
      final c = container();
      await firstScan(c);
      await lastReadBy(engineVersion);
      final reads = source.reads.length;

      await c.read(readAgainControllerProvider.notifier).readIfNewer([mpesa]);
      expect(source.reads, hasLength(reads));
      expect(await c.read(readAgainNoticeProvider.future), isNull);
    });

    test('shows nothing on Home when nothing changed', () async {
      final c = container();
      older = false;
      await c.read(smsScanServiceProvider).scan([mpesa]);
      await lastReadBy('0.0.1');

      await c.read(readAgainControllerProvider.notifier).readIfNewer([mpesa]);
      expect(source.reads.last.since, DateTime.utc(2000));
      expect(await c.read(readAgainNoticeProvider.future), isNull);
      expect(
        (await c.read(lastReadProvider.future))!.readers.engine,
        engineVersion,
      );
    });

    test('reads once what was read before the readers were noted', () async {
      final c = container();
      await firstScan(c);
      await db
          .update(db.transactions)
          .write(const TransactionsCompanion(readBy: Value(null)));

      await c.read(readAgainControllerProvider.notifier).readIfNewer([mpesa]);
      expect(await c.read(readAgainNoticeProvider.future), isNotNull);
      final reads = source.reads.length;
      await c.read(readAgainControllerProvider.notifier).readIfNewer([mpesa]);
      expect(source.reads, hasLength(reads));
    });

    test('with nothing read before, only notes the readers', () async {
      final c = container();
      await c.read(readAgainControllerProvider.notifier).readIfNewer([mpesa]);
      expect(source.reads, isEmpty);
      final last = (await c.read(lastReadProvider.future))!;
      expect(last.at, isNull);
      expect(last.readers.packs, {'mpesa': mpesa.pack.version});
    });
  });

  test('newer readers: the engine, or a pack read before', () {
    const last = ReaderVersions('0.3.0', {'mpesa': '0.3.1'});
    expect(
      const ReaderVersions('0.3.0', {'mpesa': '0.3.1'}).newerThan(last),
      isFalse,
    );
    expect(
      const ReaderVersions('0.4.0', {'mpesa': '0.3.1'}).newerThan(last),
      isTrue,
    );
    expect(
      const ReaderVersions('0.3.0', {'mpesa': '0.3.2'}).newerThan(last),
      isTrue,
    );
    expect(
      const ReaderVersions('0.3.0', {'kcb': '0.9.0'}).newerThan(last),
      isFalse,
    );
    expect(
      const ReaderVersions('0.2.9', {'mpesa': '0.3.1'}).newerThan(last),
      isFalse,
    );
  });
}
