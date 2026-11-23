import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/database/space_databases.dart';
import '../../../data/repositories/account_edits.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/balances_repository.dart';
import '../../../data/repositories/institutions_repository.dart';
import '../../../data/repositories/message_reads_repository.dart';
import '../../../data/repositories/review_inbox_repository.dart';
import '../../../data/repositories/space_move_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/accounts/mpesa_family.dart';
import '../../../domain/accounts/mpesa_lines.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/calendar.dart';
import '../../activity/application/activity_providers.dart';
import '../../sms/application/scan_range_provider.dart';
import '../../sms/application/sms_capture_providers.dart';
import '../../sms/application/sms_ingestor.dart';
import '../../sms/data/sms_source.dart';
import '../../spaces/application/routing_providers.dart';
import '../../spaces/application/spaces_providers.dart';
import '../domain/institution.dart';

/// Where Personal's settings keep the M-Pesa lines.
const mpesaLinesKey = 'mpesa.lines';

/// The M-Pesa lines on this phone, in Personal's settings so every space
/// places a message the same way. Changes run one at a time.
class MpesaLinesController extends AsyncNotifier<MpesaLines> {
  AppSettingsRepository get _settings =>
      ref.read(mainSettingsRepositoryProvider);

  Future<void> _last = Future.value();

  @override
  Future<MpesaLines> build() async => MpesaLines.fromJson(
    await ref.watch(mainSettingsRepositoryProvider).readJson(mpesaLinesKey),
  );

  /// Applies [change] to the lines as saved, saves what it gives and
  /// returns its answer.
  Future<T> change<T>((MpesaLines, T) Function(MpesaLines) change) {
    final run = _last.then((_) async {
      final current = MpesaLines.fromJson(
        await _settings.readJson(mpesaLinesKey),
      );
      final (next, answer) = change(current);
      await _settings.writeJson(mpesaLinesKey, next.toJson());
      if (ref.mounted) state = AsyncData(next);
      return (next, answer);
    });
    _last = run.then((_) {}, onError: (_) {});
    return run.then((r) => r.$2);
  }

  /// Saves the lines [update] makes of them.
  Future<MpesaLines> apply(MpesaLines Function(MpesaLines) update) =>
      change((lines) {
        final next = update(lines);
        return (next, next);
      });

  /// The lines as saved, once changes under way are done.
  Future<MpesaLines> saved() => _last.then(
    (_) async => MpesaLines.fromJson(await _settings.readJson(mpesaLinesKey)),
  );

  /// Places [facts] in order: see [MpesaLines.place].
  Future<(MpesaLines, List<LinePlace>)> placeAll(List<LineFacts> facts) =>
      change((lines) {
        final (next, places) = lines.placeAll(facts);
        return (next, (next, places));
      });

  /// "Not now" on the offer to split.
  Future<void> hideOffer() => apply((l) => l.copyWith(offerHidden: true));

  /// The quiet note on the first skipped message was seen.
  Future<void> skipNoteSeen() => apply((l) => l.skipNoteSeen());
}

/// Where the open space's settings keep whether to ask "Which line was
/// this?". It is asked in the space that reads M-Pesa itself.
const askWhichLineKey = 'mpesa.askWhichLine';

/// Whether the open space asks "Which line was this?"; off ("Don't ask me
/// again"), such messages wait in Not yet sorted.
class AskWhichLineSetting extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async =>
      (await ref
          .watch(appSettingsRepositoryProvider)
          .readJson(askWhichLineKey))?['ask'] !=
      false;

  Future<void> set(bool ask) async {
    await ref.read(appSettingsRepositoryProvider).writeJson(askWhichLineKey, {
      'ask': ask,
    });
    state = AsyncData(ask);
  }
}

final askWhichLineProvider = AsyncNotifierProvider<AskWhichLineSetting, bool>(
  AskWhichLineSetting.new,
);

