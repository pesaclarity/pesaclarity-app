import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ujumbe/ujumbe.dart' show SmsMessage;

import '../../../core/lifecycle/app_resumed.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/institutions_repository.dart';
import '../../../data/repositories/message_reads_repository.dart';
import '../../../data/repositories/reader_templates_repository.dart';
import '../../../data/repositories/review_inbox_repository.dart';
import '../../../data/repositories/sms_scan_marks_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/calendar.dart';
import '../../accounts/application/my_accounts_providers.dart';
import '../../accounts/domain/institution.dart';
import '../../categoriser/application/auto_categoriser.dart';
import '../../categoriser/application/categoriser_providers.dart';
import '../../spaces/application/routing_providers.dart';
import '../../spaces/application/spaces_providers.dart';
import '../data/sms_source.dart';
import '../domain/scan_range.dart';
import 'message_recheck.dart';
import 'read_again.dart';
import 'scan_range_provider.dart';
import 'sms_ingestor.dart';
import 'sms_scan_service.dart';

/// How message batches are parsed. Tests swap in [parseAll], since a
/// background isolate cannot finish inside a widget test's fake clock.
final smsParseBatchProvider = Provider<SmsParseBatch>(
  (ref) => parseInBackground,
);

final smsIngestorProvider = Provider<SmsIngestor>(
  (ref) => SmsIngestor(
    accounts: ref.watch(accountsRepositoryProvider),
    transactions: ref.watch(transactionsRepositoryProvider),
    reviewInbox: ref.watch(reviewInboxRepositoryProvider),
    templates: ref.watch(readerTemplatesRepositoryProvider),
    reads: ref.watch(messageReadsRepositoryProvider),
    parse: ref.watch(smsParseBatchProvider),
  ),
);

final smsScanServiceProvider = Provider<SmsScanService>(
  (ref) => SmsScanService(
    source: ref.watch(smsSourceProvider),
    ingestor: ref.watch(smsIngestorProvider),
    marks: ref.watch(smsScanMarksRepositoryProvider),
  ),
);

/// The institutions switched on in My accounts, in catalogue order.
final selectedInstitutionsProvider = Provider<List<Institution>>((ref) {
  final ids = ref.watch(selectedInstitutionIdsProvider);
  // While another space's database opens, the ids still loading are the
  // last space's: reading them would read that space's accounts into this
  // one.
  if (ids.isLoading) return const [];
  final selected = ids.value ?? const {};
  return [
    for (final institution in ref.watch(institutionCatalogueProvider))
      if (selected.contains(institution.id)) institution,
  ];
});

/// Reads what arrived for [selected] since their last scan: the catch-up
/// that runs when the app opens and every time it returns to the front. An
/// institution not scanned before is read from the start of [range], as it
/// falls at [now].
///
/// [scan] reads into its own space's ledger and keeps that space's marks,
/// so another space is caught up by passing its scan service, institutions
/// and range. A source that keeps its own copy (the iPhone's Shortcuts
/// queue) lets go of only what this read: [selected]'s senders, over the
/// window read (see [SmsScanService.scan]).
Future<SmsIngestSummary> catchUpOnInbox(
  SmsScanService scan,
  List<Institution> selected, {
  required ScanRange range,
  required DateTime now,
}) => scan.scan(
  selected,
  from: range.firstDay(CalendarDate.local(now))?.startInstant,
);

