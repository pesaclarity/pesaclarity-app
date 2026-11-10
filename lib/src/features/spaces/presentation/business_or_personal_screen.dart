import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database_providers.dart';
import '../../../data/repositories/institutions_repository.dart';
import '../../../domain/spaces/line_routing.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/states.dart';
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
    final loads = [
      ref.watch(selectedInstitutionIdsProvider),
      ref.watch(personalLinesProvider),
      ref.watch(routingRulesProvider),
    ];
    final failed = loads.any((l) => l.hasError && !l.hasValue);
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
      body: failed
          ? ErrorView(
              'Your accounts could not load.',
              onRetry: () {
                ref
                  ..invalidate(selectedInstitutionIdsProvider)
                  ..invalidate(personalLinesProvider)
                  ..invalidate(routingRulesProvider);
              },
            )
          : loading
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
                  const EmptyNote(
                    'Add accounts in My accounts, then choose here.',
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final (i, line) in lines.indexed) ...[
                          if (i > 0) const Divider(height: 1),
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
                            trailing: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: _choiceWidth,
                              ),
                              child: ChoiceMenu<LineChoice>(
                                key: Key('line-choice-${line.id}'),
                                name: line.name,
                                value: lineChoiceOf(
                                  inBusiness: inBusiness.contains(line.id),
                                  inPersonal: inPersonal.contains(line.id),
                                  shared: shared.contains(line.id),
                                ),
                                options: [
                                  (LineChoice.thisBusiness, space.name),
                                  (LineChoice.personal, 'Personal'),
                                  (LineChoice.both, 'Both'),
                                ],
                                itemKey: (choice) => Key(
                                  'line-choice-${line.id}-${choice.name}',
                                ),
                                onChanged: (choice) => choose(line, choice),
                              ),
                            ),
                          ),
                        ],
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

/// How wide a line's choice can grow before a long business name is cut
/// short.
const _choiceWidth = 160.0;
