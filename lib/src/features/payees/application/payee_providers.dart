import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/repositories/categories_repository.dart';
import '../../../data/repositories/payees_repository.dart';
import '../../../data/repositories/tags_repository.dart';
import '../../../data/repositories/transactions_repository.dart';

/// Every category, by name.
final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoriesRepositoryProvider).watchAll(),
);

/// Every tag with how many transactions carry it, by name.
final tagUsageProvider = StreamProvider<List<TagUse>>(
  (ref) => ref.watch(tagsRepositoryProvider).watchUsage(),
);

/// Named payees for the Payees list.
final payeeSummariesProvider = StreamProvider<List<PayeeSummary>>(
  (ref) => ref.watch(payeesRepositoryProvider).watchSummaries(),
);

/// Numbers, tills and paybills waiting for a name.
final unnamedPartiesProvider = StreamProvider<List<UnnamedParty>>(
  (ref) => ref.watch(payeesRepositoryProvider).watchUnnamed(),
);

/// One transaction for its detail sheet.
final transactionDetailProvider = StreamProvider.autoDispose
    .family<TransactionDetail?, int>(
      (ref, id) => ref.watch(transactionsRepositoryProvider).watchDetail(id),
    );

/// The tags on one transaction, by name.
final transactionTagsProvider = StreamProvider.autoDispose
    .family<List<Tag>, int>(
      (ref, id) => ref.watch(tagsRepositoryProvider).watchTagsOf(id),
    );

/// How many transactions each category holds, for the picker's most used.
final categoryUsageProvider = StreamProvider<Map<int, int>>(
  (ref) => ref.watch(categoriesRepositoryProvider).watchUsage(),
);
