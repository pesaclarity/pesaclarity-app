import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/review_inbox_repository.dart';
import 'package:pesaclarity/src/data/repositories/sms_scan_marks_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/sms/application/sms_scan_service.dart';

import '../../helpers/fake_sms_source.dart';
import '../../helpers/sms_samples.dart';
import '../../helpers/test_app.dart';

Institution _institution(String id) =>
    institutionCatalogue.singleWhere((i) => i.id == id);

void main() {
  late AppDatabase db;
  late FakeSmsSource source;
  late DriftSmsScanMarksRepository marks;
  late DateTime now;

  final today = DateTime.utc(2026, 10, 27, 9);

  setUp(() {
    db = openTestDatabase();
    now = today;
    marks = DriftSmsScanMarksRepository(db);
    source = FakeSmsSource(
      inbox: [
        mpesaSent(),
        mpesaTill(),
        mpesaNotice(),
        kcbDebit(),
        personal(),
        mpesaSent(
          receipt: 'TJA0000099',
          receivedAt: today.subtract(const Duration(days: 91)),
        ),
      ],
    );
    addTearDown(source.close);
  });

  SmsScanService service({int batchSize = 200}) => SmsScanService(
    source: source,
    ingestor: SmsIngestor(
      accounts: DriftAccountsRepository(db),
      transactions: DriftTransactionsRepository(db),
      reviewInbox: DriftReviewInboxRepository(db),
      parse: (packs, messages) async => parseAll(packs, messages),
    ),
    marks: marks,
    clock: () => now,
    batchSize: batchSize,
  );

  test('first scan reads 90 days from watched senders only', () async {
    final progress = <(int, int)>[];
    final summary = await service(batchSize: 2).scan([
      _institution('mpesa'),
    ], onProgress: (done, total) => progress.add((done, total)));

    expect(summary, const SmsIngestSummary(added: 2, forReview: 1));
    expect(source.reads.single.senders, {'MPESA'});
    expect(source.reads.single.since, today.subtract(const Duration(days: 90)));
    expect(progress, [(0, 3), (2, 3), (3, 3)]);
    expect(await marks.scannedUntil('mpesa'), today);
    expect(await marks.scannedUntil('kcb'), isNull);
    expect(source.releases, [today]);
  });

  test('later scans read only what is new, and new institutions '
      'their last 90 days', () async {
    await service().scan([_institution('mpesa')]);

    now = today.add(const Duration(hours: 2));
    source.inbox.add(
      mpesaSent(
        receipt: 'TJA0000012',
        receivedAt: today.add(const Duration(hours: 1)),
      ),
    );
    final summary = await service().scan([
      _institution('mpesa'),
      _institution('kcb'),
    ]);

    expect(summary, const SmsIngestSummary(added: 2));
    final [_, mpesa, kcb] = source.reads;
    expect(mpesa.senders, {'MPESA'});
    expect(mpesa.since, today);
    expect(kcb.senders, {'KCB'});
    expect(kcb.since, now.subtract(const Duration(days: 90)));
    expect(await db.select(db.transactions).get(), hasLength(4));
  });

  test('runs scans one at a time', () async {
    final scans = service();
    final results = await Future.wait([
      scans.scan([_institution('mpesa')]),
      scans.scan([_institution('mpesa')]),
    ]);
    expect(results.map((s) => s.added), [2, 0]);
    expect(await db.select(db.transactions).get(), hasLength(2));
  });

  test('a failed scan leaves no mark, so the next one retries', () async {
    final failing = SmsScanService(
      source: source,
      ingestor: SmsIngestor(
        accounts: DriftAccountsRepository(db),
        transactions: DriftTransactionsRepository(db),
        reviewInbox: DriftReviewInboxRepository(db),
        parse: (_, _) async => throw StateError('parser crashed'),
      ),
      marks: marks,
      clock: () => now,
    );
    await expectLater(failing.scan([_institution('mpesa')]), throwsStateError);
    expect(await marks.scannedUntil('mpesa'), isNull);
    expect(source.releases, isEmpty);
    expect((await service().scan([_institution('mpesa')])).added, 2);
  });

  test('an empty selection lets go of nothing', () async {
    await service().scan(const []);
    expect(source.releases, isEmpty);
  });
}
