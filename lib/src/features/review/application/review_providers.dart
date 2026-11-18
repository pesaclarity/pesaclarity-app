import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/reader_templates_repository.dart';
import '../../../data/repositories/review_inbox_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/reader/fuliza_wording.dart';
import '../../../domain/reader/message_reading.dart';
import '../../../domain/reader/reader_tokens.dart';
import '../../../domain/reader/reading_template.dart';
import '../../accounts/domain/institution.dart';
import '../../ask/data/ask_model_store.dart' show AssetReader;
import '../data/rayo_reader_runtime.dart';
import '../data/reader_store.dart';
import 'review_draft.dart';

/// Opens `reader.weights` on rayo, the same in every build. Where rayo's
/// library cannot load, the review inbox uses the rules reader. Override
/// with null to use the rules only, or with a fake in tests.
final readerRuntimeOpenerProvider = Provider<ReaderRuntimeOpener?>(
  (ref) => openMessageReader,
);

/// Reads the bundled reader files; null when absent.
final readerAssetReaderProvider = Provider<AssetReader>(
  (ref) => (path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object {
      return null;
    }
  },
);

/// The trained reader (`assets/models/reader/reader.weights`) when bundled
/// and rayo runs it, else the rules reader. Loaded the first time a message
/// needs reading.
final messageReaderProvider = FutureProvider<MessageReader>((ref) async {
  final reader = await loadReader(
    readAsset: ref.watch(readerAssetReaderProvider),
    openRuntime: ref.watch(readerRuntimeOpenerProvider),
  );
  ref.onDispose(reader.close);
  return reader;
});

/// Messages waiting to be checked, oldest first.
final pendingReviewProvider = StreamProvider<List<ReviewItem>>(
  (ref) => ref.watch(reviewInboxRepositoryProvider).watchPending(),
);

/// What the reader makes of review item [id]'s message, or null once the
/// item is gone or while the reader loads.
final reviewReadingProvider = Provider.family<MessageReading?, int>((ref, id) {
  final reader = ref.watch(messageReaderProvider).value;
  final items = ref.watch(pendingReviewProvider).value;
  if (reader == null || items == null) return null;
  for (final item in items) {
    if (item.id == id) return reader.read(item.body ?? '');
  }
  return null;
});

/// Adds checked messages to the ledger or sets them aside.
class ReviewController {
  ReviewController(this._ref);

  final Ref _ref;

  Institution? _institution(String id) {
    for (final i in _ref.read(institutionCatalogueProvider)) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Adds [draft] for [item] and clears the message text. With [sameWay],
  /// keeps the layout so later messages like it are read without asking;
  /// only fields the person left as suggested become part of it.
  Future<void> confirm(
    ReviewItem item,
    ReviewDraft draft, {
    required MessageReading reading,
    required bool sameWay,
  }) async {
    final institution = _institution(item.institutionId);
    if (institution == null || !draft.isComplete) return;
    final when = draft.occurredAt(item.receivedAt);
    final currency = draft.currency ?? institution.pack.currency;
    final accountId = await _ref
        .read(accountsRepositoryProvider)
        .accountForInstitution(
          institution.id,
          name: institution.name,
          type: institution.type,
          openingDate: when,
          currency: currency,
        );
    await _ref.read(transactionsRepositoryProvider).addNew([
      draft.toTransaction(
        accountId: accountId,
        receivedAt: item.receivedAt,
        messageHash: item.messageHash,
        currency: currency,
        ledgerKind: item.body == null ? null : fulizaKindIn(item.body!),
      ),
    ]);
    final body = item.body;
    if (sameWay && body != null) {
      final template = learnTemplate(body, reading, draft);
      if (template != null) {
        await _ref
            .read(readerTemplatesRepositoryProvider)
            .add(item.institutionId, template);
      }
    }
    await _ref.read(reviewInboxRepositoryProvider).resolve(item.id);
  }

  /// The account [item]'s messages feed, made the first time it is needed.
  Future<int?> messageAccount(ReviewItem item, {String? currency}) async {
    final institution = _institution(item.institutionId);
    if (institution == null) return null;
    return _ref
        .read(accountsRepositoryProvider)
        .accountForInstitution(
          institution.id,
          name: institution.name,
          type: institution.type,
          openingDate: item.receivedAt,
          currency: currency ?? institution.pack.currency,
        );
  }

  /// Adds [item] as money moved between the person's own accounts: out of
  /// the message's account into [otherAccountId] when [messageIsFrom], else
  /// the other way. It pairs at once with [partnerId] when the other side is
  /// already here, else it waits up to three days for it. Returns the new
  /// transaction's id, or null when the accounts are the same.
  Future<int?> confirmOwnTransfer(
    ReviewItem item, {
    required bool messageIsFrom,
    required int otherAccountId,
    required int amountMinor,
    required int feeMinor,
    required DateTime at,
    required String currency,
    int? partnerId,
  }) async {
    final own = await messageAccount(item, currency: currency);
    if (own == null || own == otherAccountId) return null;
    final transactions = _ref.read(transactionsRepositoryProvider);
    final id = await transactions.add(
      TransactionsCompanion.insert(
        accountId: own,
        occurredAt: at,
        amountMinor: amountMinor,
        direction: messageIsFrom
            ? TransactionDirection.outflow
            : TransactionDirection.inflow,
        kind: const Value(TransactionKind.bank),
        feeMinor: Value(messageIsFrom ? feeMinor : 0),
        currency: Value(currency),
        source: TransactionSource.sms,
        messageHash: Value(item.messageHash),
        transferAccountId: Value(otherAccountId),
      ),
    );
    if (partnerId != null) {
      await transactions.match(
        messageIsFrom ? id : partnerId,
        messageIsFrom ? partnerId : id,
      );
    } else {
      await transactions.pairOwnTransfers(from: at, to: at);
    }
    await _ref.read(reviewInboxRepositoryProvider).resolve(item.id);
    return id;
  }

  /// Clears [item]: it holds no transaction.
  Future<void> dismiss(ReviewItem item) =>
      _ref.read(reviewInboxRepositoryProvider).resolve(item.id);
}

/// A template from the fields of [reading] whose values the person kept in
/// [draft]. Null when the amount was changed, since its place in the
/// message is then unknown.
ReadingTemplate? learnTemplate(
  String message,
  MessageReading reading,
  ReviewDraft draft,
) {
  final suggested = ReviewDraft.fromReading(reading);
  final kept = <ReaderField>{
    if (draft.amountMinor == suggested.amountMinor) ReaderField.amount,
    if (draft.counterparty == suggested.counterparty) ReaderField.counterparty,
    if (draft.date == suggested.date) ReaderField.date,
    if (draft.minutes == suggested.minutes) ReaderField.time,
    ReaderField.balance,
    ReaderField.reference,
    ReaderField.fee,
  };
  final tokens = tokenise(message);
  final spans = <ReaderField, (int, int)>{};
  for (final f in reading.fields.values) {
    final range = tokenRange(tokens, f.start, f.end);
    if (kept.contains(f.field) && range != null) spans[f.field] = range;
  }
  return ReadingTemplate.learn(message, draft.kind, spans);
}

final reviewControllerProvider = Provider<ReviewController>(
  ReviewController.new,
);
