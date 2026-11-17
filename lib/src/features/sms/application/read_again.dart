import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/institutions_repository.dart';
import '../../../data/repositories/message_reads_repository.dart';
import '../../../domain/time/calendar.dart';
import '../../accounts/domain/institution.dart';
import '../../categoriser/application/auto_categoriser.dart';
import '../../categoriser/application/categoriser_providers.dart';
import '../data/sms_source.dart';
import 'scan_range_provider.dart';
import 'sms_capture_providers.dart';
import 'sms_ingestor.dart';

/// The readers' versions: the engine's and each pack's, by pack id.
@immutable
class ReaderVersions {
  const ReaderVersions(this.engine, this.packs);

  /// The readers this app has for [selected].
  factory ReaderVersions.of(List<Institution> selected) => ReaderVersions(
    engineVersion,
    {for (final i in selected) i.id: i.pack.version},
  );

  static ReaderVersions? fromJson(Object? json) {
    if (json is! Map) return null;
    final engine = json['engine'];
    final packs = json['packs'];
    if (engine is! String || packs is! Map) return null;
    return ReaderVersions(engine, {
      for (final MapEntry(:key, :value) in packs.entries)
        if (key is String && value is String) key: value,
    });
  }

  final String engine;
  final Map<String, String> packs;

  /// Whether these readers are newer than [last]: a newer engine, or a
  /// newer pack for an account [last] read. A pack [last] never read is not
  /// newer: a newly ticked account is read in full by the next scan anyway.
  bool newerThan(ReaderVersions last) {
    if (_compare(engine, last.engine) > 0) return true;
    for (final MapEntry(key: id, value: version) in packs.entries) {
      final before = last.packs[id];
      if (before != null && _compare(version, before) > 0) return true;
    }
    return false;
  }

  /// [last]'s packs with these on top, for accounts read now and before.
  ReaderVersions over(ReaderVersions? last) =>
      ReaderVersions(engine, {...?last?.packs, ...packs});

  Map<String, Object?> toJson() => {'engine': engine, 'packs': packs};

  static int _compare(String a, String b) {
    try {
      return compareVersions(a, b);
    } on FormatException {
      return a.compareTo(b);
    }
  }
}

/// The last time every message was read: by which readers, and, after a
/// read in full, when, how many messages, and what changed.
@immutable
class LastRead {
  const LastRead({
    required this.readers,
    this.at,
    this.messages = 0,
    this.added = 0,
    this.updated = 0,
    this.firstChange,
    this.lastChange,
    this.changedAccounts = const {},
  });

  static LastRead? fromJson(Map<String, Object?>? json) {
    final readers = ReaderVersions.fromJson(json?['readers']);
    if (json == null || readers == null) return null;
    int count(String key) => switch (json[key]) {
      final int n => n,
      _ => 0,
    };
    DateTime? when(String key) => switch (json[key]) {
      final String s => DateTime.tryParse(s),
      _ => null,
    };
    return LastRead(
      readers: readers,
      at: when('at'),
      messages: count('messages'),
      added: count('added'),
      updated: count('updated'),
      firstChange: when('firstChange'),
      lastChange: when('lastChange'),
      changedAccounts: {
        for (final id in json['changedAccounts'] as List? ?? const [])
          if (id is int) id,
      },
    );
  }

  final ReaderVersions readers;

  /// When it started; null when only the readers were noted.
  final DateTime? at;
  final int messages;
  final int added;
  final int updated;

  /// The earliest and latest of the transactions added or updated.
  final DateTime? firstChange;
  final DateTime? lastChange;
  final Set<int> changedAccounts;

  bool get changedAny => added + updated > 0;

