import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/lifecycle/app_resumed.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/data/repositories/sms_scan_marks_repository.dart';
import 'package:pesaclarity/src/features/sms/application/read_again.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/sms/application/sms_scan_service.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:ujumbe/ujumbe.dart' show SmsMessage, engineVersion;

import '../../helpers/fake_sms_source.dart';
import '../../helpers/sms_samples.dart';
import '../../helpers/test_app.dart';

/// An inbox that can keep a read waiting, then hand it over or fail it.
class _Inbox extends FakeSmsSource {
  _Inbox({super.inbox});

  /// When set, the next read takes its messages, then waits for this
  /// before handing them over. Completing it with an error fails the read.
  Completer<void>? hold;

  @override
  Future<List<SmsMessage>> readInbox({
    required Set<String> senders,
    required DateTime since,
  }) async {
    final messages = await super.readInbox(senders: senders, since: since);
    final hold = this.hold;
    this.hold = null;
    if (hold != null) await hold.future;
    return messages;
  }
}

void main() {
  late AppDatabase db;

  /// The app coming back to the front, when a test says so.
  late StreamController<void> returns;

  /// When the app is opened, and so when its first scan starts.
  final opened = DateTime.utc(2026, 10, 27, 9);

  /// When a scan starts now: the next scan reads from then on.
  late DateTime now;

  setUp(() async {
    db = openTestDatabase();
    await DriftInstitutionsRepository(db).setSelected('mpesa', selected: true);
    returns = StreamController<void>.broadcast();
    addTearDown(returns.close);
    now = opened;
  });

  ProviderContainer container(FakeSmsSource source) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        smsSourceProvider.overrideWithValue(source),
        smsParseBatchProvider.overrideWithValue(
          (packs, messages) async => parseAll(packs, messages),
        ),
        appResumedProvider.overrideWithValue(returns.stream),
        smsScanServiceProvider.overrideWith(
          (ref) => SmsScanService(
            source: ref.watch(smsSourceProvider),
            ingestor: ref.watch(smsIngestorProvider),
            marks: ref.watch(smsScanMarksRepositoryProvider),
            clock: () => now,
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<List<String?>> receipts() async => [
    for (final t in await db.select(db.transactions).get()) t.receiptNo,
  ];

  /// Waits until [done], giving up after a few seconds.
  Future<void> until(FutureOr<bool> Function() done) async {
    for (var i = 0; i < 500 && !await done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
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

  test('reads every message again in the background when the readers are '
      'newer, and notes it for Home', () async {
    // Read up to November by readers older than these; the sent message
    // was missed.
    await DriftSmsScanMarksRepository(db)
        .markScanned('mpesa', DateTime.utc(2026, 11));
    await DriftAppSettingsRepository(db).writeJson(
      ReadAgainController.settingsKey,
      const LastRead(readers: ReaderVersions('0.0.1', {'mpesa': '0.0.1'}))
          .toJson(),
    );
    final source = FakeSmsSource(inbox: [mpesaSent()]);
    addTearDown(source.close);
    final c = container(source);

    await capture(c, 1);
    ReadAgainNotice? notice;
    for (var i = 0; i < 50 && notice == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      c.invalidate(readAgainNoticeProvider);
      notice = await c.read(readAgainNoticeProvider.future);
    }
    expect(notice!.added, 1);
    expect(notice.institutionIds, ['mpesa']);
    expect(await db.select(db.transactions).get(), hasLength(1));
    final last = await c.read(lastReadProvider.future);
    expect(last!.readers.engine, engineVersion);
  });

  test('adds a message that lands while the first scan is reading', () async {
    final source = _Inbox(inbox: [mpesaSent()]);
    addTearDown(source.close);
    final reading = source.hold = Completer<void>();
    final results = await capture(container(source), 0);
    await until(() => source.hold == null);

    // Too late for the scan, which already has its messages.
    source.receive(mpesaTill(receivedAt: opened));
    reading.complete();
    await until(() async => (await receipts()).length == 2);
    expect(await receipts(), ['TJA0000001', 'TJA0000004']);
    expect(results.first.added, 1);
  });

  group('back at the front', () {
    final later = opened.add(const Duration(minutes: 30));

    /// The app, opened on an inbox of one message that its first scan read.
    Future<(ProviderContainer, List<SmsIngestSummary>)> open(
      FakeSmsSource source,
    ) async {
      addTearDown(source.close);
      final c = container(source);
      final results = await capture(c, 1);
      await until(() => results.isNotEmpty);
      expect(await receipts(), ['TJA0000001']);
      return (c, results);
    }

    test('reads a message that came while the app was in the background, '
        'and goes on listening', () async {
      final source = FakeSmsSource(inbox: [mpesaSent()]);
      await open(source);

      // In the inbox, but the app, asleep, was never told.
      source.inbox.add(mpesaTill(receivedAt: later));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await receipts(), ['TJA0000001']);

      now = opened.add(const Duration(hours: 1));
      returns.add(null);
      await until(() async => (await receipts()).length == 2);
      expect(await receipts(), ['TJA0000001', 'TJA0000004']);
      // Only what arrived since the first scan.
      expect(source.reads.last.since, opened);
      // What it read is let go of, and only that: on iPhone, M-Pesa's
      // queued messages from the first scan's start up to this one's.
      final release = source.releases.last;
      expect(release.senders, {'MPESA'});
      expect(release.since, opened);
      expect(release.before, now);

      source.receive(mpesaSent(receipt: 'TJA0000012', receivedAt: now));
      await until(() async => (await receipts()).length == 3);
      expect(await receipts(), hasLength(3));
      expect(source.listenedSenders, hasLength(1), reason: 'never restarted');
    });

    test('does not add a message twice when it also arrived as it '
        'landed', () async {
      final source = FakeSmsSource(inbox: [mpesaSent()]);
      final (_, results) = await open(source);

      source.receive(mpesaTill(receivedAt: later));
      await until(() async => (await receipts()).length == 2);

      returns.add(null);
      const again = SmsIngestSummary(duplicates: 1);
      await until(() => results.last == again);
      expect(results.last, again);
      expect(await receipts(), ['TJA0000001', 'TJA0000004']);
    });

    test('adds nothing when nothing new arrived', () async {
      final source = FakeSmsSource(inbox: [mpesaSent()]);
      final (_, results) = await open(source);

      now = opened.add(const Duration(hours: 1));
      returns.add(null);
      await until(() => results.last == const SmsIngestSummary());
      expect(results.last, const SmsIngestSummary());
      expect(source.reads.last.since, opened);
      expect(await receipts(), ['TJA0000001']);
    });

    test('two quick returns add a new message once', () async {
      final source = FakeSmsSource(inbox: [mpesaSent()]);
      final (_, results) = await open(source);
      final reads = source.reads.length;

      // The clock stands still, so the second scan reads the message too.
      source.inbox.add(mpesaTill(receivedAt: later));
      returns
        ..add(null)
        ..add(null);
      const again = SmsIngestSummary(duplicates: 1);
      await until(() => results.last == again);
      expect(results.last, again);
      expect(source.reads, hasLength(reads + 2));
      expect(await receipts(), ['TJA0000001', 'TJA0000004']);
    });

    test('reads nothing once access is taken away, and carries on when it '
        'is given back', () async {
      final source = FakeSmsSource(inbox: [mpesaSent()]);
      final (c, _) = await open(source);
      final reads = source.reads.length;

      source
        ..current = SmsAccess.denied
        ..inbox.add(mpesaTill(receivedAt: later));
      returns.add(null);
      // Read after the return, so by then the return has been dealt with.
      source.receive(mpesaSent(receipt: 'TJA0000012', receivedAt: later));
      await until(() async => (await receipts()).length == 2);
      expect(await receipts(), ['TJA0000001', 'TJA0000012']);
      expect(source.reads, hasLength(reads));
      expect(c.read(liveSmsCaptureProvider).hasError, isFalse);

      source.current = SmsAccess.granted;
      returns.add(null);
      await until(() async => (await receipts()).length == 3);
      expect(await receipts(), contains('TJA0000004'));
    });

    test('starts once access is given in the phone\'s settings', () async {
      final source = FakeSmsSource(
        inbox: [mpesaSent()],
        dialogAnswer: SmsAccess.denied,
      );
      addTearDown(source.close);
      final results = await capture(container(source), 0);
      await until(() => source.accessChecks == 1);

      // Back, but still without access.
      returns.add(null);
      await until(() => source.accessChecks == 2);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(source.reads, isEmpty);
      expect(source.listenedSenders, isEmpty);

      source.current = SmsAccess.granted;
      returns.add(null);
      await until(() => results.isNotEmpty);
      expect(results.single.added, 1);
      expect(source.listenedSenders.single, {'MPESA'});

      source.receive(mpesaTill());
      await until(() async => (await receipts()).length == 2);
      expect(await receipts(), ['TJA0000001', 'TJA0000004']);
    });

    test('a scan that fails leaves messages coming in, and the next return '
        'reads what it missed', () async {
      final source = _Inbox(inbox: [mpesaSent()]);
      final (c, _) = await open(source);

      source.inbox.add(mpesaTill(receivedAt: later));
      final reading = source.hold = Completer<void>();
      returns.add(null);
      await until(() => source.hold == null);
      reading.completeError(PlatformException(code: 'read_failed'));

      source.receive(mpesaSent(receipt: 'TJA0000012', receivedAt: later));
      await until(() async => (await receipts()).length == 2);
      expect(await receipts(), ['TJA0000001', 'TJA0000012']);
      expect(c.read(liveSmsCaptureProvider).hasError, isFalse);

      returns.add(null);
      await until(() async => (await receipts()).length == 3);
      expect(await receipts(), contains('TJA0000004'));
    });

    group('once an account is switched off', () {
      late DriftInstitutionsRepository accounts;

      setUp(() async {
        accounts = DriftInstitutionsRepository(db);
        await accounts.setSelected('kcb', selected: true);
      });

      /// Switches KCB off and waits for capture to start afresh, for M-Pesa
      /// alone.
      Future<void> switchOffKcb(FakeSmsSource source) async {
        await accounts.setSelected('kcb', selected: false);
        await until(() => source.listenedSenders.length == 2);
        expect(source.listenedSenders.last, {'MPESA'});
      }

      test('its messages are no longer read, as they land or on a '
          'return', () async {
        final source = FakeSmsSource(inbox: [mpesaSent()]);
        final (_, results) = await open(source);

        await switchOffKcb(source);
        await until(() => results.length == 2);
        final reads = source.reads.length;

        source
          ..receive(kcbDebit(receivedAt: later))
          ..inbox.add(mpesaTill(receivedAt: later));
        now = opened.add(const Duration(hours: 1));
        returns.add(null);
        await until(() async => (await receipts()).contains('TJA0000004'));
        // A second return, read after anything the first one set going.
        returns.add(null);
        await until(() => source.reads.length >= reads + 2);

        expect(await receipts(), ['TJA0000001', 'TJA0000004']);
        expect(
          source.reads.skip(reads).map((r) => r.senders),
          everyElement({'MPESA'}),
        );
      });

      test('a message of its own still waiting to be read is left', () async {
        final source = _Inbox(inbox: [mpesaSent()]);
        final (_, results) = await open(source);

        // Lands while a scan is reading, so it waits its turn.
        final reading = source.hold = Completer<void>();
        returns.add(null);
        await until(() => source.hold == null);
        source.receive(kcbDebit(receivedAt: later));

        await switchOffKcb(source);
        reading.completeError(PlatformException(code: 'read_failed'));
        await until(() => results.length == 2);
        source.receive(mpesaTill(receivedAt: later));
        await until(() async => (await receipts()).length == 2);
        expect(await receipts(), ['TJA0000001', 'TJA0000004']);
      });

      test('a scan still reading ends without a fuss', () async {
        final source = _Inbox(inbox: [mpesaSent()]);
        final (c, results) = await open(source);

        source.inbox.add(mpesaTill(receivedAt: later));
        final reading = source.hold = Completer<void>();
        returns.add(null);
        await until(() => source.hold == null);

        await switchOffKcb(source);
        reading.complete();
        await until(() => results.length == 2);
        expect(await receipts(), ['TJA0000001', 'TJA0000004']);
        expect(c.read(liveSmsCaptureProvider).hasError, isFalse);
      });

      test('the first scan, still reading, ends without a fuss', () async {
        final source = _Inbox(inbox: [mpesaSent()]);
        addTearDown(source.close);
        final reading = source.hold = Completer<void>();
        final c = container(source);
        final results = await capture(c, 0);
        await until(() => source.hold == null);

        await switchOffKcb(source);
        reading.complete();
        await until(() => results.isNotEmpty);
        expect(await receipts(), ['TJA0000001']);
        expect(c.read(liveSmsCaptureProvider).hasError, isFalse);
      });
    });
  });
}
