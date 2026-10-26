import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';

import '../../helpers/fake_sms_source.dart';
import '../../helpers/sms_samples.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = openTestDatabase();
    await DriftInstitutionsRepository(db).setSelected('mpesa', selected: true);
  });

  ProviderContainer container(FakeSmsSource source) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        smsSourceProvider.overrideWithValue(source),
        smsParseBatchProvider.overrideWithValue(
          (packs, messages) async => parseAll(packs, messages),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<List<SmsIngestSummary>> capture(ProviderContainer c, int count) async {
    final results = <SmsIngestSummary>[];
    final sub = c.listen(liveSmsCaptureProvider, (_, next) {
      if (next case AsyncData(:final value)) results.add(value);
    });
    addTearDown(sub.close);
    for (var i = 0; i < 50 && results.length < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return results;
  }

  test('catches up on the inbox, then adds watched messages as they '
      'arrive', () async {
    final source = FakeSmsSource(inbox: [mpesaSent()]);
    addTearDown(source.close);
    final c = container(source);

    final results = await capture(c, 1);
    expect(results.single.added, 1);
    expect(source.listenedSenders.single, {'MPESA'});

    source
      ..receive(personal())
      ..receive(mpesaTill());
    Future<List<TransactionRecord>> stored() =>
        db.select(db.transactions).get();
    for (var i = 0; i < 50 && (await stored()).length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect((await stored()).map((t) => t.receiptNo), [
      'TJA0000001',
      'TJA0000004',
    ]);
    expect(results.every((r) => r.ignored == 0), isTrue);
    expect(await db.select(db.reviewItems).get(), isEmpty);
  });

  test('does nothing without SMS access', () async {
    final source = FakeSmsSource(
      inbox: [mpesaSent()],
      dialogAnswer: SmsAccess.denied,
    );
    addTearDown(source.close);
    final results = await capture(container(source), 1);
    expect(results, isEmpty);
    expect(source.reads, isEmpty);
    expect(source.listenedSenders, isEmpty);
  });
}