final mpesaLinesProvider =
    AsyncNotifierProvider<MpesaLinesController, MpesaLines>(
      MpesaLinesController.new,
    );

/// The ids of the spaces on this phone.
Future<Set<String>> _listed(Ref ref) async => {
  for (final space in await ref.read(spacesProvider.future)) space.id,
};

/// Which M-Pesa line each message is on, for the ingestor of [spaceId]:
/// before the split, every line is read into one account; after it, each
/// line is read in its own space, on its own account. Only the space that
/// reads M-Pesa itself ([asks]) keeps a message whose line it cannot tell,
/// so it is asked about once.
class SpaceMessageLines implements MessageLines {
  SpaceMessageLines({
    required this.spaceId,
    required this.controller,
    required this.listed,
    required this.asks,
  });

  final String spaceId;
  final MpesaLinesController Function() controller;
  final Future<Set<String>> Function() listed;
  final Future<bool> Function() asks;

  @override
  Future<List<LineRead>> place(List<LineFacts> facts) async {
    final (lines, places) = await controller().placeAll(facts);
    final spaces = await listed();
    final asking = places.any((p) => p is AskWhichLine) && await asks();
    return [
      for (final place in places)
        switch (place) {
          // A line the person stopped tracking is read nowhere.
          NotTracked() => const ReadElsewhere(),
          OnLine() when !lines.split => const ReadOnAccount(null),
          OnLine(:final lineId) =>
            lines.readerOf(lines.line(lineId)!, spaces) == spaceId
                ? ReadOnAccount(lineReference(lineId))
                : const ReadElsewhere(),
          WaitForSim() => const ReadElsewhere(),
          AskWhichLine() => asking ? const AskLine() : const ReadElsewhere(),
        },
    ];
  }
}

/// [db]'s space reads M-Pesa itself, not only a line of it.
Future<bool> readsMpesa(AppDatabase db) async =>
    (await DriftInstitutionsRepository(
      db,
    ).selectedIds()).contains(mpesaInstitutionId);

/// The lines for the ingestor of the open space.
final spaceMessageLinesProvider = Provider<MessageLines>((ref) {
  final spaceId = ref.watch(activeSpaceIdProvider);
  final db = ref.watch(appDatabaseProvider);
  return SpaceMessageLines(
    spaceId: spaceId,
    controller: () => ref.read(mpesaLinesProvider.notifier),
    listed: () => _listed(ref),
    asks: () => readsMpesa(db),
  );
});

/// An ingestor for [spaceId]'s database [db], which need not be open, for
/// a message the person placed on a line another space reads.
SmsIngestor ingestorFor(Ref ref, AppDatabase db, String spaceId) => SmsIngestor(
  accounts: DriftAccountsRepository(db),
  transactions: DriftTransactionsRepository(db),
  reviewInbox: DriftReviewInboxRepository(db),
  reads: MessageReadsRepository(db),
  parse: (packs, messages) async => parseAll(packs, messages),
  lines: SpaceMessageLines(
    spaceId: spaceId,
    controller: () => ref.read(mpesaLinesProvider.notifier),
    listed: () => _listed(ref),
    asks: () => readsMpesa(db),
  ),
  moveToAccount: DriftBalancesRepository(db).moveToAccount,
);

/// Counts the M-Pesa lines from every message in the inbox from [from],
/// once, so a phone that read two lines as one before lines were told apart
/// is offered the split at once. A phone that keeps no copy of past
/// messages (iPhone) counts them as they arrive.
Future<void> countLines(Ref ref, {DateTime? from}) async {
  final notifier = ref.read(mpesaLinesProvider.notifier);
  if ((await notifier.saved()).surveyed) return;
  final source = ref.read(smsSourceProvider);
  if (source is ShortcutConnection) {
    await notifier.apply((l) => l.copyWith(surveyed: true));
    return;
  }
  final mpesa = mpesaInstitution(ref);
  final messages = await source.readInbox(
    senders: mpesa.senderIds.toSet(),
    since: from ?? DateTime.utc(2000),
  );
  final results = await ref.read(smsParseBatchProvider)([mpesa.pack], messages);
  await notifier.apply(
    (l) => l.counted([
      for (final (i, result) in results.indexed)
        if (result is ParsedTransaction &&
            result.accountInstitution == mpesaInstitutionId &&
            !isPochiOwnAccount(result.ownAccount))
          lineFactsOf(result, messages[i]),
    ]),
  );
}

