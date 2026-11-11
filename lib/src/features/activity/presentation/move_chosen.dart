import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database_providers.dart';
import '../../../data/repositories/space_move_repository.dart';
import '../../../domain/spaces/space.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/states.dart';
import '../../spaces/application/spaces_providers.dart';

/// "3 chosen", with Move to another space and Done, in place of the title
/// while transactions are chosen.
class MoveChosenBar extends ConsumerWidget {
  const MoveChosenBar({required this.chosen, required this.onDone, super.key});

  final Set<int> chosen;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeSpaceIdProvider);
    final others = [
      for (final s in ref.watch(spacesProvider).value ?? const <Space>[])
        if (s.id != activeId) s,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          IconButton(
            key: const Key('activity-choose-done'),
            tooltip: 'Done choosing',
            icon: const Icon(Icons.close),
            onPressed: onDone,
          ),
          Expanded(
            child: Text(
              '${chosen.length} chosen',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (others.isNotEmpty)
            PillButton(
              key: const Key('activity-move-chosen'),
              label: 'Move',
              icon: Icons.drive_file_move_outline,
              tooltip: 'Move to another space',
              onPressed: () async {
                final moved = await showAppSheet<String>(
                  context: context,
                  builder: (_) =>
                      _MoveSheet(ids: chosen.toList(), others: others),
                );
                if (moved != null && context.mounted) {
                  onDone();
                  showNote(context, 'Moved to $moved.');
                }
              },
            ),
        ],
      ),
    );
  }
}

class _MoveSheet extends ConsumerStatefulWidget {
  const _MoveSheet({required this.ids, required this.others});

  final List<int> ids;
  final List<Space> others;

  @override
  ConsumerState<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends ConsumerState<_MoveSheet> {
  late var _to = widget.others.first;
  var _busy = false;

  /// Null matches each one's category in the other space.
  int? _category;
  late var _categories = _load();

  Future<List<({int id, String name})>> _load() =>
      ref.read(spaceMoveRepositoryProvider).categoriesIn(_to.id);

  @override
  Widget build(BuildContext context) {
    final from = ref.watch(activeSpaceProvider).name;
    final n = widget.ids.length;
    final things = n == 1 ? '1 transaction' : '$n transactions';
    return SheetBody(
      title: 'Move to another space',
      children: [
        Text(
          '$things leave $from and go to the space you choose.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            title: const Text('Move to'),
            trailing: ChoiceMenu<Space>(
              key: const Key('move-chosen-to'),
              name: 'Move to',
              options: [for (final s in widget.others) (s, s.name)],
              value: _to,
              itemKey: (s) => Key('move-chosen-to-${s.id}'),
              onChanged: (s) => setState(() {
                _to = s;
                _category = null;
                _categories = _load();
              }),
            ),
          ),
        ),
        FutureBuilder(
          future: _categories,
          builder: (context, snapshot) {
            final list = snapshot.data ?? const [];
            return Card(
              child: ListTile(
                title: const Text('Category there'),
                subtitle: Text('Chosen in ${_to.name}'),
                trailing: ChoiceMenu<int?>(
                  key: const Key('move-chosen-category'),
                  name: 'Category there',
                  options: [
                    (null, 'Match each one'),
                    for (final c in list) (c.id, c.name),
                  ],
                  value: _category,
                  itemKey: (id) => Key('move-chosen-category-${id ?? 'match'}'),
                  onChanged: (id) => setState(() => _category = id),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Notice(
          'They move, not copy: $from will not have them any more. Only the '
          'transactions go; payees stay in $from.',
          icon: Icons.lock_outline,
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('move-chosen-confirm'),
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final navigator = Navigator.of(context);
                  final repo = ref.read(spaceMoveRepositoryProvider);
                  for (final id in widget.ids) {
                    await repo.move(id, _to.id, toCategoryId: _category);
                  }
                  navigator.pop(_to.name);
                },
          child: Text('Move $things'),
        ),
      ],
    );
  }
}
