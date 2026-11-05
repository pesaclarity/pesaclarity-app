import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database_providers.dart';
import '../../../data/repositories/institutions_repository.dart';
import '../../../domain/spaces/line_routing.dart';
import '../../../theme/pesa_colors.dart';
import '../../accounts/application/my_accounts_providers.dart';
import '../../accounts/domain/institution.dart';
import '../application/routing_providers.dart';
import '../application/spaces_providers.dart';

/// Lines Personal reads, whichever space is open.
final personalLinesProvider = StreamProvider<Set<String>>(
  (ref) =>
      DriftInstitutionsRepository(ref.watch(personalDatabaseProvider))
          .watchSelectedIds(),
);

/// Business or personal: where each account's money goes, for the open
/// business.
class BusinessOrPersonalScreen extends ConsumerWidget {
  const BusinessOrPersonalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final space = ref.watch(activeSpaceProvider);
    final inBusiness = ref.watch(selectedInstitutionIdsProvider).value;
    final inPersonal = ref.watch(personalLinesProvider).value;
    final rules = ref.watch(routingRulesProvider).value;
    final loading = inBusiness == null || inPersonal == null || rules == null;
    final shared = rules?.sharedWith(space.id) ?? const <String>{};
    final lines = [
      for (final i in ref.watch(institutionCatalogueProvider))
        if (!loading &&
            (inBusiness.contains(i.id) ||
                inPersonal.contains(i.id) ||
                shared.contains(i.id)))
          i,
    ];
    final learnt = rules?.learntFor(space.id);

    Future<void> choose(Institution line, LineChoice choice) => ref
        .read(routingRulesProvider.notifier)
        .setLine(
          line.id,
          choice,
          businessId: space.id,
          business: ref.read(institutionsRepositoryProvider),
          personal: DriftInstitutionsRepository(
            ref.read(personalDatabaseProvider),
          ),
        )
        .then((_) => ref.invalidate(sharedLineQuestionsProvider));

    return Scaffold(
      appBar: AppBar(title: const Text('Business or personal')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  "Choose where each account's money goes. Shared accounts "
                  "ask when they can't tell.",
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: 16),
                if (lines.isEmpty)
                  Text(
                    'Add accounts in My accounts, then choose here.',
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final line in lines)
                          ListTile(
                            key: Key('line-${line.id}'),
                            title: Text(line.name),
                            subtitle: Text(switch (lineChoiceOf(
                              inBusiness: inBusiness.contains(line.id),
                              inPersonal: inPersonal.contains(line.id),
                              shared: shared.contains(line.id),
                            )) {
                              LineChoice.thisBusiness => 'Only ${space.name}',
                              LineChoice.personal => 'Only Personal',
                              LineChoice.both => 'Used for both',
                            }),
                            trailing: DropdownButton<LineChoice>(
                              key: Key('line-choice-${line.id}'),
                              value: lineChoiceOf(
                                inBusiness: inBusiness.contains(line.id),
                                inPersonal: inPersonal.contains(line.id),
                                shared: shared.contains(line.id),
                              ),
                              underline: const SizedBox.shrink(),
                              onChanged: (choice) {
                                if (choice != null) choose(line, choice);
                              },
                              items: [
                                DropdownMenuItem(
                                  value: LineChoice.thisBusiness,
                                  child: Text(space.name),
                                ),
                                const DropdownMenuItem(
                                  value: LineChoice.personal,
                                  child: Text('Personal'),
                                ),
                                const DropdownMenuItem(
                                  value: LineChoice.both,
                                  child: Text('Ask me'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                if (learnt != null && learnt.business + learnt.personal > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Card(
                      child: ListTile(
                        title: const Text('Learnt so far'),
                        subtitle: Text(
                          '${learnt.business} business · '
                          '${learnt.personal} personal, on shared accounts',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
