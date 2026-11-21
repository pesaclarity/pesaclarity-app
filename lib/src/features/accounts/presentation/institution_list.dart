import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/database/space_databases.dart';
import '../../../data/repositories/institutions_repository.dart';
import '../../../domain/spaces/space.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/semantic_ids.dart';
import '../../spaces/application/spaces_providers.dart';
import '../application/my_accounts_providers.dart';
import '../domain/institution.dart';

/// How each institution is shown: ticked during onboarding, switched later.
enum InstitutionControl { checkbox, toggle }

/// The institution catalogue with a control per row that saves the choice.
class InstitutionList extends ConsumerWidget {
  const InstitutionList({required this.control, super.key});

  final InstitutionControl control;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(institutionCatalogueProvider);
    final selected = ref.watch(selectedInstitutionIdsProvider).value;

    return Card(
      child: Column(
        children: [
          for (final (index, institution) in catalogue.indexed) ...[
            if (index > 0) const Divider(height: 1),
            _InstitutionTile(
              institution: institution,
              control: control,
              selected: selected?.contains(institution.id) ?? false,
              enabled: selected != null,
              onChanged: (value) => value
                  ? _switchOn(context, ref, institution)
                  : ref
                        .read(institutionsRepositoryProvider)
                        .setSelected(institution.id, selected: false),
            ),
          ],
        ],
      ),
    );
  }
}

/// Switches [institution] on in the open space, unless another space reads
/// it: each account is read in one space. Then it says where, and in a
/// business leads to Business or personal, where it can be shared.
Future<void> _switchOn(
  BuildContext context,
  WidgetRef ref,
  Institution institution,
) async {
  final reader = await ref
      .read(spaceDatabasesProvider)
      .readerOf(institution.id);
  if (reader == null) {
    await ref
        .read(institutionsRepositoryProvider)
        .setSelected(institution.id, selected: true);
    return;
  }
  if (!context.mounted) return;
  final here = ref.read(activeSpaceProvider);
  final share = reader.id == personalSpaceId && here.kind == SpaceKind.business;
  final body = share
      ? 'Each account is read in one space. Choose in Business or personal '
            'whether its money is for ${here.name}, Personal or both.'
      : here.id == personalSpaceId && reader.kind == SpaceKind.business
      ? 'Each account is read in one space. To use it for both, open '
            '${reader.name} and choose in Business or personal.'
      : 'Each account is read in one space. Switch it off in ${reader.name} '
            'first to read it here.';
  final choose = await showAdaptiveDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text('${reader.name} reads ${institution.name}'),
      content: Text(body),
      actions: [
        if (share) ...[
          DialogAction(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Not now'),
          ),
          DialogAction(
            key: const Key('institution-choose-line'),
            filled: true,
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Choose'),
          ),
        ] else
          DialogAction(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('OK'),
          ),
      ],
    ),
  );
  if ((choose ?? false) && context.mounted) {
    await context.push(AppRoutes.businessOrPersonal);
  }
}

class _InstitutionTile extends StatelessWidget {
  const _InstitutionTile({
    required this.institution,
    required this.control,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final Institution institution;
  final InstitutionControl control;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final title = Text(institution.name);
    final subtitle = Text('Messages from ${institution.senderIds.join(', ')}');
    final onChanged = enabled ? (bool? v) => this.onChanged(v ?? false) : null;

    final tile = switch (control) {
      InstitutionControl.checkbox => CheckboxListTile(
        value: selected,
        onChanged: onChanged,
        title: title,
        subtitle: subtitle,
        controlAffinity: ListTileControlAffinity.trailing,
      ),
      InstitutionControl.toggle => SwitchListTile.adaptive(
        value: selected,
        onChanged: onChanged,
        title: title,
        subtitle: subtitle,
      ),
    };
    // Merged so the id lands on the node that carries the checked state.
    return MergeSemantics(
      child: Semantics(
        identifier: SemanticIds.institution(institution.id),
        child: tile,
      ),
    );
  }
}
