import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/share_repository.dart';
import '../../../domain/sharing/share_model.dart';
import '../../../domain/sharing/share_rules.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../shared/widgets/value_tile.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../accounts/presentation/mpesa_lines_screen.dart' show LinePick;
import '../../spaces/application/spaces_providers.dart';
import '../application/share_providers.dart';

const _pad = EdgeInsets.fromLTRB(
  Layout.gutter,
  0,
  Layout.gutter,
  Layout.screenBottom,
);

TextStyle _muted(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: PesaColors.of(context).textMuted);

String _day(DateTime at) {
  final d = CalendarDate.local(at);
  return '${weekdayName(d).substring(0, 3)} ${shortDate(d)}';
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _names(List<String> names) => switch (names.length) {
  0 => '',
  1 => names.single,
  _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
};

/// "3 changes to approve", at the top of Share this space for an
/// approver. Nothing when none wait.
class ApprovalsCard extends ConsumerWidget {
  const ApprovalsCard({required this.spaceId, super.key});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asks = ref.watch(toApproveProvider).value ?? const [];
    if (asks.isEmpty) return const SizedBox.shrink();
    final overview = ref.watch(shareOverviewProvider).value;
    final from = <String>{
      for (final w in asks)
        if (w.fromMember != null)
          _cap(overview?.nameOf(w.fromMember!) ?? 'someone'),
    }.toList();
    final n = asks.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GroupedSection(
        children: [
          ListTile(
            key: const Key('share-approvals'),
            leading: const Icon(Icons.task_alt),
            title: Text('$n change${n == 1 ? '' : 's'} to approve'),
            subtitle: Text(
              [
                if (from.isNotEmpty) 'From ${_names(from)}',
                'since ${_day(asks.first.at)}',
              ].join(' · '),
            ),
            onTap: () => context.push(AppRoutes.shareApprovals(spaceId)),
          ),
        ],
      ),
    );
  }
}

/// A one-line summary of the rules, under "Who can change what", in the
/// mockup's words: for Household defaults "Changes by others to the plan
/// are free; deletions need approval". Accounts are named only when their
/// level differs from the plan's.
String policySummary(SharePolicy p) {
  String verb(ChangeLevel l) => switch (l) {
    ChangeLevel.anyone => 'are free',
    ChangeLevel.approval => 'need approval',
    ChangeLevel.restricted =>
      'are ${p.kind == SpaceKind.savingsGroup ? 'Owner and Treasurer only' : 'Owner only'}',
  };
  final plan = p.level(RuleArea.plan);
  final accounts = p.level(RuleArea.accounts);
  final others = p.level(RuleArea.others);
  if (plan == accounts && plan == others) {
    return 'Changes by others ${verb(plan)}';
  }
  return [
    'Changes by others to the plan ${verb(plan)}',
    if (accounts != plan) 'accounts ${verb(accounts)}',
    'deletions ${verb(others)}',
  ].join('; ');
}

/// "Who can change what", under the members on Share this space.
class RulesRow extends ConsumerWidget {
  const RulesRow({required this.spaceId, super.key});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(sharePolicyProvider).value;
    return GroupedSection(
      children: [
        ListTile(
          key: const Key('share-rules'),
          leading: const Icon(Icons.tune),
          title: const Text('Who can change what'),
          subtitle: policy == null ? null : Text(policySummary(policy)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(AppRoutes.shareRules(spaceId)),
        ),
      ],
    );
  }
}

