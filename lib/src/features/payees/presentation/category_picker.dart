import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/repositories/categories_repository.dart';
import '../../../domain/categories/default_categories.dart';
import '../../../domain/export/export_tables.dart';
import '../../../shared/widgets/selector_field.dart';
import '../../../theme/pesa_colors.dart';
import '../application/payee_providers.dart';

/// What the person picked in [pickCategory].
sealed class CategoryChoice {
  const CategoryChoice();
}

/// A category, or Uncategorised when [id] is null.
class ChosenCategory extends CategoryChoice {
  const ChosenCategory(this.id);

  final int? id;
}

/// Drop the transaction's own category and follow the payee's.
class FollowPayeeCategory extends CategoryChoice {
  const FollowPayeeCategory();
}

/// Opens the category list: the five most used first, then everything on
/// "Show all" or as the person types. Typing filters it, and a name that is
/// not there yet can be created on the spot. Returns null when dismissed.
///
/// With [payeeCategoryName] set, offers to follow the payee's category.
/// [allowType] limits the list, for example to income for money in.
Future<CategoryChoice?> pickCategory(
  BuildContext context, {
  int? selectedId,
  String? payeeName,
  String? payeeCategoryName,
  bool Function(CategoryType type)? allowType,
}) => showModalBottomSheet<CategoryChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.75,
    maxChildSize: 0.95,
    builder: (context, controller) => CategoryPicker(
      controller: controller,
      selectedId: selectedId,
      payeeName: payeeName,
      payeeCategoryName: payeeCategoryName,
      allowType: allowType,
    ),
  ),
);

/// How many most-used categories the picker shows before "Show all".
const mostUsedCount = 5;

/// The [count] categories to show first: the most used, ties in list order;
/// without enough use, day-to-day ones fill the rest. [selectedId] is always
/// among them.
List<Category> mostUsedCategories(
  List<Category> categories,
  Map<int, int> usage, {
  int? selectedId,
  int count = mostUsedCount,
}) {
  final order = {for (final (i, c) in categories.indexed) c.id: i};
  int rank(Category c) => (usage[c.id] ?? 0) * 2 + (c.isDailySpending ? 1 : 0);
  final ranked = [...categories]
    ..sort((a, b) {
      final byRank = rank(b).compareTo(rank(a));
      return byRank != 0 ? byRank : order[a.id]!.compareTo(order[b.id]!);
    });
  final top = ranked.take(count).toList();
  if (selectedId != null && !top.any((c) => c.id == selectedId)) {
    final selected = categories.where((c) => c.id == selectedId);
    if (selected.isNotEmpty) top.insert(0, selected.first);
  }
  return top;
}

class CategoryPicker extends ConsumerStatefulWidget {
  const CategoryPicker({
    this.controller,
    this.selectedId,
    this.payeeName,
    this.payeeCategoryName,
    this.allowType,
    super.key,
  });

  final ScrollController? controller;
  final int? selectedId;
  final String? payeeName;
  final String? payeeCategoryName;
  final bool Function(CategoryType type)? allowType;

