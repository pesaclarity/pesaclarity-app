import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/reader_templates_repository.dart';
import 'package:pesaclarity/src/data/repositories/review_inbox_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/reader/message_reading.dart';
import 'package:pesaclarity/src/domain/reader/model_reader.dart';
import 'package:pesaclarity/src/domain/reader/reader_tokens.dart';
import 'package:pesaclarity/src/domain/reader/rule_reader.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/review/application/review_draft.dart';
import 'package:pesaclarity/src/features/review/application/review_providers.dart';
import 'package:pesaclarity/src/features/review/data/reader_store.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../helpers/fake_sms_source.dart';
import '../../helpers/test_app.dart';

// New wording from a selected sender that the M-Pesa pack does not match.
SmsMessage _newWording({
  String amount = '1,250.00',
  String payee = 'EXAMPLE GROCERS',
  int day = 29,
}) => SmsMessage(
  sender: 'MPESA',
  body:
      'Dear Customer, KES $amount has been paid to $payee on $day/10/26 '
      'at 14:05. Ref QW12ER34TY.',
  receivedAt: DateTime.utc(2026, 10, day, 11, 6),
);

class _FakeRuntime implements ReaderRuntime {
  var closed = false;

  @override
  (List<List<double>>, List<double>) run(List<int> input) => (
    List.generate(
      readerMaxTokens,
      (_) => [1.0, for (var i = 1; i < ReaderField.values.length; i++) 0.0],
    ),
    [0.1, 0.1, 0.8],
  );

  @override
  void close() => closed = true;
}

