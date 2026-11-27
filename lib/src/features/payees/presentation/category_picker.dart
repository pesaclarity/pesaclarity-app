import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/database/app_database.dart';
import '../../../data/repositories/categories_repository.dart';
import '../../../data/repositories/fuliza_tracking.dart';
import '../../../domain/categories/default_categories.dart';
import '../../../domain/categories/subcategories.dart';
import '../../../domain/export/export_tables.dart';
import '../../../domain/lending/loan_link.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/selector_field.dart';
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

/// Money lent or borrowed, or paying it back: the transaction is linked to
/// its loan in Lent and borrowed.
class LoanChoice extends CategoryChoice {
  const LoanChoice(this.link);

  final LoanLink link;
}

/// Opens the category list: the five most used first, then everything on
/// "Show all" or as the person types. Typing filters it, and a name that is
/// not there yet can be created on the spot. Returns null when dismissed.
///
/// With [payeeCategoryName] set, offers to follow the payee's category.
/// [allowType] limits the list, for example to income for money in.
/// [loanLinks] offers what a transaction can be in Lent and borrowed, with
/// [selectedLink] the one it is now.
Future<CategoryChoice?> pickCategory(
  BuildContext context, {
  int? selectedId,
  String? payeeName,
  String? payeeCategoryName,
  bool Function(CategoryType type)? allowType,
  List<LoanLink> loanLinks = const [],
  LoanLink? selectedLink,
  bool topLevelOnly = false,
}) => showAppSheet<CategoryChoice>(
  context: context,
  // Stays above the keyboard while the search box is in use.
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => CategoryPicker(
        controller: controller,
        selectedId: selectedId,
        payeeName: payeeName,
        payeeCategoryName: payeeCategoryName,
        allowType: allowType,
        loanLinks: loanLinks,
        selectedLink: selectedLink,
        topLevelOnly: topLevelOnly,
      ),
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
    this.loanLinks = const [],
    this.selectedLink,
    this.topLevelOnly = false,
    super.key,
  });

  /// Offers top-level categories only, as budgets take.
  final bool topLevelOnly;

  final ScrollController? controller;
  final int? selectedId;
  final String? payeeName;
  final String? payeeCategoryName;
  final bool Function(CategoryType type)? allowType;

  /// What the transaction can be in Lent and borrowed, shown above the
  /// categories; empty for none.
  final List<LoanLink> loanLinks;

  /// The one it is now; its loan's category then shows no tick of its own.
  final LoanLink? selectedLink;

  @override
  ConsumerState<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends ConsumerState<CategoryPicker> {
  final _query = TextEditingController();
  // Spending when it is allowed: most new categories are.
  late CategoryType _newType =
      (widget.allowType?.call(CategoryType.expense) ?? true)
      ? CategoryType.expense
      : CategoryType.values.firstWhere(
          (t) => widget.allowType?.call(t) ?? true,
          orElse: () => CategoryType.expense,
        );
  bool _creating = false;
  bool _showAll = false;

  /// Parents open to show their subcategories.
  final _open = <int>{};

  /// The parent whose "New subcategory" field is showing, if any.
  int? _addingUnder;
  final _subName = TextEditingController();
  bool _openedSelected = false;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    _subName.dispose();
    super.dispose();
  }

  Future<void> _create(String name, {Category? parent}) async {
    setState(() => _creating = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final id = await ref
          .read(categoriesRepositoryProvider)
          .create(
            name: name,
            type: parent?.type ?? _newType,
            parentId: parent?.id,
          );
      if (mounted) navigator.pop(ChosenCategory(id));
    } on CategoryNameTaken catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      messenger?.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Fuliza repayment only for people who use Fuliza and track it, or
    // when it is the one already chosen.
    final fuliza = ref.watch(fulizaTrackingProvider).value?.shown ?? false;
    final all = [
      for (final c in ref.watch(categoriesProvider).value ?? const <Category>[])
        if ((widget.allowType?.call(c.type) ?? true) &&
            (!widget.topLevelOnly || c.parentId == null) &&
            (fuliza ||
                c.key != fulizaRepaymentCategoryKey ||
                c.id == widget.selectedId))
          c,
    ];
    final rawUsage = ref.watch(categoryUsageProvider).value ?? const {};
    final query = _query.text.trim();
    final key = categoryNameKey(query);
    final byId = {for (final c in all) c.id: c};
    // Subcategories sit under their parent; one whose parent is not
    // offered here stands on its own.
    final children = <int, List<Category>>{};
    for (final c in all) {
      if (c.parentId case final p? when byId.containsKey(p)) {
        (children[p] ??= []).add(c);
      }
    }
    bool isTop(Category c) =>
        c.parentId == null || !byId.containsKey(c.parentId);
    String path(Category c) => categoryPath(
      c.name,
      parentName: isTop(c) ? null : byId[c.parentId]!.name,
    );
    final tops = [
      for (final c in all)
        if (isTop(c)) c,
    ];
    // Subcategories in the order they were made.
    for (final list in children.values) {
      list.sort((a, b) => a.id.compareTo(b.id));
    }
    // A parent's use counts its subcategories'.
    final usage = <int, int>{};
    for (final MapEntry(key: id, value: n) in rawUsage.entries) {
      final c = byId[id];
      if (c == null) continue;
      final top = isTop(c) ? id : c.parentId!;
      usage[top] = (usage[top] ?? 0) + n;
    }
    final selected = byId[widget.selectedId];
    final selectedTop = selected == null
        ? null
        : isTop(selected)
        ? selected.id
        : selected.parentId;
    if (!_openedSelected && selectedTop != null) {
      _openedSelected = true;
      if (children.containsKey(selectedTop)) _open.add(selectedTop);
    }
    // Searching lists every match flat, a subcategory by its full name:
    // "Uber" finds "Transport › Uber".
    final shown = [
      for (final c in all)
        if (key.isEmpty
            ? isTop(c)
            : categoryNameKey(c.name).contains(key) ||
                  categoryNameKey(path(c)).contains(key))
          c,
    ];
    final clean = cleanCategoryName(query);
    final canCreate =
        clean != null && !all.any((c) => categoryNameKey(c.name) == key);
    final types = [
      for (final t in CategoryType.values)
        if (widget.allowType?.call(t) ?? true) t,
    ];

    final groups = <CategoryType, List<Category>>{};
    for (final c in shown) {
      (groups[c.type] ??= []).add(c);
    }

    final mostUsed = key.isEmpty && !_showAll && tops.length > shortListLimit
        ? mostUsedCategories(tops, usage, selectedId: selectedTop)
        : null;

    final linked = widget.selectedLink;
    final accent = theme.colorScheme.primary;
    // The chosen one reads in the accent colour with a tick, no fill.
    Widget choice(
      Category c, {
      required String title,
      String? subtitle,
      double indent = 0,
    }) {
      final on = linked == null && c.id == widget.selectedId;
      return ListTile(
        key: Key(
          'category-${c.id}${indent > 0 && c.parentId == null ? '-only' : ''}',
        ),
        contentPadding: EdgeInsetsDirectional.only(start: 16 + indent, end: 16),
        title: Text(
          title,
          style: on
              ? TextStyle(color: accent, fontWeight: FontWeight.w600)
              : null,
        ),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: on ? Icon(Icons.check, color: accent) : null,
        onTap: () => Navigator.of(context).pop(ChosenCategory(c.id)),
      );
    }

    List<Widget> tile(Category c) {
      final subs = children[c.id];
      if (key.isNotEmpty) return [choice(c, title: path(c))];
      if (subs == null) return [choice(c, title: c.name)];
      final open = _open.contains(c.id);
      return [
        ListTile(
          key: Key('category-parent-${c.id}'),
          title: Text(c.name),
          subtitle: open
              ? Text('Pick one below, or keep it as ${c.name}')
              : null,
          trailing: Icon(open ? Icons.expand_less : Icons.expand_more),
          onTap: () =>
              setState(() => open ? _open.remove(c.id) : _open.add(c.id)),
        ),
        if (open) ...[
          choice(
            c,
            title: '${c.name} only',
            subtitle: 'No subcategory',
            indent: 32,
          ),
          for (final sub in subs) choice(sub, title: sub.name, indent: 32),
          if (_addingUnder == c.id)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(48, 0, 16, 8),
              child: TextField(
                key: const Key('new-subcategory-name'),
                controller: _subName,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'New subcategory of ${c.name}',
                ),
                onSubmitted: (v) {
                  final name = cleanCategoryName(v);
                  if (name != null && !_creating) _create(name, parent: c);
                },
              ),
            )
          else
            ListTile(
              key: Key('new-subcategory-${c.id}'),
              contentPadding: const EdgeInsetsDirectional.only(
                start: 48,
                end: 16,
              ),
              leading: const Icon(Icons.add),
              minLeadingWidth: 0,
              title: Text(
                'New subcategory of ${c.name}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () => setState(() {
                _subName.clear();
                _addingUnder = c.id;
              }),
            ),
        ],
      ];
    }

    final loans = [
      for (final link in widget.loanLinks)
        if (key.isEmpty || categoryNameKey(link.label).contains(key)) link,
    ];

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('Choose a category', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        TextField(
          controller: _query,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Find or add a category',
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
                  if (types.length > 2)
                    ChoiceMenu<CategoryType>(
                      key: const Key('new-category-type'),
                      name: 'Category type',
                      options: [
                        for (final t in types) (t, categoryTypeLabel(t)),
                      ],
                      value: _newType,
                      itemKey: (t) => Key('new-category-type-${t.name}'),
                      onChanged: (t) => setState(() => _newType = t),
                    )
                  else
                    AdaptiveSegmented<CategoryType>(
                      key: const Key('new-category-type'),
                      segments: [
                        for (final t in types) (t, categoryTypeLabel(t)),
                      ],
                      selected: _newType,
                      onChanged: (t) => setState(() => _newType = t),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _creating ? null : () => _create(clean),
                    child: const Text('Add a category'),
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
            trailing: widget.selectedId == null && linked == null
                ? const Icon(Icons.check)
                : null,
            onTap: () => Navigator.of(context).pop(const ChosenCategory(null)),
          ),
        ],
        if (loans.isNotEmpty) ...[
          const SectionLabel('Lent and borrowed'),
          for (final link in loans)
            ListTile(
              key: Key('category-loan-${link.name}'),
              title: Text(link.label),
              subtitle: Text(link.hint),
              trailing: link == linked ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(LoanChoice(link)),
            ),
        ],
        if (mostUsed != null) ...[
          const SectionLabel('Most used'),
          for (final c in mostUsed) ...tile(c),
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('category-show-all'),
            onPressed: () => setState(() => _showAll = true),
            icon: const Icon(Icons.expand_more),
            label: Text('Show all ${tops.length} categories'),
          ),
        ] else
          for (final type in CategoryType.values)
            if (groups[type] case final list?) ...[
              SectionLabel(categoryTypeLabel(type)),
              for (final c in list) ...tile(c),
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
    this.topLevelOnly = false,
    super.key,
  });

  /// See [CategoryPicker.topLevelOnly].
  final bool topLevelOnly;

  final int? selectedId;
  final ValueChanged<int?> onChanged;
  final String label;
  final String noneLabel;
  final bool Function(CategoryType type)? allowType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(categoriesProvider).value ?? const <Category>[];
    final chosen = all.where((c) => c.id == selectedId).firstOrNull;
    final parent = chosen?.parentId == null
        ? null
        : all.where((c) => c.id == chosen!.parentId).firstOrNull;
    return SelectorField(
      label: label,
      value: chosen == null
          ? noneLabel
          : categoryPath(chosen.name, parentName: parent?.name),
      detail: chosen != null && chosen.isDailySpending
          ? 'Counts toward safe to spend'
          : null,
      onTap: () async {
        final choice = await pickCategory(
          context,
          selectedId: selectedId,
          allowType: allowType,
          topLevelOnly: topLevelOnly,
        );
        if (choice case ChosenCategory(:final id)) onChanged(id);
      },
    );
  }
}
