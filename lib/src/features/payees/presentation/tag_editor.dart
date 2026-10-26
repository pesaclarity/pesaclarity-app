import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/tags_repository.dart';
import '../../../domain/tags/tag_totals.dart';
import '../application/payee_providers.dart';

/// The tags on one transaction: remove any, add new ones or reuse earlier
/// ones. A transaction can carry any number of tags.
class TransactionTagsEditor extends ConsumerStatefulWidget {
  const TransactionTagsEditor({required this.transactionId, super.key});

  final int transactionId;

  @override
  ConsumerState<TransactionTagsEditor> createState() =>
      _TransactionTagsEditorState();
}

class _TransactionTagsEditorState extends ConsumerState<TransactionTagsEditor> {
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add(String name) async {
    if (cleanTagName(name) == null) return;
    final repo = ref.read(tagsRepositoryProvider);
    final id = await repo.findOrCreate(name);
    await repo.tag(widget.transactionId, id);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on =
        ref.watch(transactionTagsProvider(widget.transactionId)).value ??
        const [];
    final onIds = {for (final t in on) t.id};
    final typed = cleanTagName(_input.text);
    final suggestions = [
      for (final u in ref.watch(tagUsageProvider).value ?? const <TagUse>[])
        if (!onIds.contains(u.tag.id) &&
            (typed == null || u.tag.name.contains(typed)))
          u.tag,
    ].take(8);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tags', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Tags group spending across categories, like #roadtrip.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (on.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in on)
                InputChip(
                  label: Text('#${tag.name}'),
                  onDeleted: () => ref
                      .read(tagsRepositoryProvider)
                      .untag(widget.transactionId, tag.id),
                  deleteButtonTooltipMessage: 'Remove #${tag.name}',
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _input,
          maxLength: 41,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            prefixText: '#',
            hintText: 'Add a tag',
            border: const OutlineInputBorder(),
            counterText: '',
            suffixIcon: typed == null
                ? null
                : IconButton(
                    tooltip: 'Add tag',
                    icon: const Icon(Icons.add),
                    onPressed: () => _add(_input.text),
                  ),
          ),
          onSubmitted: _add,
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in suggestions)
                ActionChip(
                  label: Text('#${tag.name}'),
                  onPressed: () => ref
                      .read(tagsRepositoryProvider)
                      .tag(widget.transactionId, tag.id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Chips that filter Activity to one tag, with All first. Shows nothing
/// until a tag exists.
class TagFilterChips extends ConsumerWidget {
  const TagFilterChips({
    required this.selectedTagId,
    required this.onSelected,
    super.key,
  });

  final int? selectedTagId;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = [
      for (final u in ref.watch(tagUsageProvider).value ?? const <TagUse>[])
        if (u.count > 0) u.tag,
    ];
    if (tags.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All tags'),
            selected: selectedTagId == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final tag in tags) ...[
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text('#${tag.name}'),
              selected: selectedTagId == tag.id,
              onSelected: (selected) => onSelected(selected ? tag.id : null),
            ),
          ],
        ],
      ),
    );
  }
}
