import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/database/database_providers.dart';
import '../../../data/repositories/institutions_repository.dart';
import '../../../domain/accounts/mpesa_lines.dart';
import '../../../domain/spaces/line_routing.dart';
import '../../../domain/spaces/money_between_spaces.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/pesa_colors.dart';
import '../../accounts/application/mpesa_lines_providers.dart';
import '../../accounts/application/my_accounts_providers.dart';
import '../../accounts/domain/institution.dart';
import '../application/routing_providers.dart';
import '../application/spaces_providers.dart';
import 'till_sheet.dart';

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
    // Split M-Pesa lines are each given a space in My accounts, M-Pesa
    // lines.
    final split = ref.watch(mpesaLinesProvider).value?.split ?? false;
    final lines = [
      for (final i in ref.watch(institutionCatalogueProvider))
        if (!loading &&
            !(split && i.id == mpesaInstitutionId) &&
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
                          if (shared.contains(line.id))
                            _LineChannelsRows(
                              line: line,
                              channels: rules.channelsOn(line.id),
                              business: space.name,
                            ),
                        ],
                      ],
                    ),
                  ),
                for (final line in lines)
                  if (shared.contains(line.id))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '${line.name}: used for both. It stays in Personal; '
                        'the ${shortSpaceName(space.name)} keeps what is its '
                        'own.',
                        key: Key('line-both-note-${line.id}'),
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: colors.textMuted,
                        ),
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

/// Under a line used for both: the business's own till or paybill, and
/// whether customers also send money to the owner's number (decision 0027,
/// section 4; owner's decisions 15 and 17).
class _LineChannelsRows extends ConsumerWidget {
  const _LineChannelsRows({
    required this.line,
    required this.channels,
    required this.business,
  });

  final Institution line;
  final LineChannels channels;
  final String business;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final named = channels.named;
    return Column(
      children: [
        const Divider(height: 1),
        ListTile(
          key: Key('line-till-${line.id}'),
          title: const Text("Your business's till or paybill"),
          subtitle: Text(
            named.isEmpty
                ? 'None yet'
                : [for (final (k, n) in named) channelLabel(k, n)].join(', '),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showTillSheet(context, line: line.id),
        ),
        const Divider(height: 1),
        SwitchListTile.adaptive(
          key: Key('line-customers-to-number-${line.id}'),
          value: channels.customersToNumber,
          title: const Text('Customers also send money to my number'),
          subtitle: Text(
            'Then the ${shortSpaceName(business)} asks about those payments',
          ),
          onChanged: (on) async {
            await ref
                .read(routingRulesProvider.notifier)
                .setChannels(line.id, channels.copyWith(customersToNumber: on));
            ref.invalidate(sharedLineQuestionsProvider);
          },
        ),
      ],
    );
  }
}