  Map<String, Object?> toJson() => {
    'readers': readers.toJson(),
    if (at != null) 'at': at!.toUtc().toIso8601String(),
    'messages': messages,
    'added': added,
    'updated': updated,
    if (firstChange != null)
      'firstChange': firstChange!.toUtc().toIso8601String(),
    if (lastChange != null) 'lastChange': lastChange!.toUtc().toIso8601String(),
    'changedAccounts': changedAccounts.toList(),
  };
}

/// What reading again found on its own, for the card on Home, until it is
/// closed.
@immutable
class ReadAgainNotice {
  const ReadAgainNotice({
    required this.added,
    required this.updated,
    required this.institutionIds,
  });

  static ReadAgainNotice? fromJson(Map<String, Object?>? json) {
    final added = json?['added'];
    final updated = json?['updated'];
    final ids = json?['institutions'];
    if (added is! int || updated is! int || ids is! List) return null;
    if (added + updated == 0) return null;
    return ReadAgainNotice(
      added: added,
      updated: updated,
      institutionIds: [
        for (final id in ids)
          if (id is String) id,
      ],
    );
  }

  final int added;
  final int updated;

  /// The accounts whose messages gave something new or changed.
  final List<String> institutionIds;

  Map<String, Object?> toJson() => {
    'added': added,
    'updated': updated,
    'institutions': institutionIds,
  };
}

enum ReadAgainStage { idle, reading, finished, failed }

/// Where reading messages again has got to.
@immutable
class ReadAgainState {
  const ReadAgainState(
    this.stage, {
    this.done = 0,
    this.total = 0,
    this.summary = const SmsIngestSummary(),
    this.at,
  });

  static const idle = ReadAgainState(ReadAgainStage.idle);

  final ReadAgainStage stage;

  /// Messages read so far, of [total], while reading.
  final int done;
  final int total;

  /// What the read that finished found, and when it started.
  final SmsIngestSummary summary;
  final DateTime? at;

  bool get reading => stage == ReadAgainStage.reading;
}

/// Reads every message of the ticked accounts again, from the start of the
/// chosen range, with the readers this app has: through the same scan as
/// every other read, so nothing is stored twice and what the person set
/// stays (see [SmsIngestor.ingest]).
///
/// Lives as long as the app, so a read keeps going when the person leaves
/// the screen that started it.
class ReadAgainController extends Notifier<ReadAgainState> {
  static const settingsKey = 'sms.lastRead';
  static const noticeKey = 'sms.readAgainNotice';

  @override
  ReadAgainState build() => ReadAgainState.idle;

  /// Reads every message again, as the person asked. Does nothing while a
  /// read is going.
  Future<void> readAgain() => _run(automatic: false);

  /// Reads every message again on its own when the readers are newer than
  /// the ones that last read them all. A note on Home says what changed,
  /// if anything did.
  Future<void> readIfNewer(List<Institution> selected) async {
    if (selected.isEmpty || state.reading) return;
    final last = await _last();
    final current = ReaderVersions.of(selected);
    if (last == null) {
      // Messages read before the readers were noted: read them again once.
      if (!await ref.read(messageReadsRepositoryProvider).hasUnnotedReads()) {
        await _save(LastRead(readers: current));
        return;
      }
    } else if (!current.newerThan(last.readers)) {
      return;
    }
    await _run(automatic: true);
  }

  /// Notes a read of every message by [selected]'s readers, as the first
  /// scan is, so they are not read again until the readers are newer.
  Future<void> noteFullRead(
    List<Institution> selected, {
    required DateTime at,
    required int messages,
  }) async {
    if (selected.isEmpty) return;
    final last = await _last();
    await _save(
      LastRead(
        readers: ReaderVersions.of(selected).over(last?.readers),
        at: at,
        messages: messages,
      ),
    );
  }