/// Who can change what: a level for each kind of change, and who can
/// approve. Only the Owner changes them; everyone else sees them.
class ShareRulesScreen extends ConsumerWidget {
  const ShareRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = ref.watch(activeSpaceProvider);
    final loaded = ref.watch(sharePolicyProvider);
    final overview = ref.watch(shareOverviewProvider).value;
    final owner = (overview?.myRole ?? ShareRole.owner) == ShareRole.owner;
    final chama = space.kind == SpaceKind.savingsGroup;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Who can change what')),
      body: switch (loaded) {
        AsyncData(value: final policy) => ListView(
          padding: _pad,
          children: [
            Text(
              "For changes made by other members. The Owner's own changes "
              'never wait. Everyone can always add transactions and edit '
              'their own.',
              style: _muted(context),
            ),
            SectionLabel('${space.name} · ${space.kind.label}'),
            GroupedSection(
              children: [
                for (final a in RuleArea.values)
                  _LevelRow(
                    key: Key('rules-${a.name}'),
                    title: a.title,
                    hint: a.hint,
                    value: policy.level(a).label(space.kind),
                    onTap: owner
                        ? () => showAppSheet<void>(
                            context: context,
                            builder: (_) => LevelSheet(area: a, policy: policy),
                          )
                        : null,
                  ),
                const _LevelRow(
                  title: 'Adding members',
                  hint: 'Add someone or change a role',
                  value: 'Owner only',
                ),
              ],
            ),
            if (chama) ...[
              const SizedBox(height: 12),
              GroupedSection(
                children: [
                  SwitchListTile.adaptive(
                    key: const Key('rules-contributions'),
                    title: const Text('Contributions need approval'),
                    subtitle: const Text(
                      'Money in added by a member waits until an approver '
                      'says yes',
                    ),
                    value: policy.contributions,
                    onChanged: owner
                        ? (on) => _save(
                            ref,
                            SharePolicy(
                              policy.kind,
                              policy.levels,
                              contributions: on,
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ],
            SectionLabel(
              'Who can approve',
              trailing: chama
                  ? Text(
                      '${_approvers(overview, policy).length} people',
                      style: theme.textTheme.labelLarge!.copyWith(
                        color: PesaColors.of(context).textMuted,
                      ),
                    )
                  : null,
            ),
            GroupedSection(
              children: [
                for (final m in overview?.members ?? const <ShareMember>[])
                  if (m.role != ShareRole.viewer)
                    _ApproverRow(
                      member: m,
                      me: m.id == overview?.myId,
                      policy: policy,
                      owner: owner,
                    ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Kept on every phone and checked when an update is opened, '
              'like roles.',
              style: theme.textTheme.bodySmall!.copyWith(
                color: PesaColors.of(context).textMuted,
              ),
            ),
          ],
        ),
        AsyncError() => const EmptyNote("These rules can't be read."),
        _ => const LoadingView(),
      },
    );
  }

  static List<ShareMember> _approvers(ShareOverview? o, SharePolicy p) => [
    for (final m in o?.members ?? const <ShareMember>[])
      if (p.canApprove(m.role, marked: m.approver)) m,
  ];

  static Future<void> _save(WidgetRef ref, SharePolicy p) async {
    await ref.read(shareRepositoryProvider)!.setPolicy(p);
    ref
      ..invalidate(sharePolicyProvider)
      ..invalidate(toApproveProvider);
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.title,
    required this.hint,
    required this.value,
    this.onTap,
    super.key,
  });

  final String title;
  final String hint;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ValueTile(
    title: Text(title),
    subtitle: Text(hint),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: Theme.of(context).textTheme.labelMedium),
        if (onTap != null) const Icon(Icons.chevron_right),
      ],
    ),
    onTap: onTap,
  );
}

class _ApproverRow extends ConsumerWidget {
  const _ApproverRow({
    required this.member,
    required this.me,
    required this.policy,
    required this.owner,
  });

  final ShareMember member;
  final bool me;
  final SharePolicy policy;
  final bool owner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = me ? 'You' : member.name;
    if (policy.trusted(member.role)) {
      return ListTile(
        title: Text(name),
        subtitle: Text('${member.role.label}, always'),
      );
    }
    return SwitchListTile.adaptive(
      key: Key('rules-approver-${member.name}'),
      title: Text(name),
      subtitle: Text(member.role.label),
      value: member.approver,
      onChanged: owner
          ? (on) async {
              await ref
                  .read(shareRepositoryProvider)!
                  .setApprover(member.id, approver: on);
              ref
                ..invalidate(shareOverviewProvider)
                ..invalidate(toApproveProvider);
            }
          : null,
    );
  }
}

/// One rule's level: Anyone, Needs approval, or Owner (and Treasurer)
/// only; the chosen one in red text with a check.
class LevelSheet extends ConsumerStatefulWidget {
  const LevelSheet({required this.area, required this.policy, super.key});