/// Reads again the M-Pesa messages an answer about a SIM sent to the open
/// space, if any.
Future<void> readWhatLinesSent(Ref ref) async {
  final notifier = ref.read(mpesaLinesProvider.notifier);
  final here = ref.read(activeSpaceIdProvider);
  final from = (await notifier.saved()).readFrom[here];
  if (from == null) return;
  await ref
      .read(smsScanServiceProvider)
      .scan([mpesaInstitution(ref)], from: from, again: true);
  await notifier.apply((l) => l.readDone(here));
}

/// The institution M-Pesa, as the catalogue has it.
Institution mpesaInstitution(Ref ref) => ref
    .read(institutionCatalogueProvider)
    .singleWhere((i) => i.id == mpesaInstitutionId);

/// What the person chose for one line.
@immutable
class LineSetting {
  const LineSetting({required this.spaceId, this.name, this.sharedWith});

  final String? name;

  /// The space that reads it.
  final String spaceId;

  /// The business that asks about it, for a line used for both.
  final String? sharedWith;
}

/// Gives lines to spaces, names them, and settles the questions about
/// them.
class MpesaLineRouting {
  MpesaLineRouting(this._ref);

  final Ref _ref;

  MpesaLinesController get _lines => _ref.read(mpesaLinesProvider.notifier);

  /// Names line [lineId] and gives it to [choice]'s space. A line that
  /// moves takes its payments and the balance its messages printed with it
  /// (see [DriftSpaceMoveRepository.move]); the account left behind is
  /// empty and not shown.
  Future<void> choose(String lineId, LineSetting choice) async {
    final listed = await _listed(_ref);
    final before = (await _lines.saved()).line(lineId);
    if (before == null) return;
    final from = (await _lines.saved()).readerOf(before, listed);
    final lines = await _lines.apply(
      (l) => l.withChoice(
        lineId,
        name: choice.name,
        spaceId: choice.spaceId,
        sharedWith: () => choice.sharedWith,
      ),
    );
    final to = lines.readerOf(lines.line(lineId)!, listed);
    await _ref
        .read(routingRulesProvider.notifier)
        .shareLine(lineSelectionId(lineId), choice.sharedWith);
    final spaces = _ref.read(spaceDatabasesProvider);
    final (target, closeTarget) = await spaces.open(to);
    try {
      // Read where it goes before it leaves, so its balance goes too.
      await DriftInstitutionsRepository(target)
          .setSelected(lineSelectionId(lineId), selected: true);
      if (from == to) return;
      final (source, closeSource) = await spaces.open(from);
      try {
        await DriftInstitutionsRepository(source)
            .setSelected(lineSelectionId(lineId), selected: false);
        final account =
            await (source.select(source.accounts)..where(
                  (a) =>
                      a.institutionId.equals(mpesaInstitutionId) &
                      a.reference.equals(lineReference(lineId)),
                ))
                .get();
        if (account.isEmpty) return;
        final ids = [
          for (final t
              in await (source.select(source.transactions)
                    ..where(
                      (t) => t.accountId.isIn([for (final a in account) a.id]),
                    )
                    ..orderBy([(t) => OrderingTerm.asc(t.occurredAt)]))
                  .get())
            t.id,
        ];
        await DriftSpaceMoveRepository(
          source,
          spaces.open,
          sourceSpaceId: from,
          nameOf: spaces.nameOf,
        ).moveMany(ids, to);
      } finally {
        if (closeSource) await source.close();
      }
    } finally {
      if (closeTarget) await target.close();
    }
  }

