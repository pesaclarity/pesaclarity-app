import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../data/database/app_database.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/reader_templates_repository.dart';
import '../../../data/repositories/review_inbox_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/reader/message_reading.dart';
import '../../../domain/reader/reader_tokens.dart';
import '../../../domain/reader/reading_template.dart';
import '../../../domain/reader/rule_reader.dart';
import '../../accounts/domain/institution.dart';
import '../../categoriser/data/tflite_flutter_runtime.dart';
import '../data/reader_store.dart';
import 'review_draft.dart';

/// Opens the reader's TFLite model. Override in tests with a fake.
final readerRuntimeOpenerProvider = Provider<ReaderRuntimeOpener>(
  (ref) => TfliteReaderRuntime.open,
);

/// Where an installed reader model is read from. No model ships with the
/// app yet; until one is installed the rules reader is used.
final readerFolderProvider = FutureProvider<Directory>(
  (ref) async => Directory(
    p.join((await getApplicationSupportDirectory()).path, readerFolderName),
  ),
);

/// The trained reader when installed, else the rules reader.
final messageReaderProvider = FutureProvider<MessageReader>((ref) async {
  final Directory folder;
  try {
    folder = await ref.watch(readerFolderProvider.future);
  } on Object {
    return const RuleMessageReader();
  }
  final reader = await loadReader(
    folder,
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
    final accountId = await _ref
        .read(accountsRepositoryProvider)
        .accountForInstitution(
          institution.id,
          name: institution.name,
          type: institution.type,
          openingDate: when,
        );
    await _ref.read(transactionsRepositoryProvider).addNew([
      draft.toTransaction(
        accountId: accountId,
        receivedAt: item.receivedAt,
        messageHash: item.messageHash,
        currency: institution.pack.currency,
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