void main() {
  group('loading the reader', () {
    late Directory folder;
    setUp(() => folder = Directory.systemTemp.createTempSync('reader'));
    tearDown(() => folder.deleteSync(recursive: true));

    final model = Uint8List.fromList(List.generate(64, (i) => i));
    Map<String, Object?> manifest({int schema = readerSchemaVersion}) => {
      'model_file': 'reader.tflite',
      'model_sha256': sha256.convert(model).toString(),
      'model_size_bytes': model.length,
      'reader_schema_version': schema,
      'max_tokens': readerMaxTokens,
      'hash_buckets': readerHashBuckets,
      'outputs': {
        'fields': {
          'labels': [
            'other',
            'amount',
            'counterparty',
            'date',
            'time',
            'balance',
            'reference',
            'fee',
          ],
        },
        'kind': {
          'labels': ['money_out', 'money_in', 'not_transaction'],
        },
      },
    };

    Future<MessageReader> load() =>
        loadReader(folder, openRuntime: (_) => _FakeRuntime());

    test('uses the rules until a model is installed', () async {
      expect(await load(), isA<RuleMessageReader>());
    });

    test('opens an installed model that fits', () async {
      File('${folder.path}/reader.tflite').writeAsBytesSync(model);
      File('${folder.path}/$readerManifestFile')
          .writeAsStringSync(jsonEncode(manifest()));
      final reader = await load();
      expect(reader, isA<ModelMessageReader>());
      expect(reader.read('Hello').kind, MessageKind.notTransaction);
    });

    test('refuses a model for another schema or with other bytes', () async {
      File('${folder.path}/reader.tflite').writeAsBytesSync(model);
      File('${folder.path}/$readerManifestFile')
          .writeAsStringSync(jsonEncode(manifest(schema: 99)));
      expect(await load(), isA<RuleMessageReader>());
      File('${folder.path}/$readerManifestFile')
          .writeAsStringSync(jsonEncode(manifest()));
      File('${folder.path}/reader.tflite').writeAsBytesSync([1, 2, 3]);
      expect(await load(), isA<RuleMessageReader>());
    });
  });

  group('templates during capture', () {
    late AppDatabase db;
    late DriftReaderTemplatesRepository templates;
    late SmsIngestor ingestor;
    final mpesa = [institutionCatalogue.singleWhere((i) => i.id == 'mpesa')];

    setUp(() {
      db = openTestDatabase();
      templates = DriftReaderTemplatesRepository(db);
      ingestor = SmsIngestor(
        accounts: DriftAccountsRepository(db),
        transactions: DriftTransactionsRepository(db),
        reviewInbox: DriftReviewInboxRepository(db),
        templates: templates,
        parse: (packs, messages) async => parseAll(packs, messages),
      );
    });

    test('new wording waits for review until a layout is saved', () async {
      final first = _newWording();
      expect((await ingestor.ingest([first], mpesa)).forReview, 1);

      final reading = const RuleMessageReader().read(first.body);
      final draft = ReviewDraft.fromReading(reading);
      expect(draft.amountMinor, 125000);
      expect(draft.counterparty, 'Example Grocers');
      await templates.add('mpesa', learnTemplate(first.body, reading, draft)!);

      final next = _newWording(
        amount: '80.00',
        payee: 'SUNRISE BAKERY',
        day: 30,
      );
      final summary = await ingestor.ingest([next], mpesa);
      expect(summary.forReview, 0);
      expect(summary.added, 1);
      final row = await db.select(db.transactions).getSingle();
      expect(row.amountMinor, 8000);
      expect(row.counterpartyName, 'Sunrise Bakery');
      expect(row.direction, TransactionDirection.outflow);
      expect(row.receiptNo, 'QW12ER34TY');
    });

    test('a changed amount saves no layout', () {
      final message = _newWording();
      final reading = const RuleMessageReader().read(message.body);
      final edited = ReviewDraft.fromReading(reading).copyWith(amountMinor: 1);
      expect(learnTemplate(message.body, reading, edited), isNull);
    });
  });

  testAppWidgets('checks a message from Home and adds it', (tester) async {
    final db = openTestDatabase();
    final sms = FakeSmsSource(inbox: [_newWording()]);
    addTearDown(sms.close);
    await pumpApp(
      tester,
      db: db,
      sms: sms,
      overrides: [
        messageReaderProvider.overrideWith(
          (ref) async => const RuleMessageReader(),
        ),
      ],
    );
    await finishOnboarding(tester);

    await tester.tap(find.byKey(const Key('home-review')));
    await tester.pumpAndSettle();
    expect(find.text('Messages to check'), findsOneWidget);
    expect(find.textContaining('Suggested: Money out · 1,250'), findsOneWidget);

    await tester.tap(find.textContaining('Dear Customer'));
    await tester.pumpAndSettle();
    expect(find.text('Check this message'), findsOneWidget);
    expect(find.text('Example Grocers'), findsOneWidget);
    expect(find.text('QW12ER34TY'), findsOneWidget);

    await tapText(tester, 'Add transaction');
    final row = await tester.runAsync(
      () => db.select(db.transactions).getSingle(),
    );
    expect(row!.amountMinor, 125000);
    final kept = await tester.runAsync(
      () => db.select(db.readerTemplates).get(),
    );
    expect(kept, hasLength(1));
    final items = await tester.runAsync(
      () => db.select(db.reviewItems).getSingle(),
    );
    expect(items!.body, isNull);
    expect(items.resolvedAt, isNotNull);
  });

  testAppWidgets('sets a notice aside', (tester) async {
    final db = openTestDatabase();
    final sms = FakeSmsSource(
      inbox: [
        SmsMessage(
          sender: 'MPESA',
          body: 'Your verification code is 482913. Do not share it.',
          receivedAt: DateTime.utc(2026, 10, 29, 9),
        ),
      ],
    );
    addTearDown(sms.close);
    await pumpApp(
      tester,
      db: db,
      sms: sms,
      overrides: [
        messageReaderProvider.overrideWith(
          (ref) async => const RuleMessageReader(),
        ),
      ],
    );
    await finishOnboarding(tester);
    await tester.tap(find.byKey(const Key('home-review')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Suggested: Not a transaction'), findsOneWidget);
    await tester.tap(find.textContaining('verification code'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Not a transaction');
    expect(find.byKey(const Key('home-review')), findsNothing);
    expect(
      await tester.runAsync(() => db.select(db.transactions).get()),
      isEmpty,
    );
  });
}