/// Keeps the ledger current while the app runs. When the app opens, and
/// every time it returns to the front, a scan reads what arrived since the
/// last one (or, for a newly ticked institution, its messages from the
/// chosen [scanRangeProvider] start). In between, each watched message is
/// added as it lands.
///
/// The phone passes a message on only while the app is awake, and many
/// phones put apps in the background to sleep. Messages that arrive while
/// the app is closed or asleep stay in the inbox and are picked up by the
/// next scan, so no background service is needed.
///
/// Nothing is read without SMS access. It can be given in the phone's
/// settings while the app is away, so each return to the front checks
/// again, and reading starts on the first one that finds it given.
final liveSmsCaptureProvider = StreamProvider<SmsIngestSummary>((ref) async* {
  final selected = ref.watch(selectedInstitutionsProvider);
  final source = ref.watch(smsSourceProvider);
  final scan = ref.watch(smsScanServiceProvider);
  final ingestor = ref.watch(smsIngestorProvider);
  final resumed = ref.watch(appResumedProvider);
  if (selected.isEmpty) return;

  // What to deal with next, in the order it came: a message that just
  // landed, or null for the app coming back to the front. Taken one at a
  // time, so a scan and a message being added never run at once.
  final events = StreamController<SmsMessage?>();
  final next = StreamIterator(events.stream);
  final resumes = resumed.listen((_) => events.add(null));
  StreamSubscription<SmsMessage>? arrivals;
  void stop() {
    unawaited(next.cancel());
    unawaited(resumes.cancel());
    unawaited(arrivals?.cancel());
    unawaited(events.close());
  }

  // A change of accounts or space starts capture afresh. This run then
  // stops waiting at once, and leaves unread what still waited its turn.
  ref.onDispose(stop);
  try {
    // Access can be given in the phone's settings while the app is away, so
    // look again each time it comes back.
    while (await source.access() != SmsAccess.granted) {
      if (!await next.moveNext()) return;
    }
    // The space may have changed while access was asked: this capture is
    // then over.
    if (!ref.mounted) return;
    // Each account is read in one space: one this space has on while
    // Personal reads it too is left to Personal. The selection then changes
    // and the capture starts again with it.
    final spaceId = ref.read(activeSpaceIdProvider);
    if (spaceId != personalSpaceId) {
      final space = (await ref.read(spacesProvider.future))
          .where((s) => s.id == spaceId)
          .firstOrNull;
      if (!ref.mounted) return;
      if (space != null &&
          await ref
              .read(routingRulesProvider.notifier)
              .readOnce(
                space,
                here: ref.read(institutionsRepositoryProvider),
                personal: DriftInstitutionsRepository(
                  ref.read(personalDatabaseProvider),
                ),
              )) {
        return;
      }
      if (!ref.mounted) return;
    }
    // Listening starts before the first scan, so a message that lands
    // during it is not missed. One the scan also read is skipped as already
    // stored.
    arrivals = source
        .incoming({for (final i in selected) ...i.senderIds})
        .listen(events.add, onError: events.addError);

    void triggerAutoCategorise() {
      final suggester = ref.read(categorySuggesterProvider);
      if (suggester != null) {
        unawaited(ref.read(autoCategoriserProvider).autoCategorise(suggester));
      }
    }

    final range = await ref.watch(scanRangeProvider.future);
    if (!ref.mounted) return;
    // The same catch-up when the app opens and each time it comes back.
    Future<SmsIngestSummary> catchUp() => catchUpOnInbox(
      scan,
      selected,
      range: range,
      now: ref.read(clockProvider)(),
    );
    final initial = await catchUp();
    // Another space opened, or capture started afresh, meanwhile: the rest
    // is that run's to do.
    if (!ref.mounted) return;
    if (initial.added > 0) triggerAutoCategorise();
    // Amounts read before a pack knew an account's currency or number move
    // to the right ones, once per pack version.
    try {
      final notice = await ref
          .read(messageRecheckProvider)
          .runIfNeeded(selected);
      if (notice != null) ref.invalidate(recheckNoticeProvider);
    } on Object catch (error) {
      if (kDebugMode) debugPrint('Rechecking messages failed: $error');
    }
    if (!ref.mounted) return;
    // Every message again, in the background, once the readers are newer
    // than the ones that last read them all.
    unawaited(
      ref.read(readAgainControllerProvider.notifier).readIfNewer(selected),
    );
    yield initial;

    // Personal reads accounts shared with a business; sort what it already
    // knows (people the owner said are always business or personal).
    Future<void> sortShared() async {
      if (ref.read(activeSpaceIdProvider) != personalSpaceId) return;
      try {
        await ref.read(sharedLineRouterProvider).applyRules();
      } on Object catch (error) {
        if (kDebugMode) debugPrint('Sorting shared accounts failed: $error');
      }
    }

    if (initial.added > 0) await sortShared();
    while (await next.moveNext()) {
      final message = next.current;
      final SmsIngestSummary summary;
      if (message != null) {
        summary = await ingestor.ingest([message], selected);
      } else {
        // Back at the front. The phone passed nothing on while the app was
        // asleep, so read what arrived since the last scan. Access may have
        // been taken away meanwhile: then there is nothing to read.
        try {
          final access = await source.access();
          if (!ref.mounted) return;
          if (access != SmsAccess.granted) continue;
          summary = await catchUp();
        } on Object catch (error) {
          // Messages still come in as they land, and the next return reads
          // from the same mark again.
          if (kDebugMode) debugPrint('Reading missed messages failed: $error');
          continue;
        }
      }
      // Another space opened meanwhile: its own capture takes over.
      if (!ref.mounted) return;
      if (summary.added > 0) {
        triggerAutoCategorise();
        await sortShared();
      }
      yield summary;
    }
  } finally {
    // Also when an error ends capture, so nothing goes on listening.
    stop();
  }
});

