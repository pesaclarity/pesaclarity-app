import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/review_inbox_repository.dart';
import '../../../data/repositories/sms_scan_marks_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../accounts/application/my_accounts_providers.dart';
import '../../accounts/domain/institution.dart';
import '../../categoriser/application/auto_categoriser.dart';
import '../../categoriser/application/categoriser_providers.dart';
import '../data/sms_source.dart';
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
  final selected = ref.watch(selectedInstitutionIdsProvider).value ?? const {};
  return [
    for (final institution in ref.watch(institutionCatalogueProvider))
      if (selected.contains(institution.id)) institution,
  ];
});

/// Keeps the ledger current while the app runs: first a scan for messages
/// that arrived while it was closed (or, for a newly ticked institution, the
/// last 90 days), then each watched message as it lands.
///
/// Messages that arrive while the app is closed stay in the inbox and are
/// picked up by the next scan, so no background service is needed.
final liveSmsCaptureProvider = StreamProvider<SmsIngestSummary>((ref) async* {
  final selected = ref.watch(selectedInstitutionsProvider);
  final source = ref.watch(smsSourceProvider);
  final scan = ref.watch(smsScanServiceProvider);
  final ingestor = ref.watch(smsIngestorProvider);
  if (selected.isEmpty || await source.access() != SmsAccess.granted) return;

  void triggerAutoCategorise() {
    final suggester = ref.read(categorySuggesterProvider);
    if (suggester != null) {
      unawaited(ref.read(autoCategoriserProvider).autoCategorise(suggester));
    }
  }

  final initial = await scan.scan(selected);
  if (initial.added > 0) triggerAutoCategorise();
  yield initial;

  final senders = {for (final i in selected) ...i.senderIds};
  await for (final message in source.incoming(senders)) {
    final summary = await ingestor.ingest([message], selected);
    if (summary.added > 0) triggerAutoCategorise();
    yield summary;
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

/// Onboarding: asks for SMS access, then runs the first 90-day scan.
class SmsScanController extends Notifier<SmsScanState> {
  @override
  SmsScanState build() => const SmsScanState(SmsScanStage.explain);

  SmsSource get _source => ref.read(smsSourceProvider);

  /// Asks for access and, once granted, scans.
  Future<void> allowAndScan() async {
    state = const SmsScanState(SmsScanStage.asking);
    await _afterAccess(await _source.requestAccess());
  }

  /// Checks access again, after the person comes back from settings.
  Future<void> checkAgain() async => _afterAccess(await _source.access());

  Future<void> openSettings() => _source.openSettings();

  Future<void> _afterAccess(SmsAccess access) async {
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
      final summary = await ref
          .read(smsScanServiceProvider)
          .scan(
            ref.read(selectedInstitutionsProvider),
            onProgress: (done, total) => state = SmsScanState(
              SmsScanStage.scanning,
              done: done,
              total: total,
            ),
          );
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
