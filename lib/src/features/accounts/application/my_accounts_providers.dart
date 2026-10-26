import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/institutions_repository.dart';
import '../domain/institution.dart';

/// Ids of the institutions switched on in My accounts.
final selectedInstitutionIdsProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(institutionsRepositoryProvider).watchSelectedIds(),
);

/// SMS sender IDs the capture reads; every other sender is ignored.
final senderWatchListProvider = Provider<Set<String>>((ref) {
  final selected = ref.watch(selectedInstitutionIdsProvider).value ?? const {};
  return senderWatchList(ref.watch(institutionCatalogueProvider), selected);
});

/// The sender IDs of the [selected] institutions in [catalogue].
Set<String> senderWatchList(
  List<Institution> catalogue,
  Set<String> selected,
) => {
  for (final institution in catalogue)
    if (selected.contains(institution.id)) ...institution.senderIds,
};