/// Where the onboarding scan has got to.
enum SmsScanStage {
  explain,
  asking,
  denied,
  blocked,
  unavailable,
  scanning,
  finished,
  failed,
}

@immutable
class SmsScanState {
  const SmsScanState(
    this.stage, {
    this.done = 0,
    this.total = 0,
    this.summary = const SmsIngestSummary(),
  });

  final SmsScanStage stage;

  /// Messages read so far, of [total], while scanning.
  final int done;
  final int total;
  final SmsIngestSummary summary;
}

/// Onboarding: asks for SMS access, then runs the first scan, from the
/// chosen [scanRangeProvider] start.
class SmsScanController extends Notifier<SmsScanState> {
  @override
  SmsScanState build() => const SmsScanState(SmsScanStage.explain);

  SmsSource get _source => ref.read(smsSourceProvider);

  /// Asks for access and, once granted, scans.
  Future<void> allowAndScan() async {
    state = const SmsScanState(SmsScanStage.asking);
    await _afterAccess(_source.requestAccess);
  }

  /// Checks access again, after the person comes back from settings.
  Future<void> checkAgain() => _afterAccess(_source.access);

  Future<void> openSettings() => _source.openSettings();

  /// Acts on what [ask] says about access. When asking fails (the phone's
  /// side of it threw), the step offers Try again and Continue without
  /// messages rather than waiting on an answer that will not come.
  Future<void> _afterAccess(Future<SmsAccess> Function() ask) async {
    final SmsAccess access;
    try {
      access = await ask();
    } on Object catch (error) {
      if (kDebugMode) debugPrint('SMS access could not be checked: $error');
      state = const SmsScanState(SmsScanStage.failed);
      return;
    }
    switch (access) {
      case SmsAccess.granted:
        await _scan();
      case SmsAccess.denied:
        state = const SmsScanState(SmsScanStage.denied);
      case SmsAccess.blocked:
        state = const SmsScanState(SmsScanStage.blocked);
      case SmsAccess.unavailable:
        state = const SmsScanState(SmsScanStage.unavailable);
    }
  }

  Future<void> _scan() async {
    state = const SmsScanState(SmsScanStage.scanning);
    try {
      await ref.read(selectedInstitutionIdsProvider.future);
      final range = await ref.read(scanRangeProvider.future);
      final selected = ref.read(selectedInstitutionsProvider);
      final startedAt = ref.read(clockProvider)();
      var total = 0;
      final summary = await ref
          .read(smsScanServiceProvider)
          .scan(
            selected,
            from: range
                .firstDay(CalendarDate.local(ref.read(clockProvider)()))
                ?.startInstant,
            onProgress: (done, all) {
              total = all;
              state = SmsScanState(
                SmsScanStage.scanning,
                done: done,
                total: all,
              );
            },
          );
      // The first scan reads every message: no need to read them again
      // until the readers are newer.
      await ref
          .read(readAgainControllerProvider.notifier)
          .noteFullRead(selected, at: startedAt, messages: total);
      if (summary.added > 0) {
        final suggester = ref.read(categorySuggesterProvider);
        if (suggester != null) {
          unawaited(
            ref.read(autoCategoriserProvider).autoCategorise(suggester),
          );
        }
      }
      state = SmsScanState(SmsScanStage.finished, summary: summary);
    } on Object catch (error) {
      if (kDebugMode) debugPrint('SMS scan failed: $error');
      state = const SmsScanState(SmsScanStage.failed);
    }
  }
}

final smsScanControllerProvider =
    NotifierProvider<SmsScanController, SmsScanState>(SmsScanController.new);