  Future<void> _run({required bool automatic}) async {
    if (state.reading) return;
    state = const ReadAgainState(ReadAgainStage.reading);
    try {
      final ids = await ref.read(institutionsRepositoryProvider).selectedIds();
      final selected = [
        for (final i in ref.read(institutionCatalogueProvider))
          if (ids.contains(i.id)) i,
      ];
      final source = ref.read(smsSourceProvider);
      if (selected.isEmpty || await source.access() != SmsAccess.granted) {
        state = ReadAgainState.idle;
        return;
      }
      final at = ref.read(clockProvider)();
      final range = await ref.read(scanRangeProvider.future);
      var total = 0;
      final summary = await ref
          .read(smsScanServiceProvider)
          .scan(
            selected,
            from: range.firstDay(CalendarDate.local(at))?.startInstant,
            again: true,
            onProgress: (done, all) {
              total = all;
              if (ref.mounted) {
                state = ReadAgainState(
                  ReadAgainStage.reading,
                  done: done,
                  total: all,
                );
              }
            },
          );
      if (summary.added > 0) _categorise();
      final changes = summary.changes;
      final last = await _last();
      final times = [for (final c in changes) c.at]..sort();
      await _save(
        LastRead(
          readers: ReaderVersions.of(selected).over(last?.readers),
          at: at,
          messages: total,
          added: summary.added,
          updated: summary.updated,
          firstChange: times.firstOrNull,
          lastChange: times.lastOrNull,
          changedAccounts: {for (final c in changes) c.accountId},
        ),
      );
      if (automatic && changes.isNotEmpty) {
        final ids = {for (final c in changes) c.institutionId};
        await ref
            .read(appSettingsRepositoryProvider)
            .writeJson(
              noticeKey,
              ReadAgainNotice(
                added: summary.added,
                updated: summary.updated,
                institutionIds: [
                  for (final i in ref.read(institutionCatalogueProvider))
                    if (ids.contains(i.id)) i.id,
                ],
              ).toJson(),
            );
        ref.invalidate(readAgainNoticeProvider);
      }
      if (!ref.mounted) return;
      state = automatic
          ? ReadAgainState.idle
          : ReadAgainState(
              ReadAgainStage.finished,
              summary: summary,
              total: total,
              at: at,
            );
    } on Object catch (error) {
      if (kDebugMode) debugPrint('Reading messages again failed: $error');
      if (ref.mounted) {
        state = automatic
            ? ReadAgainState.idle
            : const ReadAgainState(ReadAgainStage.failed);
      }
    }
  }

  void _categorise() {
    final suggester = ref.read(categorySuggesterProvider);
    if (suggester != null) {
      unawaited(ref.read(autoCategoriserProvider).autoCategorise(suggester));
    }
  }

  Future<LastRead?> _last() async => LastRead.fromJson(
    await ref.read(appSettingsRepositoryProvider).readJson(settingsKey),
  );

  Future<void> _save(LastRead last) async {
    await ref
        .read(appSettingsRepositoryProvider)
        .writeJson(settingsKey, last.toJson());
    ref.invalidate(lastReadProvider);
  }
}

final readAgainControllerProvider =
    NotifierProvider<ReadAgainController, ReadAgainState>(
      ReadAgainController.new,
    );

/// The last time every message was read, if ever.
final lastReadProvider = FutureProvider<LastRead?>(
  (ref) async => LastRead.fromJson(
    await ref
        .watch(appSettingsRepositoryProvider)
        .readJson(ReadAgainController.settingsKey),
  ),
);

/// The card on Home after messages were read again on their own and
/// something changed, until it is closed.
final readAgainNoticeProvider = FutureProvider<ReadAgainNotice?>(
  (ref) async => ReadAgainNotice.fromJson(
    await ref
        .watch(appSettingsRepositoryProvider)
        .readJson(ReadAgainController.noticeKey),
  ),
);

/// Closes the card on Home.
Future<void> closeReadAgainNotice(WidgetRef ref) async {
  await ref
      .read(appSettingsRepositoryProvider)
      .writeJson(ReadAgainController.noticeKey, const {});
  ref.invalidate(readAgainNoticeProvider);
}