  /// Each line its own account, as the split makes them, before a choice
  /// that needs it: a role, a merge or not tracking a line. Names and
  /// spaces stay as they are.
  Future<void> _ensureSplit() async {
    final lines = await _lines.saved();
    if (lines.split || lines.lines.isEmpty) return;
    await _ref.read(lineSplitControllerProvider.notifier).split({
      for (final line in lines.lines)
        line.id: LineSetting(
          spaceId: line.spaceId,
          name: line.name,
          sharedWith: line.sharedWith,
        ),
    });
  }

  /// Runs [work] on the database of the space that reads [lineId], with
  /// the id of the line's account there, if it has one.
  Future<T?> _onLineAccount<T>(
    String lineId,
    Future<T> Function(AppDatabase db, int accountId) work,
  ) async {
    final lines = await _lines.saved();
    final line = lines.line(lineId);
    if (line == null) return null;
    final reader = lines.readerOf(line, await _listed(_ref));
    final (db, close) = await _ref.read(spaceDatabasesProvider).open(reader);
    try {
      final account =
          await (db.select(db.accounts)..where(
                (a) =>
                    a.institutionId.equals(mpesaInstitutionId) &
                    a.reference.equals(lineReference(lineId)),
              ))
              .getSingleOrNull();
      if (account == null) return null;
      return await work(db, account.id);
    } finally {
      if (close) await db.close();
    }
  }

  /// Whether [lineId]'s balance counts in On hand and the M-Pesa total.
  Future<void> _counts(String lineId, {required bool counts}) => _onLineAccount(
    lineId,
    (db, id) => AccountEdits(db).save(
      id,
      // Null follows the type, which counts.
      countsOnHand: counts ? null : false,
      setCountsOnHand: true,
    ),
  );

  /// How many records line [lineId] has in the space that reads it.
  Future<int> recordCount(String lineId) async =>
      await _onLineAccount(
        lineId,
        (db, id) => AccountEdits(db).transactionCount(id),
      ) ??
      0;

  /// "Keep my 2 most recent lines, set the rest aside".
  Future<void> keepTwoMostRecent() async {
    await _ensureSplit();
    final lines = await _lines.apply((l) => l.keepTwoMostRecent());
    for (final line in lines.lines) {
      await _counts(line.id, counts: line.tracked);
    }
  }

  /// [lineId] is the main or second line, and tracked again.
  Future<void> setRole(String lineId, LineRole role) async {
    await _ensureSplit();
    await _lines.apply((l) => l.withRole(lineId, role));
    await _counts(lineId, counts: true);
  }

  /// "Don't track this line": its new messages are skipped and its balance
  /// leaves every total. With [deleteRecords] its records go too, as
  /// removing an account's transactions does: their messages set aside so
  /// reading again never brings them back, the journal and the Firefly III
  /// outbox following through their triggers.
  Future<void> untrack(String lineId, {required bool deleteRecords}) async {
    await _ensureSplit();
    await _lines.apply((l) => l.untracked(lineId));
    await _onLineAccount(lineId, (db, id) async {
      final edits = AccountEdits(db);
      if (deleteRecords) await edits.deleteRecords(id);
      await edits.save(id, countsOnHand: false, setCountsOnHand: true);
    });
  }

