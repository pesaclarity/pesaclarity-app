import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database_providers.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../domain/savings/savings_account.dart';
import '../../../domain/savings/savings_product.dart';
import '../../../domain/savings/savings_prompt.dart';
import '../../../domain/spaces/space.dart';

// What the savings screens watch. Each follows the records, so a new
// payment, a typed balance or an answer shows without being asked for.

/// Counts changes behind the savings providers: the ledger's, and the
/// answers kept in settings ("It's not mine", the one-time line).
final savingsChangesProvider = StreamProvider<int>((ref) async* {
  var count = 0;
  await for (final _ in ref.watch(savingsRepositoryProvider).watchChanges()) {
    yield ++count;
  }
});

/// Whether savings accounts are offered in the open space: only Personal
/// keeps them in this version.
final savingsOfferedProvider = Provider<bool>(
  (ref) => ref.watch(activeSpaceIdProvider) == personalSpaceId,
);

/// Every savings account the open space keeps, oldest first.
final savingsAccountsProvider = FutureProvider<List<SavingsAccountSummary>>((
  ref,
) async {
  ref.watch(savingsChangesProvider);
  return ref.watch(savingsRepositoryProvider).accounts();
});

/// One savings account, by account id; null when it is not one.
final savingsAccountProvider =
    FutureProvider.family<SavingsAccountSummary?, int>((ref, accountId) async {
      ref.watch(savingsChangesProvider);
      return ref.watch(savingsRepositoryProvider).account(accountId);
    });

/// The question to ask under a payment in Activity, "Is this your Chumz
/// savings?": null when there is nothing to ask, after "It's not mine",
/// once the product is added, and in every space but Personal.
final savingsPromptProvider = FutureProvider<SavingsPrompt?>((ref) async {
  ref.watch(savingsChangesProvider);
  if (!ref.watch(savingsOfferedProvider)) return null;
  return ref.watch(savingsRepositoryProvider).prompt();
});

/// What the records show of a savings product, by product id, for the sheet
/// that adds it: the account codes to name and the payments that would
/// change. Null for a product this app does not know.
final savingsDiscoveryProvider =
    FutureProvider.family<SavingsDiscovery?, String>((ref, productId) async {
      ref.watch(savingsChangesProvider);
      final product = savingsProductById(productId);
      if (product == null) return null;
      return ref.watch(savingsRepositoryProvider).discover(product);
    });

/// The line to show once after a savings product was added, under the
/// payment the question was asked under. Null once it was seen.
final savingsAddedNoticeProvider = FutureProvider<SavingsAddedNotice?>((
  ref,
) async {
  ref.watch(savingsChangesProvider);
  return ref.watch(savingsRepositoryProvider).addedNotice();
});

/// What a transaction, by id, is to a savings account: an entry on one, or
/// the payment such an entry mirrors. Null for every other transaction.
/// Such transactions are not unmatched, moved or undone one by one.
final savingsEntryProvider = FutureProvider.family<SavingsEntryLink?, int>((
  ref,
  transactionId,
) async {
  ref.watch(savingsChangesProvider);
  return ref.watch(savingsRepositoryProvider).entryOf(transactionId);
});
