import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/clock.dart';
import '../../../domain/sharing/share_model.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/value_tile.dart';
import '../../../theme/pesa_colors.dart';
import '../application/group_sync_controller.dart';
import '../application/share_providers.dart';

/// The note under the members when sync is on.
const syncPrivacyNote =
    'Changes are sealed on your phone. Our server passes them on and '
    'cannot open them.';

/// "2 min ago", "3 h ago", else the day.
String syncedAgo(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 12) return '${d.inHours} h ago';
  final day = CalendarDate.local(at);
  return '${weekdayName(day).substring(0, 3)} ${shortDate(day)}';
}

String _changes(int n, String tail) => '$n change${n == 1 ? '' : 's'} $tail';

/// Why sync stopped, in plain words.
String syncProblemReason(String? code) => switch (code) {
  'unauthorized' ||
  'replay' ||
  'signature' => 'the server could not check this phone',
  'clock' => "this phone's clock looks wrong",
  'not_member' => 'this phone is no longer in the space on the server',
  'not_owner' => 'only the owner can do that',
  'too_large' => 'an update was too big to send',
  'space_full' => 'the space has as many members as it can hold',
  'not_found' => 'the server no longer has this space',
  final c? when c.startsWith('licence') => 'Premium could not be checked',
  final c? when c.startsWith('http_5') || c == 'server_error' =>
    'the server had a problem',
  _ => 'something went wrong',
};

/// The "Sync automatically" row at the top of Share this space, with its
/// status. Only the owner has the switch; members see the status only.
class GroupSyncCard extends ConsumerWidget {
  const GroupSyncCard({required this.space, super.key});

  final Space space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(groupSyncProvider).value;
    if (view == null || view.phase == GroupSyncPhase.hidden) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final now = ref.watch(clockProvider)();
    final error = view.phase == GroupSyncPhase.error;
    final status = _status(view, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupedSection(
          children: [
            MergeSemantics(
              // The switch moves under the status at larger text.
              child: ValueTile(
                key: const Key('sync-row'),
                leading: Icon(error ? Icons.sync_problem : Icons.sync),
                title: const Text('Sync automatically'),
                subtitle: error
                    ? Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  'Sync stopped: '
                                  '${syncProblemReason(view.problem)}.',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                            const TextSpan(text: ' Your data is safe here.'),
                          ],
                        ),
                      )
                    : Text(status),
                trailing: view.owner
                    ? Switch(
                        key: const Key('sync-switch'),
                        value: view.on,
                        onChanged: view.phase == GroupSyncPhase.syncing
                            ? null
                            : (on) => on
                                  ? _turnOn(context, ref)
                                  : ref
                                        .read(groupSyncProvider.notifier)
                                        .turnOff(),
                      )
                    : Text(
                        view.on ? 'On' : 'Off',
                        key: const Key('sync-member-status'),
                        style: theme.textTheme.labelLarge,
                      ),
              ),
            ),
            if (error)
              ListTile(
                key: const Key('sync-try-again'),
                title: const Text('Try again'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ref.read(groupSyncProvider.notifier).sync(),
              ),
          ],
        ),
        if (view.phase == GroupSyncPhase.receivingOnly) ...[
          const SizedBox(height: 8),
          Text(
            view.owner
                ? 'Your Premium has ended. You still get the others\' '
                      'changes. Yours are kept on this phone and go once it '
                      'is renewed, or send them as an update file.'
                : "${view.ownerName ?? 'The owner'}'s Premium has ended. "
                      "You still get the others' changes. Yours are kept on "
                      'this phone and go once it is renewed, or send them as '
                      'an update file.',
            key: const Key('sync-readonly-note'),
            style: theme.textTheme.bodyMedium!.copyWith(
              color: colors.textMuted,
            ),
          ),
        ],
      ],
    );
  }

  String _status(GroupSyncView v, DateTime now) {
    final ago = v.lastSyncAt == null ? null : syncedAgo(v.lastSyncAt!, now);
    return switch (v.phase) {
      GroupSyncPhase.off =>
        v.owner ? 'Off' : 'Off · only the owner can turn it on',
      GroupSyncPhase.waitingToBeAdded =>
        "Waiting for ${v.ownerName ?? 'the owner'}'s phone to add you",
      GroupSyncPhase.syncing => 'Syncing…',
      GroupSyncPhase.upToDate =>
        ago == null ? 'Up to date' : 'Up to date · $ago',
      GroupSyncPhase.offline =>
        v.toSend == 0
            ? 'Waiting for a connection'
            : 'Waiting for a connection · ${_changes(v.toSend, 'to send')}',
      GroupSyncPhase.receivingOnly =>
        v.toSend == 0
            ? 'Receiving only'
            : 'Receiving only · ${_changes(v.toSend, 'waiting to send')}',
      GroupSyncPhase.error || GroupSyncPhase.hidden => '',
    };
  }

  Future<void> _turnOn(BuildContext context, WidgetRef ref) async {
    final go = await showAppSheet<bool>(
      context: context,
      builder: (_) => TurnOnSyncSheet(space: space),
    );
    if (go != true || !context.mounted) return;
    final result = await ref.read(groupSyncProvider.notifier).turnOn();
    if (!context.mounted) return;
    switch (result) {
      case TurnOnResult.needsPremium:
        final o = ref.read(shareOverviewProvider).value;
        await showAppSheet<void>(
          context: context,
          builder: (_) => SyncNeedsPremiumSheet(
            others: [
              for (final m in o?.others ?? const <ShareMember>[])
                m.name.split(' ').first,
            ],
          ),
        );
      case TurnOnResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync is not available yet.')),
        );
      case TurnOnResult.on:
        break;
    }
  }
}

