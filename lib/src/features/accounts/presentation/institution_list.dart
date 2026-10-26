import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/institutions_repository.dart';
import '../../../shared/semantic_ids.dart';
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
              onChanged: (value) => ref
                  .read(institutionsRepositoryProvider)
                  .setSelected(institution.id, selected: value),
            ),
          ],
        ],
      ),
    );
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
      InstitutionControl.toggle => SwitchListTile(
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
