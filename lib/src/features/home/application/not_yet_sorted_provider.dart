import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/repositories/ledger_history.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/ledger/not_yet_sorted.dart';
import '../../../domain/reader/message_reading.dart';
import '../../accounts/domain/institution.dart';
import '../../review/application/review_draft.dart';
import '../../review/application/review_providers.dart';

/// Money not yet sorted in the open space, for Home: money in from people
/// not named yet and messages waiting to be checked. Balance gaps are not
/// part of it; Home warns about them on their own line.
///
/// Each space keeps its own database, so this only ever sees the open one.
final notYetSortedProvider = FutureProvider<NotYetSorted>((ref) async {
  ref.watch(ledgerChangesProvider);
  final items = await ref.watch(pendingReviewProvider.future);
  final entries = await readLedgerHistory(
    ref,
    from: DateTime.utc(1970),
    to: DateTime.utc(3000),
  );
  // The reader only loads when there is something for it to read.
  final reader = items.isEmpty
      ? null
      : await ref.watch(messageReaderProvider.future);
  final catalogue = ref.watch(institutionCatalogueProvider);
  return NotYetSorted.of(entries, [
    for (final item in items)
      messageToCheck(item, reader: reader, institutions: catalogue),
  ]);
});

/// What [reader] makes of [item]'s amount, in the currency it would be
/// added in: the one printed with the amount, else the institution's.
MessageToCheck messageToCheck(
  ReviewItem item, {
  required MessageReader? reader,
  required List<Institution> institutions,
}) {
  final body = item.body;
  if (reader == null || body == null) {
    return (amountMinor: null, currency: null);
  }
  final draft = ReviewDraft.fromReading(reader.read(body));
  if (!draft.isComplete) return (amountMinor: null, currency: null);
  String? packCurrency;
  for (final i in institutions) {
    if (i.id == item.institutionId) packCurrency = i.pack.currency;
  }
  return (
    amountMinor: draft.amountMinor,
    currency: draft.currency ?? packCurrency,
  );
}
