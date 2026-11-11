import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/database_providers.dart';
import '../../../domain/spaces/business_setup.dart';
import '../../../domain/spaces/kept_data.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/business_day.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../../backup/application/backup_providers.dart';
import '../../close/application/business_day_providers.dart';
import '../../security/application/app_lock_controller.dart';
import '../application/business_setup_providers.dart';
import '../application/space_manager.dart';
import '../application/spaces_providers.dart';
import '../data/space_files.dart';
import 'spaces_sheet.dart';

const _pad = EdgeInsets.fromLTRB(
  Layout.gutter,
  8,
  Layout.gutter,
  Layout.screenBottom,
);

TextStyle _muted(BuildContext context) =>
    Theme.of(context).textTheme.bodyLarge!
        .copyWith(color: PesaColors.of(context).textMuted);

/// Profile › Spaces: every space, where the app opens, what is kept for 30
/// days, and deleting everything.
class SpacesScreen extends ConsumerStatefulWidget {
  const SpacesScreen({super.key});

  @override
  ConsumerState<SpacesScreen> createState() => _SpacesScreenState();
}

class _SpacesScreenState extends ConsumerState<SpacesScreen> {
  @override
  void initState() {
    super.initState();
    // What was kept past its 30 days goes now.
    Future.microtask(() => ref.read(spaceManagerProvider).purgeExpired());
  }