  /// "Same line as…": line [fromId] joins [intoId]. Its records move to
  /// the space that reads [intoId] when that is another, then onto
  /// [intoId]'s account there, keeping their dates; the balance continues
  /// from the line with the later message.
  Future<void> merge(String fromId, String intoId) async {
    if (fromId == intoId) return;
    await _ensureSplit();
    final before = await _lines.saved();
    final from = before.line(fromId);
    final into = before.line(intoId);
    if (from == null || into == null) return;
    final listed = await _listed(_ref);
    if (before.readerOf(from, listed) != before.readerOf(into, listed)) {
      await choose(
        fromId,
        LineSetting(
          spaceId: into.spaceId,
          name: from.name,
          sharedWith: into.sharedWith,
        ),
      );
    }
    await _onLineAccount(fromId, (db, fromAccount) async {
      final target =
          await (db.select(db.accounts)..where(
                (a) =>
                    a.institutionId.equals(mpesaInstitutionId) &
                    a.reference.equals(lineReference(intoId)),
              ))
              .getSingleOrNull();
      if (target == null) {
        // The kept line has no account here yet: this one becomes it.
        await (db.update(db.accounts)..where((a) => a.id.equals(fromAccount)))
            .write(AccountsCompanion(reference: Value(lineReference(intoId))));
      } else {
        await AccountEdits(db).mergeLine(fromAccount, target.id);
      }
      await DriftInstitutionsRepository(db)
          .setSelected(lineSelectionId(fromId), selected: false);
    });
    final lines = await _lines.apply((l) => l.merged(fromId, intoId));
    final kept = lines.line(intoId);
    if (kept != null) await _counts(intoId, counts: kept.tracked);
  }

  /// "Same line" or "A new line" for [sim], asked about [lineId].
  Future<void> answerSim(
    String sim,
    String lineId, {
    required bool same,
  }) async {
    final listed = await _listed(_ref);
    final lines = await _lines.apply(
      (l) => l.answerSim(sim, lineId, same: same, listed: listed),
    );
    // A line that came of it is read where its SIM's messages go.
    for (final line in lines.lines) {
      if (!line.sims.contains(sim)) continue;
      final (db, close) = await _ref
          .read(spaceDatabasesProvider)
          .open(lines.readerOf(line, listed));
      try {
        await DriftInstitutionsRepository(db)
            .setSelected(lineSelectionId(line.id), selected: true);
      } finally {
        if (close) await db.close();
      }
    }
    // Its messages skipped while it waited, read now where the open space
    // reads them; another space reads its own when it next opens.
    await readWhatLinesSent(_ref);
  }

  /// "Which line was this?": the message waiting in [item] was on line
  /// [lineId]. It is read there, in the space that reads that line, and
  /// leaves the open space's review.
  Future<void> answerWhichLine(ReviewItem item, String lineId) async {
    final body = item.body;
    if (body == null) return;
    final message = SmsMessage(
      sender: item.sender,
      body: body,
      receivedAt: item.receivedAt,
    );
    final mpesa = mpesaInstitution(_ref);
    final parsed = SmsParser([mpesa.pack]).parse(message);
    if (parsed is ParsedTransaction) {
      final facts = lineFactsOf(parsed, message);
      await _lines.apply((l) => l.placedOn(facts, lineId));
    }
    final lines = await _lines.saved();
    final line = lines.line(lineId);
    if (line == null) return;
    final reader = lines.readerOf(line, await _listed(_ref));
    final (db, close) = await _ref.read(spaceDatabasesProvider).open(reader);
    try {
      await ingestorFor(_ref, db, reader).ingest([message], [mpesa]);
    } finally {
      if (close) await db.close();
    }
    await _ref.read(reviewInboxRepositoryProvider).resolve(item.id);
  }
}

final mpesaLineRoutingProvider = Provider<MpesaLineRouting>(
  MpesaLineRouting.new,
);

enum LineSplitStage { idle, splitting, finished, failed }

/// Where splitting the lines has got to.
@immutable
class LineSplitState {
  const LineSplitState(this.stage, {this.done = 0, this.total = 0});

  static const idle = LineSplitState(LineSplitStage.idle);

  final LineSplitStage stage;

  /// Messages sorted so far, of [total].
  final int done;
  final int total;
}

