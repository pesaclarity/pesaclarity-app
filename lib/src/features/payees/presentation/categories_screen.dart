import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/database/app_database.dart';
import '../../../data/repositories/categories_repository.dart';
import '../../../domain/categories/default_categories.dart';
import '../../../domain/export/export_tables.dart';
import '../../../domain/insights/category_breakdown.dart';
import '../../../domain/insights/spending_charts.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/pesa_colors.dart';
import '../../insights/application/insights_providers.dart';
import '../application/payee_providers.dart';

/// Profile › Categories: every top-level category by type, with how many
/// subcategories each has. Each opens [CategoryScreen].
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = PesaColors.of(context);
    final async = ref.watch(categoriesProvider);
    final appBar = AppBar(title: const Text('Categories'));
    final all = async.value;
    if (all == null) {
      return Scaffold(
        appBar: appBar,
        body: async.hasError
            ? ErrorView(
                'Categories could not load.',
                onRetry: () => ref.invalidate(categoriesProvider),
              )
            : const LoadingView(),
      );
    }
    final subs = <int, int>{};
    for (final c in all) {
      if (c.parentId case final p?) subs[p] = (subs[p] ?? 0) + 1;
    }
    return Scaffold(
      appBar: appBar,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            'Open a category to rename it or give it subcategories.',
            style: Theme.of(context).textTheme.bodyLarge!
                .copyWith(color: colors.textMuted),
          ),
          for (final type in CategoryType.values)
            if (all.any((c) => c.type == type && c.parentId == null)) ...[
              SectionLabel(categoryTypeLabel(type)),
              Card(
                child: Column(
                  children: [
                    for (final c in all)
                      if (c.type == type && c.parentId == null)
                        ListTile(
                          key: Key('categories-${c.id}'),
                          title: Text(c.name),
                          subtitle: switch (subs[c.id]) {
                            null => null,
                            1 => const Text('1 subcategory'),
                            final n => Text('$n subcategories'),
                          },
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go(AppRoutes.category(c.id)),
                        ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}

/// One category: its name, and its subcategories with what each held
/// this month, and a field to add another. A subcategory's own id opens
/// its parent.
class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({required this.categoryId, super.key});

  final int categoryId;

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  final _name = TextEditingController();
  final _field = FocusNode();
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _field.dispose();
    super.dispose();
  }

  Future<void> _add(Category parent) async {
    final name = cleanCategoryName(_name.text);
    if (name == null) return;
    setState(() => _adding = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(categoriesRepositoryProvider)
          .create(name: name, type: parent.type, parentId: parent.id);
      _name.clear();
    } on CategoryNameTaken catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final all = ref.watch(categoriesProvider).value;
    final asked = all?.where((c) => c.id == widget.categoryId).firstOrNull;
    final category = asked?.parentId == null
        ? asked
        : all!.where((c) => c.id == asked!.parentId).firstOrNull;
    if (all == null || category == null) {
      return Scaffold(
        appBar: AppBar(),
        body: all == null
            ? const LoadingView()
            : ErrorView(
                'This category is no longer here.',
                onRetry: () => ref.invalidate(categoriesProvider),
              ),
      );
    }
    final subs = [
      for (final c in all)
        if (c.parentId == category.id) c,
    ];
    final month = ref
        .watch(categoryBreakdownProvider((category.id, ChartPeriod.month)))
        .value;
    BreakdownRow? rowOf(int? sub) =>
        month?.rows.where((r) => r.subcategoryId == sub).firstOrNull;
    // In the order they were made.
    subs.sort((a, b) => a.id.compareTo(b.id));
    String thisMonth(BreakdownRow? row) => '${row?.count ?? 0} this month';
    final muted = theme.textTheme.bodyLarge!.copyWith(color: colors.textMuted);

    return Scaffold(
      appBar: AppBar(title: Text(category.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            [
              categoryTypeLabel(category.type),
              if (category.isDailySpending) 'Counts toward safe to spend',
            ].join(' · '),
            style: muted,
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Name'),
            subtitle: Text(category.name),
            trailing: IconButton(
              key: const Key('category-rename'),
              tooltip: 'Rename',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _rename(context, category),
            ),
          ),
          SectionLabel(
            'Subcategories',
            trailing: Text(
              'Optional',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text(category.name),
                  subtitle: Text('No subcategory · ${thisMonth(rowOf(null))}'),
                ),
                if (subs.isNotEmpty) const Divider(height: 1),
                for (final sub in subs)
                  ListTile(
                    key: Key('subcategory-${sub.id}'),
                    contentPadding: const EdgeInsetsDirectional.only(
                      start: 40,
                      end: 16,
                    ),
                    title: Text(sub.name),
                    subtitle: Text(
                      [
                        thisMonth(rowOf(sub.id)),
                        if (rowOf(sub.id) case final row?)
                          shownMoney(
                            context,
                            row.amountMinor,
                            withCurrency: true,
                          ),
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _subcategory(context, category, sub),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('add-subcategory'),
              onPressed: _field.requestFocus,
              icon: const Icon(Icons.add),
              label: const Text('Add subcategory'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Subcategories are yours to make. A transaction with none '
            'stays plain ${category.name}, and every subcategory still '
            'adds up into ${category.name} in Insights, budgets and Ask.',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: colors.textMuted,
            ),
          ),
          const SectionLabel('Add subcategory'),
          TextField(
            key: const Key('subcategory-name'),
            controller: _name,
            focusNode: _field,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'For example Boda boda',
            ),
            onSubmitted: (_) => _add(category),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('add-to-category'),
            onPressed: _adding ? null : () => _add(category),
            child: Text('Add to ${category.name}'),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, Category category) async {
    final controller = TextEditingController(text: category.name);
    final name = await showAdaptiveDialog<String>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text('Rename'),
        content: Material(
          type: MaterialType.transparency,
          child: TextField(
            key: const Key('category-new-name'),
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ),
        actions: [
          DialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          DialogAction(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || cleanCategoryName(name) == null) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(categoriesRepositoryProvider).rename(category.id, name);
    } on CategoryNameTaken catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _subcategory(
    BuildContext context,
    Category parent,
    Category sub,
  ) async {
    final action = await showAppSheet<String>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              sub.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () => Navigator.of(context).pop('rename'),
          ),
          ListTile(
            key: const Key('subcategory-delete'),
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete'),
            subtitle: Text('Its transactions go back to ${parent.name}'),
            onTap: () => Navigator.of(context).pop('delete'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'rename':
        await _rename(context, sub);
      case 'delete':
        final yes = await confirmDelete(
          context,
          title: 'Delete ${sub.name}?',
          body:
              'Its transactions, payees and plans move to ${parent.name}, '
              'and still count there.',
        );
        if (yes) {
          await ref
              .read(categoriesRepositoryProvider)
              .deleteSubcategory(sub.id);
        }
    }
  }
}