/// 14b: what turning sync on means.
class TurnOnSyncSheet extends StatelessWidget {
  const TurnOnSyncSheet({required this.space, super.key});

  final Space space;

  @override
  Widget build(BuildContext context) => SheetBody(
    title: 'Sync automatically',
    subtitle: '${space.name} · ${space.kind.label}',
    children: [
      const GroupedSection(
        children: [
          ListTile(
            title: Text('Changes go by themselves'),
            subtitle: Text(
              'When anyone adds or changes something, the others get it '
              'next time their app is open.',
            ),
          ),
          ListTile(
            title: Text('Sealed on your phone'),
            subtitle: Text(
              'Our server passes changes on. It cannot read amounts, names '
              'or notes.',
            ),
          ),
          ListTile(
            title: Text('Members join free'),
            subtitle: Text('Only you, the owner, need Premium.'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('sync-turn-on'),
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('Turn on sync'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Not now'),
      ),
    ],
  );
}

/// 14e: the owner turned sync on without Premium.
class SyncNeedsPremiumSheet extends ConsumerWidget {
  const SyncNeedsPremiumSheet({super.key, this.others = const []});

  /// First names of the other members, for "Jane and Brian sync free".
  final List<String> others;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final who = switch (others.length) {
      0 => 'Members',
      1 => others.single,
      _ =>
        '${others.sublist(0, others.length - 1).join(', ')} and '
            '${others.last}',
    };
    return SheetBody(
      title: 'Sync needs Premium',
      subtitle: 'For the owner of the space only',
      children: [
        Text(
          'Sync automatically is part of Premium. $who sync free once you '
          'have it. Update files stay free.',
          style: theme.textTheme.bodyLarge!.copyWith(
            color: PesaColors.of(context).textMuted,
          ),
        ),
        const SizedBox(height: 12),
        GroupedSection(
          children: [
            ListTile(
              title: const Text('Premium'),
              subtitle: const Text('A year at a time · works offline'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _premium(context),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('sync-see-premium'),
          onPressed: () => _premium(context),
          child: const Text('See Premium'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep using update files'),
        ),
      ],
    );
  }

  void _premium(BuildContext context) {
    // No Premium screen yet (licences, decision 0032, are not issued).
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Premium is not available yet.')),
    );
  }
}

/// Pull to sync on a shared space's screens, when sync is shown; else
/// just [child].
class GroupSyncRefresh extends ConsumerWidget {
  const GroupSyncRefresh({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(groupSyncProvider).value;
    if (view == null || view.phase == GroupSyncPhase.hidden) return child;
    return RefreshIndicator(
      onRefresh: () => ref.read(groupSyncProvider.notifier).sync(),
      child: child,
    );
  }
}