/// Splits the lines read into one M-Pesa account: each becomes its own
/// account, the messages are read again into the line each was on, then
/// each line goes to the space chosen for it. Lives as long as the app, so
/// it carries on when the person leaves the screen.
class LineSplitController extends Notifier<LineSplitState> {
  @override
  LineSplitState build() => LineSplitState.idle;

  /// Splits the lines with [choices] by line id. Nothing is split when it
  /// is already, or while a split runs.
  Future<void> split(Map<String, LineSetting> choices) async {
    if (state.stage == LineSplitStage.splitting) return;
    state = const LineSplitState(LineSplitStage.splitting);
    try {
      final here = _ref.read(activeSpaceIdProvider);
      final notifier = ref.read(mpesaLinesProvider.notifier);
      final before = await notifier.saved();
      if (before.split || before.lines.isEmpty) {
        state = LineSplitState.idle;
        return;
      }
      // Every line here first, with its name; then each moves where chosen.
      final lines = await notifier.apply((l) {
        var next = l.copyWith(split: true, offerHidden: true);
        for (final line in l.lines) {
          next = next.withChoice(
            line.id,
            name: choices[line.id]?.name,
            spaceId: here,
            sharedWith: () => null,
          );
        }
        return next;
      });
      final db = ref.read(appDatabaseProvider);
      final keeper =
          ([...lines.shown.isEmpty ? lines.lines : lines.shown]..sort((a, b) {
                final stay =
                    ((choices[b.id]?.spaceId ?? here) == here ? 1 : 0) -
                    ((choices[a.id]?.spaceId ?? here) == here ? 1 : 0);
                return stay != 0 ? stay : b.messages - a.messages;
              }))
              .first;
      // The one account every line was read into is now the keeper's, so
      // its names, categories and balance checks stay.
      await (db.update(db.accounts)..where(
            (a) =>
                a.institutionId.equals(mpesaInstitutionId) &
                a.reference.isNull(),
          ))
          .write(AccountsCompanion(reference: Value(lineReference(keeper.id))));
      final selected = DriftInstitutionsRepository(db);
      for (final line in lines.lines) {
        await selected.setSelected(lineSelectionId(line.id), selected: true);
      }
      // Lines are shared one by one now, not M-Pesa as a whole.
      await ref
          .read(routingRulesProvider.notifier)
          .shareLine(mpesaInstitutionId, null);

      if (ref.read(smsSourceProvider) is ShortcutConnection) {
        await _sortStored(db, lines);
      } else {
        final range = await ref.read(scanRangeProvider.future);
        final now = ref.read(clockProvider)();
        await ref
            .read(smsScanServiceProvider)
            .scan(
              [mpesaInstitution(ref)],
              from: range.firstDay(CalendarDate.local(now))?.startInstant,
              again: true,
              onProgress: (done, total) {
                if (ref.mounted) {
                  state = LineSplitState(
                    LineSplitStage.splitting,
                    done: done,
                    total: total,
                  );
                }
              },
            );
      }
      final routing = ref.read(mpesaLineRoutingProvider);
      for (final line in lines.lines) {
        final choice = choices[line.id];
        if (choice == null) continue;
        await routing.choose(line.id, choice);
      }
      if (ref.mounted) {
        state = LineSplitState(
          LineSplitStage.finished,
          done: state.total,
          total: state.total,
        );
      }
    } on Object catch (error) {
      if (kDebugMode) debugPrint('Splitting M-Pesa lines failed: $error');
      if (ref.mounted) state = const LineSplitState(LineSplitStage.failed);
    }
  }

  Ref get _ref => ref;

