import 'dart:math';

import '../../../data/repositories/sms_scan_marks_repository.dart';
import '../../accounts/domain/institution.dart';
import '../data/sms_source.dart';
import 'sms_ingestor.dart';

/// Called as a scan works through the inbox: [done] of [total] messages.
typedef SmsScanProgress = void Function(int done, int total);

/// Reads the inbox of the selected institutions' senders into the ledger.
///
/// The first scan of an institution reads from the `from` given to [scan]
/// (every message when it is null); later scans read only what arrived
/// since the previous one started. Scans run one at a time.
class SmsScanService {
  SmsScanService({
    required this._source,
    required this._ingestor,
    required this._marks,
    DateTime Function()? clock,
    this.batchSize = 200,
  }) : _clock = clock ?? DateTime.now;

  final SmsSource _source;
  final SmsIngestor _ingestor;
  final SmsScanMarksRepository _marks;
  final DateTime Function() _clock;
  final int batchSize;

  Future<void> _previous = Future.value();

  /// Before any phone kept messages: "every message".
  static final _beginning = DateTime.utc(2000);

  /// Scans the inbox for each of the [selected] institutions.
  Future<SmsIngestSummary> scan(
    List<Institution> selected, {
    DateTime? from,
    SmsScanProgress? onProgress,
  }) {
    final run = _previous.then((_) => _scan(selected, from, onProgress));
    _previous = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<SmsIngestSummary> _scan(
    List<Institution> selected,
    DateTime? from,
    SmsScanProgress? onProgress,
  ) async {
    final startedAt = _clock().toUtc();
    final inboxes = [
      for (final institution in selected)
        (
          institution,
          await _source.readInbox(
            senders: institution.senderIds.toSet(),
            since:
                await _marks.scannedUntil(institution.id) ?? from ?? _beginning,
          ),
        ),
    ];

    final total = inboxes.fold(0, (sum, inbox) => sum + inbox.$2.length);
    var done = 0;
    onProgress?.call(done, total);
    var summary = const SmsIngestSummary();
    for (final (institution, messages) in inboxes) {
      for (var i = 0; i < messages.length; i += batchSize) {
        final batch = messages.sublist(i, min(i + batchSize, messages.length));
        summary += await _ingestor.ingest(batch, [institution]);
        done += batch.length;
        onProgress?.call(done, total);
      }
      await _marks.markScanned(institution.id, startedAt);
    }
    // Everything before the start has now been read for every institution.
    if (selected.isNotEmpty) await _source.release(startedAt);
    return summary;
  }
}