  final RuleArea area;
  final SharePolicy policy;

  @override
  ConsumerState<LevelSheet> createState() => _LevelSheetState();
}

class _LevelSheetState extends ConsumerState<LevelSheet> {
  late var _level = widget.policy.level(widget.area);

  @override
  Widget build(BuildContext context) {
    final space = ref.watch(activeSpaceProvider);
    final overview = ref.watch(shareOverviewProvider).value;
    return SheetBody(
      title: widget.area.title,
      subtitle:
          '${space.name} · ${overview?.count ?? 1} of '
          '${memberLimit(space.kind)} members',
      children: [
        GroupedSection(
          children: [
            for (final l in ChangeLevel.values)
              LinePick(
                key: Key('rules-level-${l.name}'),
                title: l.label(space.kind),
                hint: l.hint(space.kind),
                chosen: _level == l,
                onTap: () => setState(() => _level = l),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('rules-level-save'),
          onPressed: () async {
            final p = widget.policy;
            await ShareRulesScreen._save(
              ref,
              SharePolicy(p.kind, {
                ...p.levels,
                widget.area: _level,
              }, contributions: p.contributions),
            );
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Changes to approve: each in words, who added the record, then Approve
/// or Decline. Grouped by the file it came in.
class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(toApproveProvider);
    final overview = ref.watch(shareOverviewProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Changes to approve')),
      body: switch (loaded) {
        AsyncData(:final value) when value.isEmpty => const EmptyNote(
          'Nothing waits for your approval.',
        ),
        AsyncData(:final value) => ListView(
          padding: _pad,
          children: [
            Text(
              '${value.length} change${value.length == 1 ? '' : 's'} to '
              'approve. Until then they show as waiting, and totals leave '
              'them out.',
              style: _muted(context),
            ),
            for (final MapEntry(key: label, value: group) in _groups(
              value,
              overview,
            ).entries) ...[
              SectionLabel(label),
              GroupedSection(
                children: [for (final w in group) _AskRow(change: w)],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Your answer goes in your next update file. A declined change '
              'stays in Space history.',
              style: Theme.of(context).textTheme.bodySmall!
                  .copyWith(color: PesaColors.of(context).textMuted),
            ),
          ],
        ),
        AsyncError() => const EmptyNote("These changes can't be read."),
        _ => const LoadingView(),
      },
    );
  }

  static Map<String, List<WaitingChange>> _groups(
    List<WaitingChange> all,
    ShareOverview? o,
  ) {
    final out = <String, List<WaitingChange>>{};
    for (final w in all.reversed) {
      final from = w.fromMember == null
          ? 'on this phone'
          : "from ${_cap(o?.nameOf(w.fromMember!) ?? 'someone')}'s file";
      out.putIfAbsent('${_day(w.at)} · $from', () => []).add(w);
    }
    return out;
  }
}

class _AskRow extends ConsumerStatefulWidget {
  const _AskRow({required this.change});

  final WaitingChange change;

  @override
  ConsumerState<_AskRow> createState() => _AskRowState();
}

class _AskRowState extends ConsumerState<_AskRow> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final w = widget.change;
    // At large text the two buttons go one under the other.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.6;
    final approve = FilledButton(
      key: Key('approve-${w.id}'),
      onPressed: _busy ? null : () => _answer(yes: true),
      child: const Text('Approve'),
    );
    final decline = OutlinedButton(
      key: Key('decline-${w.id}'),
      onPressed: _busy ? null : () => _answer(yes: false),
      child: const Text('Decline'),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(w.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(w.detail, style: _muted(context)),
          const SizedBox(height: 10),
          if (stacked) ...[
            approve,
            const SizedBox(height: 8),
            decline,
          ] else
            Row(
              children: [
                Expanded(child: approve),
                const SizedBox(width: 8),
                Expanded(child: decline),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _answer({required bool yes}) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(shareRepositoryProvider)!
          .answer(widget.change.id, yes: yes);
    } on StateError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("This change can't be answered now.")),
        );
      }
    }
    ref.invalidate(toApproveProvider);
    if (mounted) setState(() => _busy = false);
  }
}