  /// On iPhone no past messages are kept to read again: the stored M-Pesa
  /// transactions move to their lines by the balance each printed.
  Future<void> _sortStored(AppDatabase db, MpesaLines lines) async {
    final t = db.transactions;
    final a = db.accounts;
    final rows =
        await (db.select(t).join([innerJoin(a, a.id.equalsExp(t.accountId))])
              ..where(
                a.institutionId.equals(mpesaInstitutionId) &
                    (a.reference.isNull() |
                        a.reference.equals(pochiReference).not()),
              )
              ..orderBy([OrderingTerm.asc(t.occurredAt)]))
            .get();
    final stored = [
      for (final row in rows)
        if (row.readTable(t) case final tx)
          StoredLineFacts(
            tx.id,
            LineFacts(
              hash: tx.messageHash ?? 'tx:${tx.id}',
              at: tx.occurredAt,
              amountMinor: tx.amountMinor,
              feeMinor: tx.feeMinor,
              inflow: tx.direction == TransactionDirection.inflow,
              balanceMinor: tx.balanceAfterMinor,
            ),
          ),
    ];
    final placed = placeStored(lines, stored);
    final accounts = ref.read(accountsRepositoryProvider);
    final balances = ref.read(balancesRepositoryProvider);
    final mpesa = mpesaInstitution(ref);
    final byLine = <String, int>{};
    for (final (i, row) in rows.indexed) {
      final tx = row.readTable(t);
      final lineId = placed[tx.id];
      if (lineId == null) continue;
      final accountId = byLine[lineId] ??= await accounts.accountForInstitution(
        mpesa.id,
        name: mpesa.name,
        type: mpesa.type,
        openingDate: tx.occurredAt,
        currency: tx.currency,
        reference: lineReference(lineId),
      );
      if (tx.accountId != accountId) {
        await balances.moveToAccount(tx.id, accountId);
      }
      if (ref.mounted) {
        state = LineSplitState(
          LineSplitStage.splitting,
          done: i + 1,
          total: rows.length,
        );
      }
    }
  }

  /// Back to the start, once the result is seen.
  void reset() => state = LineSplitState.idle;
}

final lineSplitControllerProvider =
    NotifierProvider<LineSplitController, LineSplitState>(
      LineSplitController.new,
    );

/// The open space's M-Pesa line accounts and their lines, by account id.
final lineAccountsProvider = Provider<Map<int, MpesaLine>>((ref) {
  final lines = ref.watch(mpesaLinesProvider).value;
  final accounts = ref.watch(activityAccountsProvider).value;
  if (lines == null || accounts == null || !lines.split) return const {};
  return {
    for (final account in accounts.values)
      if (lineOfReference(account.reference) case final id?)
        account.id: ?lines.line(id),
  };
});

/// The open space's line accounts that it reads: a line given to another
/// space leaves its empty account behind, which is not shown.
final readLineAccountsProvider = Provider<Map<int, MpesaLine>>((ref) {
  final lines = ref.watch(mpesaLinesProvider).value;
  final here = ref.watch(activeSpaceIdProvider);
  final listed = {
    for (final s in ref.watch(spacesProvider).value ?? const [Space.personal])
      s.id,
  };
  if (lines == null) return const {};
  return {
    for (final MapEntry(:key, :value)
        in ref.watch(lineAccountsProvider).entries)
      if (lines.readerOf(value, listed) == here) key: value,
  };
});

/// Account names that say the line: `M-Pesa · Shop line`. [all] are the
/// open space's accounts.
Map<int, Account> withLineNames(
  Map<int, Account> all,
  Map<int, MpesaLine> lines,
) => {
  for (final MapEntry(:key, :value) in all.entries)
    key: lines[key] == null
        ? value
        : value.copyWith(name: '${value.name} · ${lines[key]!.label}'),
};

/// Line accounts given to another space, left empty here: kept out of
/// lists of accounts.
final hiddenLineAccountsProvider = Provider<Set<int>>((ref) {
  final read = ref.watch(readLineAccountsProvider);
  return {
    for (final id in ref.watch(lineAccountsProvider).keys)
      if (!read.containsKey(id)) id,
  };
});