  @override
  ConsumerState<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends ConsumerState<CategoryPicker> {
  final _query = TextEditingController();
  late CategoryType _newType = CategoryType.values.firstWhere(
    (t) => widget.allowType?.call(t) ?? true,
    orElse: () => CategoryType.expense,
  );
  bool _creating = false;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _create(String name) async {
    setState(() => _creating = true);
    final navigator = Navigator.of(context);
    final id = await ref
        .read(categoriesRepositoryProvider)
        .create(name: name, type: _newType);
    if (mounted) navigator.pop(ChosenCategory(id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final all = [
      for (final c in ref.watch(categoriesProvider).value ?? const <Category>[])
        if (widget.allowType?.call(c.type) ?? true) c,
    ];
    final usage = ref.watch(categoryUsageProvider).value ?? const {};
    final query = _query.text.trim();
    final key = categoryNameKey(query);
    final shown = [
      for (final c in all)
        if (key.isEmpty || categoryNameKey(c.name).contains(key)) c,
    ];
    final clean = cleanCategoryName(query);
    final canCreate =
        clean != null && !all.any((c) => categoryNameKey(c.name) == key);

    final groups = <CategoryType, List<Category>>{};
    for (final c in shown) {
      (groups[c.type] ??= []).add(c);
    }

    final mostUsed = key.isEmpty && !_showAll && all.length > shortListLimit
        ? mostUsedCategories(all, usage, selectedId: widget.selectedId)
        : null;

    Widget tile(Category c) => ListTile(
      title: Text(c.name),
      trailing: c.id == widget.selectedId
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      onTap: () => Navigator.of(context).pop(ChosenCategory(c.id)),
    );

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('Choose a category', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _query,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Find or add a category',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            if (canCreate) _create(clean);
          },
        ),
        if (canCreate) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'New category: $clean',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in CategoryType.values)
                        if (widget.allowType?.call(type) ?? true)
                          ChoiceChip(
                            label: Text(categoryTypeLabel(type)),
                            selected: _newType == type,
                            onSelected: (_) => setState(() => _newType = type),
                          ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _creating ? null : () => _create(clean),
                    child: const Text('Add category'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (key.isEmpty) ...[
          if (widget.payeeCategoryName != null)
            ListTile(
              title: Text('Same as ${widget.payeeName ?? 'the payee'}'),
              subtitle: Text(widget.payeeCategoryName!),
              onTap: () =>
                  Navigator.of(context).pop(const FollowPayeeCategory()),
            ),
          ListTile(
            title: const Text(uncategorisedName),
            subtitle: const Text('Still counts in your totals'),
            trailing: widget.selectedId == null
                ? Icon(Icons.check, color: theme.colorScheme.primary)
                : null,
            onTap: () => Navigator.of(context).pop(const ChosenCategory(null)),
          ),
        ],
        if (mostUsed != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text(
              'MOST USED',
              style: theme.textTheme.labelMedium!.copyWith(
                color: colors.textMuted,
                letterSpacing: 1,
              ),
            ),
          ),
          for (final c in mostUsed) tile(c),
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('category-show-all'),
            onPressed: () => setState(() => _showAll = true),
            icon: const Icon(Icons.expand_more),
            label: Text('Show all ${all.length} categories'),
          ),
        ] else
          for (final type in CategoryType.values)
            if (groups[type] case final list?) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 4),
                child: Text(
                  categoryTypeLabel(type).toUpperCase(),
                  style: theme.textTheme.labelMedium!.copyWith(
                    color: colors.textMuted,
                    letterSpacing: 1,
                  ),
                ),
              ),
              for (final c in list) tile(c),
            ],
      ],
    );
  }
}

/// A form field for a category: shows the chosen one and opens
/// [pickCategory] when tapped. [noneLabel] names the empty choice.
class CategorySelectorField extends ConsumerWidget {
  const CategorySelectorField({
    required this.selectedId,
    required this.onChanged,
    this.label = 'Category',
    this.noneLabel = 'Choose later',
    this.allowType,
    super.key,
  });

  final int? selectedId;
  final ValueChanged<int?> onChanged;
  final String label;
  final String noneLabel;
  final bool Function(CategoryType type)? allowType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(categoriesProvider).value ?? const <Category>[];
    final chosen = all.where((c) => c.id == selectedId).firstOrNull;
    return SelectorField(
      label: label,
      value: chosen?.name ?? noneLabel,
      detail: chosen != null && chosen.isDailySpending
          ? 'Counts toward safe to spend'
          : null,
      onTap: () async {
        final choice = await pickCategory(
          context,
          selectedId: selectedId,
          allowType: allowType,
        );
        if (choice case ChosenCategory(:final id)) onChanged(id);
      },
    );
  }
}