  @override
  Widget build(BuildContext context) {
    final spaces = ref.watch(spacesProvider).value ?? const [Space.personal];
    final activeId = ref.watch(activeSpaceIdProvider);
    final kept = ref.watch(keptDataProvider).value ?? const [];
    final colors = PesaColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spaces'),
        actions: [
          AddButton(
            tooltip: 'Add a space',
            onPressed: () => context.push(AppRoutes.addSpace),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: _pad,
        children: [
          Text(
            'Each space keeps its own records, locked on this phone. Nothing '
            'is shared between them.',
            style: _muted(context),
          ),
          const SizedBox(height: 16),
          GroupedSection(
            children: [
              for (final space in spaces)
                ListTile(
                  key: Key('spaces-${space.id}'),
                  leading: CircleAvatar(
                    backgroundColor: colors.border,
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    child: Text(space.initial),
                  ),
                  title: Text(space.name),
                  subtitle: Text(space.kind.label),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (space.id == activeId) const Tag('Open now'),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => context.push(AppRoutes.spaceSettings(space.id)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          GroupedSection(
            children: [
              ListTile(
                key: const Key('spaces-open-in'),
                title: const Text('Opens in'),
                subtitle: Text(
                  openChoiceLabel(ref.watch(openSpaceChoiceProvider), spaces),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showOpenSpaceChoice(context),
              ),
              ListTile(
                key: const Key('spaces-recently-deleted'),
                title: const Text('Recently deleted'),
                subtitle: const Text('Kept for 30 days, then gone'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (kept.isNotEmpty) Text('${kept.length}'),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => context.push(AppRoutes.recentlyDeleted),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GroupedSection(
            children: [
              ListTile(
                key: const Key('spaces-delete-all'),
                title: Text(
                  'Delete all my data',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                subtitle: const Text('Every space, and the app starts again'),
                onTap: () => context.push(AppRoutes.deleteAll),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One space's settings: name, kind, what it sells and the rest, then
/// Clear data and Delete space.
class SpaceSettingsScreen extends ConsumerWidget {
  const SpaceSettingsScreen({required this.spaceId, super.key});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = ref.watch(spacesProvider).value;
    final space = spaces?.where((s) => s.id == spaceId).firstOrNull;
    if (space == null) {
      return Scaffold(
        appBar: AppBar(),
        body: spaces == null
            ? const LoadingView()
            : const EmptyNote('This space is no longer on this phone.'),
      );
    }
    final open = ref.watch(activeSpaceIdProvider) == space.id;
    final business = space.kind == SpaceKind.business;
    final error = Theme.of(context).colorScheme.error;
    final setup = open && business
        ? ref.watch(businessSetupProvider).value
        : null;
    final day = open && business ? ref.watch(businessDayProvider).value : null;

    return Scaffold(
      appBar: AppBar(title: Text(space.name)),
      body: ListView(
        padding: _pad,
        children: [
          const SectionLabel('This space', padding: EdgeInsets.only(bottom: 8)),
          GroupedSection(
            children: [
              ListTile(
                key: const Key('space-name'),
                title: const Text('Name'),
                subtitle: Text(space.name),
                trailing: const TrailingLink('Edit'),
                onTap: () => _rename(context, ref, space),
              ),
              if (space.id != personalSpaceId)
                ListTile(
                  title: const Text('Kind'),
                  subtitle: const Text('What the space is for'),
                  trailing: ChoiceMenu<SpaceKind>(
                    key: const Key('space-kind'),
                    name: 'Kind',
                    options: [
                      for (final k in SpaceKind.values)
                        if (k != SpaceKind.personal) (k, k.label),
                    ],
                    value: space.kind,
                    itemKey: (k) => Key('space-kind-${k.name}'),
                    onChanged: (k) => _changeKind(context, ref, space, k),
                  ),
                ),
              if (setup != null)
                ListTile(
                  title: const Text('Sells'),
                  subtitle: const Text('Changes Home, Sell and Stock'),
                  trailing: ChoiceMenu<BusinessSells>(
                    key: const Key('space-sells'),
                    name: 'Sells',
                    options: [
                      for (final s in BusinessSells.values) (s, s.label),
                    ],
                    value: setup.sells ?? BusinessSells.products,
                    itemKey: (s) => Key('space-sells-${s.name}'),
                    onChanged: (s) =>
                        ref.read(businessSetupProvider.notifier).chooseSells(s),
                  ),
                ),
              if (open) ...[
                ListTile(
                  title: const Text('Accounts'),
                  subtitle: Text(
                    business
                        ? "Where each account's money goes"
                        : 'Whose messages are read',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    business
                        ? AppRoutes.businessOrPersonal
                        : AppRoutes.myAccounts,
                  ),
                ),
                ListTile(
                  title: const Text('Base currency'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.baseCurrency),
                ),
                if (day != null)
                  ListTile(
                    title: const Text('Day ends at'),
                    subtitle: const Text('For sales today and Close the day'),
                    trailing: ChoiceMenu<int>(
                      name: 'Day ends at',
                      options: [
                        for (final h in BusinessDay.choices)
                          (h, BusinessDay.labelFor(h)),
                      ],
                      value: day.endsAtHour,
                      onChanged: (h) => ref
                          .read(businessDayProvider.notifier)
                          .save(BusinessDay(endsAtHour: h)),
                    ),
                  ),
              ],
            ],
          ),
          if (open) ...[
            const SectionLabel('More'),
            GroupedSection(
              children: [
                if (business) ...[
                  ListTile(
                    title: const Text('Receipts and invoices'),
                    subtitle: const Text(
                      'Business details, numbering, how to pay',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.documentSettings),
                  ),
                  ListTile(
                    title: const Text('Tax'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.tax),
                  ),
                ],
                ListTile(
                  title: const Text('Backup'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.backup),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('space-open'),
              onPressed: () async {
                final router = GoRouter.of(context);
                await ref
                    .read(activeSpaceIdProvider.notifier)
                    .switchTo(space.id);
                router.go(AppRoutes.home);
              },
              child: const Text('Open this space for its other settings'),
            ),
          ],
          const SectionLabel('Data'),
          GroupedSection(
            children: [
              ListTile(
                key: const Key('space-clear'),
                title: const Text('Clear data'),
                subtitle: const Text('Keep the space and its settings'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.clearSpace(space.id)),
              ),
              if (space.id != personalSpaceId)
                ListTile(
                  key: const Key('space-delete'),
                  title: Text('Delete space', style: TextStyle(color: error)),
                  subtitle: const Text('The space and all its records'),
                  onTap: () => _delete(context, ref, space),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Space space) async {
    final controller = TextEditingController(text: space.name);
    final name = await showAppSheet<String>(
      context: context,
      builder: (context) => SheetBody(
        title: 'Name',
        children: [
          TextField(
            key: const Key('space-name-field'),
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('space-name-save'),
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null) {
      await ref.read(spacesProvider.notifier).rename(space.id, name);
    }
  }

  Future<void> _changeKind(
    BuildContext context,
    WidgetRef ref,
    Space space,
    SpaceKind kind,
  ) async {
    if (kind == space.kind) return;
    final change = kindChange(space.kind, kind);
    final yes = await showAppSheet<bool>(
      context: context,
      builder: (context) => SheetBody(
        title: 'Change ${space.name} to ${_article(kind)}?',
        children: [
          Text(
            '${space.name} becomes ${_article(kind)} space. Its records stay.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                if (change.comesIn.isNotEmpty)
                  ListTile(
                    title: const Text('Comes in'),
                    subtitle: Text(change.comesIn.join(', ')),
                  ),
                if (change.comesIn.isNotEmpty && change.goesAway.isNotEmpty)
                  const Divider(height: 1),
                if (change.goesAway.isNotEmpty)
                  ListTile(
                    title: const Text('Goes away'),
                    subtitle: Text(change.goesAway.join(', ')),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Only this space changes. You can change it back.',
            style: _muted(context),
          ),
          const SizedBox(height: 16),
          ButtonPair(
            primary: FilledButton(
              key: const Key('space-kind-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Change'),
            ),
            secondary: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Keep ${_article(space.kind)}'),
            ),
          ),
        ],
      ),
    );
    if (yes ?? false) {
      await ref.read(spaceManagerProvider).changeKind(space, kind);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Space space) async {
    final done = await showAppSheet<bool>(
      context: context,
      builder: (_) => _DeleteSpaceSheet(space),
    );
    if ((done ?? false) && context.mounted) {
      showNote(context, '${space.name} is deleted.');
      Navigator.of(context).pop();
    }
  }
}

String _article(SpaceKind kind) {
  final word = kind.label.toLowerCase();
  return '${'aeiou'.contains(word[0]) ? 'an' : 'a'} $word';
}

class _DeleteSpaceSheet extends ConsumerStatefulWidget {
  const _DeleteSpaceSheet(this.space);

  final Space space;

  @override
  ConsumerState<_DeleteSpaceSheet> createState() => _DeleteSpaceSheetState();
}

class _DeleteSpaceSheetState extends ConsumerState<_DeleteSpaceSheet> {
  var _keep = true;
  var _online = false;
  var _busy = false;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final space = widget.space;
    final typed = _name.text.trim().toLowerCase() == space.name.toLowerCase();
    return SheetBody(
      title: 'Delete ${space.name}?',
      children: [
        Text(
          'The space and every record in it leave this phone. Other spaces '
          'are untouched.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        _KeepOptions(
          keep: _keep,
          online: _online,
          onKeep: (v) => setState(() => _keep = v),
          onOnline: (v) => setState(() => _online = v),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('space-delete-name'),
          controller: _name,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Type ${space.name} to confirm',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('space-delete-confirm'),
          onPressed: !typed || _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final navigator = Navigator.of(context);
                  await ref
                      .read(spaceManagerProvider)
                      .delete(space, keep: _keep, deleteOnline: _online);
                  navigator.pop(true);
                },
          child: Text('Delete ${space.name}'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : () => _backUp(context, ref),
          child: const Text('Back up first'),
        ),
      ],
    );
  }
}

Future<void> _backUp(BuildContext context, WidgetRef ref) async {
  final settings = await ref.read(backupControllerProvider.future);
  if (!context.mounted) return;
  if (settings.enabled.isEmpty) {
    await context.push(AppRoutes.backup);
    return;
  }
  final report = await ref.read(backupControllerProvider.notifier).backUpNow();
  if (context.mounted) {
    showNote(
      context,
      report.failed.isEmpty ? 'Backed up.' : 'The backup did not finish.',
    );
  }
}

/// "Keep for 30 days" and "Also delete the online backup".
class _KeepOptions extends StatelessWidget {
  const _KeepOptions({
    required this.keep,
    required this.online,
    required this.onKeep,
    required this.onOnline,
  });

  final bool keep;
  final bool online;
  final ValueChanged<bool> onKeep;
  final ValueChanged<bool> onOnline;

  @override
  Widget build(BuildContext context) => GroupedSection(
    children: [
      SwitchListTile.adaptive(
        key: const Key('keep-30-days'),
        title: const Text('Keep for 30 days'),
        subtitle: const Text('Restore it from Recently deleted'),
        value: keep,
        onChanged: onKeep,
      ),
      SwitchListTile.adaptive(
        key: const Key('delete-online'),
        title: const Text('Also delete the online backup'),
        subtitle: const Text('In the vault and Google Drive'),
        value: online,
        onChanged: onOnline,
      ),
    ],
  );
}

/// Clears a space's records; the space and its settings stay.
class ClearSpaceScreen extends ConsumerStatefulWidget {
  const ClearSpaceScreen({required this.spaceId, super.key});

  final String spaceId;

  @override
  ConsumerState<ClearSpaceScreen> createState() => _ClearSpaceScreenState();
}

class _ClearSpaceScreenState extends ConsumerState<ClearSpaceScreen> {
  var _keep = true;
  var _online = false;
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final space = (ref.watch(spacesProvider).value ?? const [])
        .where((s) => s.id == widget.spaceId)
        .firstOrNull;
    if (space == null) {
      return Scaffold(appBar: AppBar(), body: const LoadingView());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Clear data')),
      body: ListView(
        padding: _pad,
        children: [
          Text(
            '${space.name} keeps its name, accounts, categories and '
            'settings. Its records go: transactions, sales, stock, people, '
            'plans and goals.',
            style: _muted(context),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('clear-back-up'),
            onPressed: _busy ? null : () => _backUp(context, ref),
            child: const Text('Back up first'),
          ),
          const SizedBox(height: 16),
          _KeepOptions(
            keep: _keep,
            online: _online,
            onKeep: (v) => setState(() => _keep = v),
            onOnline: (v) => setState(() => _online = v),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('clear-confirm'),
            onPressed: _busy
                ? null
                : () async {
                    final yes = await confirmDelete(
                      context,
                      title: 'Clear ${space.name}?',
                      body: _keep
                          ? 'You can restore it from Recently deleted for 30 '
                                'days.'
                          : 'Its records go for good.',
                      action: 'Clear',
                    );
                    if (!yes || !context.mounted) return;
                    setState(() => _busy = true);
                    await ref
                        .read(spaceManagerProvider)
                        .clear(space, keep: _keep, deleteOnline: _online);
                    if (!context.mounted) return;
                    showNote(context, '${space.name} is cleared.');
                    Navigator.of(context).pop();
                  },
            child: Text('Clear ${space.name}'),
          ),
        ],
      ),
    );
  }
}

/// What was cleared or deleted and kept for 30 days.
class RecentlyDeletedScreen extends ConsumerWidget {
  const RecentlyDeletedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kept = ref.watch(keptDataProvider);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final manager = ref.read(spaceManagerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recently deleted')),
      body: ListView(
        padding: _pad,
        children: [
          Text(
            'Kept on this phone, still locked. Each goes for good on its date.',
            style: _muted(context),
          ),
          const SizedBox(height: 16),
          switch (kept) {
            AsyncData(value: final list) when list.isEmpty => const EmptyNote(
              'Spaces you delete or clear, and choose to keep, show here.',
            ),
            AsyncData(value: final list) => GroupedSection(
              children: [
                for (final k in list)
                  ListTile(
                    key: Key('kept-${k.token}'),
                    title: Text(
                      k.kind == KeptKind.space
                          ? k.space.name
                          : '${k.space.name}: cleared records',
                    ),
                    subtitle: Text(
                      '${k.kind == KeptKind.space ? 'Space' : 'Cleared data'}'
                      ' · goes on ${dayHeading(CalendarDate.local(k.until), today: today)}',
                    ),
                    trailing: PillButton(
                      key: Key('kept-restore-${k.token}'),
                      label: 'Restore',
                      onPressed: () async {
                        final router = GoRouter.of(context);
                        await manager.restore(k);
                        router.go(AppRoutes.home);
                      },
                    ),
                  ),
              ],
            ),
            AsyncError() => ErrorView(
              'Recently deleted could not load.',
              onRetry: () => ref.invalidate(keptDataProvider),
            ),
            _ => const LoadingView(inList: true),
          },
          if (kept.value?.isNotEmpty ?? false) ...[
            const SizedBox(height: 16),
            GroupedSection(
              children: [
                ListTile(
                  key: const Key('kept-delete-now'),
                  title: Text(
                    'Delete these now',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  subtitle: const Text('They go for good today'),
                  onTap: () async {
                    final yes = await confirmDelete(
                      context,
                      title: 'Delete these for good?',
                      body: 'They cannot be restored afterwards.',
                    );
                    if (!yes) return;
                    for (final k in kept.value!) {
                      await manager.deleteNow(k);
                    }
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Deletes every space and everything the app keeps, after the app lock.
class DeleteAllScreen extends ConsumerStatefulWidget {
  const DeleteAllScreen({super.key});

  @override
  ConsumerState<DeleteAllScreen> createState() => _DeleteAllScreenState();
}

class _DeleteAllScreenState extends ConsumerState<DeleteAllScreen> {
  var _online = false;
  var _signIn = false;
  var _busy = false;
  final _check = TextEditingController();

  @override
  void dispose() {
    _check.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pinSet = ref.watch(appLockControllerProvider).settings.pinSet;
    final signedIn = ref.watch(authControllerProvider).value != null;
    final ready = pinSet
        ? _check.text.length >= 4
        : _check.text.trim().toLowerCase() == 'delete';
    return Scaffold(
      appBar: AppBar(title: const Text('Delete all my data')),
      body: ListView(
        padding: _pad,
        children: [
          const Notice(
            'Every space, backup setting and record on this phone goes. The '
            'app starts again from setup.',
            tone: Tone.warning,
            icon: Icons.warning_amber_outlined,
          ),
          const SectionLabel('Also'),
          GroupedSection(
            children: [
              SwitchListTile.adaptive(
                key: const Key('delete-all-online'),
                title: const Text('Delete my online backups'),
                subtitle: const Text(
                  "Every space's copy in the vault and Drive",
                ),
                value: _online,
                onChanged: (v) => setState(() => _online = v),
              ),
              if (signedIn)
                SwitchListTile.adaptive(
                  key: const Key('delete-all-sign-in'),
                  title: const Text('Delete my sign-in'),
                  subtitle: const Text('Your email and devices on the server'),
                  value: _signIn,
                  onChanged: (v) => setState(() => _signIn = v),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Notice(
            'Personal is not deleted on its own; this is how its data goes.',
            icon: Icons.lock_outline,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('delete-all-check'),
            controller: _check,
            obscureText: pinSet,
            keyboardType: pinSet ? TextInputType.number : TextInputType.text,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: pinSet
                  ? 'Your app lock PIN'
                  : 'Type DELETE to confirm',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('delete-all-confirm'),
            onPressed: !ready || _busy ? null : _deleteAll,
            child: const Text('Delete everything'),
          ),
          const SizedBox(height: 8),
          Text(
            'It deletes at once; nothing is kept for 30 days.',
            textAlign: TextAlign.center,
            style: _muted(context),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAll() async {
    if (ref.read(appLockControllerProvider).settings.pinSet) {
      final check = await ref
          .read(appLockControllerProvider.notifier)
          .enterPin(_check.text);
      if (check != PinCheck.correct) {
        if (mounted) showNote(context, 'That PIN is not right.');
        return;
      }
    }
    setState(() => _busy = true);
    await ref
        .read(spaceManagerProvider)
        .deleteEverything(deleteOnline: _online, deleteSignIn: _signIn);
    await ref.read(appRestarterProvider).restart();
  }
}
