import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/reader_templates_repository.dart';
import '../../../data/repositories/review_inbox_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/reader/reading_template.dart';
import '../../accounts/domain/institution.dart';
import '../../review/application/review_draft.dart';
import 'transaction_mapping.dart';

/// Parses [messages] with [packs]; one result per message, in order.
typedef SmsParseBatch = Future<List<ParseResult>> Function(
  List<ParserPack> packs,
  List<SmsMessage> messages,
);

/// Parses on a background isolate so a large scan never blocks the UI.
Future<List<ParseResult>> parseInBackground(
  List<ParserPack> packs,
  List<SmsMessage> messages,
) => Isolate.run(() => parseAll(packs, messages));

/// Parses on the calling isolate.
List<ParseResult> parseAll(List<ParserPack> packs, List<SmsMessage> messages) {
  final parser = SmsParser(packs);
  return [for (final message in messages) parser.parse(message)];
}

/// What one batch of messages turned into.
@immutable
class SmsIngestSummary {
  const SmsIngestSummary({
    this.added = 0,
    this.duplicates = 0,
    this.forReview = 0,
    this.ignored = 0,
  });

  /// New transactions stored.
  final int added;

  /// Transactions already in the ledger, such as from an earlier scan.
  final int duplicates;

  /// Messages from selected senders that no rule matched, newly in review.
  final int forReview;

  /// Messages from senders that are not selected, dropped unstored.
  final int ignored;

  SmsIngestSummary operator +(SmsIngestSummary other) => SmsIngestSummary(
    added: added + other.added,
    duplicates: duplicates + other.duplicates,
    forReview: forReview + other.forReview,
    ignored: ignored + other.ignored,
  );

  @override
  bool operator ==(Object other) =>
      other is SmsIngestSummary &&
      other.added == added &&
      other.duplicates == duplicates &&
      other.forReview == forReview &&
      other.ignored == ignored;

  @override
  int get hashCode => Object.hash(added, duplicates, forReview, ignored);

  @override
  String toString() =>
      'SmsIngestSummary(added: $added, duplicates: $duplicates, '
      'forReview: $forReview, ignored: $ignored)';
}

/// Turns messages into ledger transactions and review items.
///
/// Parsed messages keep only their fields and hash. Unmatched messages from
/// selected senders go to the review inbox, the one place their text is
/// kept. Messages from any other sender are dropped.
/// The first template [message] fits, read into a complete draft, or null.
ReviewDraft? _readWith(List<ReadingTemplate> templates, String message) {
  for (final template in templates) {
    final reading = template.read(message);
    if (reading == null) continue;
    final draft = ReviewDraft.fromReading(reading);
    if (draft.isComplete) return draft;
  }
  return null;
}

class SmsIngestor {
  SmsIngestor({
    required this._accounts,
    required this._transactions,
    required this._reviewInbox,
    this._templates,
    this._parse = parseInBackground,
  });

  final AccountsRepository _accounts;
  final TransactionsRepository _transactions;
  final ReviewInboxRepository _reviewInbox;

  /// Layouts the person asked to be read the same way; a message that fits
  /// one skips the review inbox.
  final ReaderTemplatesRepository? _templates;
  final SmsParseBatch _parse;

  /// Ingests [messages], reading only those from the [selected] institutions.
  Future<SmsIngestSummary> ingest(
    List<SmsMessage> messages,
    List<Institution> selected,
  ) async {
    if (messages.isEmpty) return const SmsIngestSummary();
    if (selected.isEmpty) return SmsIngestSummary(ignored: messages.length);

    final results = await _parse([
      for (final institution in selected) institution.pack,
    ], messages);

    final parsedByPack = <String, List<ParsedTransaction>>{};
    final readByPack = <String, List<(ReviewDraft, SmsMessage, String)>>{};
    final templates = <String, List<ReadingTemplate>>{};
    var forReview = 0;
    var ignored = 0;
    for (final result in results) {
      switch (result) {
        case ParsedTransaction():
          (parsedByPack[result.packId] ??= []).add(result);
        case Unmatched(:final message):
          final known = _templates == null
              ? const <ReadingTemplate>[]
              : templates[result.packId] ??= await _templates.forInstitution(
                  result.packId,
                );
          final draft = _readWith(known, message.body);
          if (draft != null) {
            (readByPack[result.packId] ??= []).add((
              draft,
              message,
              result.rawHash,
            ));
            continue;
          }
          final added = await _reviewInbox.addIfNew(
            institutionId: result.packId,
            sender: message.sender,
            receivedAt: message.receivedAt,
            messageHash: result.rawHash,
            body: message.body,
            reason: result.reason,
          );
          if (added) forReview++;
        case Ignored():
          ignored++;
      }
    }

    var added = 0;
    var parsedCount = 0;
    final institutions = {for (final i in selected) i.id: i};

    // Each account gets the messages that show its number and currency,
    // oldest first so an account from before numbers were read takes the
    // first number it sees.
    final pending = <(String, String?, String), List<Object>>{};
    final firstSeen = <(String, String?, String), DateTime>{};
    void note((String, String?, String) key, DateTime when, Object item) {
      (pending[key] ??= []).add(item);
      final seen = firstSeen[key];
      if (seen == null || when.isBefore(seen)) firstSeen[key] = when;
    }

    for (final MapEntry(key: packId, value: read) in readByPack.entries) {
      final institution = institutions[packId]!;
      for (final (draft, message, hash) in read) {
        final currency = draft.currency ?? institution.pack.currency;
        note(
          (packId, null, currency),
          draft.occurredAt(message.receivedAt),
          (draft, message, hash),
        );
      }
    }
    for (final MapEntry(key: packId, value: parsed) in parsedByPack.entries) {
      for (final p in parsed) {
        note((packId, p.ownAccount, p.currency), p.time, p);
      }
    }
    final keys = pending.keys.toList()
      ..sort((a, b) => firstSeen[a]!.compareTo(firstSeen[b]!));
    for (final key in keys) {
      final (packId, reference, currency) = key;
      final institution = institutions[packId]!;
      final accountId = await _accounts.accountForInstitution(
        institution.id,
        name: institution.name,
        type: institution.type,
        openingDate: firstSeen[key]!,
        currency: currency,
        reference: reference,
      );
      final rows = [
        for (final item in pending[key]!)
          switch (item) {
            ParsedTransaction() => transactionFromParsed(
              item,
              accountId: accountId,
            ),
            (
              final ReviewDraft draft,
              final SmsMessage message,
              final String hash,
            ) =>
              draft.toTransaction(
                accountId: accountId,
                receivedAt: message.receivedAt,
                messageHash: hash,
                currency: currency,
              ),
            _ => throw StateError('unexpected $item'),
          },
      ];
      added += await _transactions.addNew(rows);
      parsedCount += rows.length;
    }

    return SmsIngestSummary(
      added: added,
      duplicates: parsedCount - added,
      forReview: forReview,
      ignored: ignored,
    );
  }
}
