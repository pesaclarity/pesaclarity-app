import 'dart:convert';
import 'dart:io';

import 'package:barcode/barcode.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/share/share_codec.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/share_repository.dart';
import '../../../domain/sharing/safety_words.dart';
import '../../../domain/sharing/share_merge.dart';
import '../../../domain/sharing/share_model.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/selector_field.dart';
import '../../../shared/widgets/states.dart';
import '../../../shared/widgets/value_tile.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../accounts/presentation/mpesa_lines_screen.dart' show LinePick;
import '../../auth/application/auth_controller.dart';
import '../../backup/application/backup_providers.dart';
import '../../spaces/application/spaces_providers.dart';
import '../application/group_sync_controller.dart';
import '../application/share_providers.dart';
import 'approval_screens.dart';
import 'group_sync_widgets.dart';
import 'share_scanner.dart';

/// The privacy note on every sharing screen.
const sharePrivacyNote =
    'Files are encrypted on your phone; only members can open them.';

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

/// Picks a `.pcshare` file, read into memory.
abstract interface class ShareFilePicker {
  Future<(String, List<int>)?> pick();
}

class SystemShareFilePicker implements ShareFilePicker {
  const SystemShareFilePicker();

  @override
  Future<(String, List<int>)?> pick() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Update file', extensions: ['pcshare']),
      ],
    );
    if (file == null) return null;
    return (file.name, await file.readAsBytes());
  }
}

final shareFilePickerProvider = Provider<ShareFilePicker>(
  (ref) => const SystemShareFilePicker(),
);

/// The lock and the privacy note.
class SharePrivacyNote extends StatelessWidget {
  const SharePrivacyNote({super.key, this.text = sharePrivacyNote});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.lock_outline,
          size: 18,
          color: PesaColors.of(context).textMuted,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: _muted(context))),
      ],
    ),
  );
}

/// A row with an icon, a name and a hint, and a chevron.
class _IconRow extends StatelessWidget {
  const _IconRow(this.icon, this.title, this.subtitle, {this.onTap, super.key});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: const Icon(Icons.chevron_right),
    enabled: onTap != null,
    onTap: onTap,
  );
}

/// The Sharing section's row in a space's settings.
class ShareSpaceTile extends ConsumerWidget {
  const ShareSpaceTile({required this.spaceId, super.key});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(shareOverviewProvider).value;
    final count = overview?.count ?? 1;
    return _IconRow(
      Icons.people_outline,
      'Share this space',
      '${count == 1 ? 'Just you' : '$count people'} · works by sending a '
          'file, no server',
      key: const Key('space-share'),
      onTap: () => context.push(AppRoutes.shareSpace(spaceId)),
    );
  }
}

/// Share this space: send and add update files, then the members with
/// their roles, the limits and the privacy note (decision 0031, stage 1).
class ShareSpaceScreen extends ConsumerWidget {
  const ShareSpaceScreen({required this.spaceId, super.key});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = ref.watch(activeSpaceProvider);
    final loaded = ref.watch(shareOverviewProvider);
    final overview = loaded.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share this space'),
        actions: [
          if (overview?.shared ?? false)
            IconButton(
              key: const Key('share-history'),
              tooltip: 'Space history',
              icon: const Icon(Icons.history),
              onPressed: () => context.push(AppRoutes.spaceHistory(spaceId)),
            ),
        ],
      ),
      body: overview == null
          ? const LoadingView()
          : ref.watch(groupSyncFlagProvider) && overview.shared
          // Pull to sync, as on the space's other screens.
          ? RefreshIndicator(
              onRefresh: () => ref.read(groupSyncProvider.notifier).sync(),
              child: _ShareBody(
                space: space,
                overview: overview,
                spaceId: spaceId,
              ),
            )
          : _ShareBody(space: space, overview: overview, spaceId: spaceId),
    );
  }
}

class _ShareBody extends ConsumerWidget {
  const _ShareBody({
    required this.space,
    required this.overview,
    required this.spaceId,
  });

  final Space space;
  final ShareOverview overview;
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = _muted(context);
    final owner = overview.myRole == ShareRole.owner;
    final lastSent = _latest(overview, sent: true);
    final lastFrom = _latest(overview, sent: false);
    final viewer = overview.myRole == ShareRole.viewer;
    final sync = ref.watch(groupSyncProvider).value;
    final syncShown = sync != null && sync.phase != GroupSyncPhase.hidden;
    final syncOn = syncShown && sync.on;
    final files = GroupedSection(
      children: [
        _IconRow(
          Icons.upload_file_outlined,
          'Share an update file',
          viewer
              ? 'Viewers receive updates only'
              : syncOn
              ? 'Still works, for anyone not syncing'
              : lastSent == null
              ? null
              : 'Last sent to ${overview.nameOf(lastSent.$1)} · '
                    '${_day(lastSent.$2)}',
          key: const Key('share-send'),
          onTap: viewer ? null : () => _send(context, ref, overview),
        ),
        _IconRow(
          Icons.file_download_outlined,
          'Add an update from someone',
          lastFrom == null
              ? null
              : 'Last from ${overview.nameOf(lastFrom.$1)} · '
                    '${_day(lastFrom.$2)}',
          key: const Key('share-receive'),
          onTap: () => receiveShareFile(context, ref),
        ),
      ],
    );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: _pad,
      children: [
        Text(
          syncShown
              ? 'Everyone keeps their own copy. With sync on, changes reach '
                    'the others by themselves.'
              : 'Everyone keeps their own copy. Send an update file when you '
                    'add things; open the ones others send.',
          style: muted,
        ),
        const SizedBox(height: 12),
        if (syncShown) ...[
          GroupSyncCard(space: space),
          const SizedBox(height: 12),
        ],
        if (overview.shared) ApprovalsCard(spaceId: spaceId),
        if (!syncShown) files,
        SectionLabel(
          'Members',
          trailing: Text(
            '${overview.count} of ${overview.limit}',
            style: theme.textTheme.labelLarge!.copyWith(
              color: PesaColors.of(context).textMuted,
            ),
          ),
        ),
        GroupedSection(
          children: [
            if (!overview.shared)
              const _MemberRow(
                letter: 'Y',
                name: 'You',
                hint: 'Made this space',
                role: ShareRole.owner,
              )
            else
              for (final m in overview.members)
                _MemberRow(
                  key: Key('share-member-${m.name}'),
                  letter: m.id == overview.myId
                      ? 'Y'
                      : (m.name.isEmpty ? '?' : m.name[0].toUpperCase()),
                  name: m.id == overview.myId ? 'You' : m.name,
                  hint: _memberHint(m, overview),
                  role: m.role,
                  onTap: owner && m.id != overview.myId
                      ? () => showRoleSheet(context, m)
                      : null,
                ),
          ],
        ),
        if (overview.shared) ...[
          const SizedBox(height: 12),
          RulesRow(spaceId: spaceId),
        ],
        const SizedBox(height: 12),
        GroupedSection(
          children: [
            _IconRow(
              Icons.qr_code_scanner,
              'Add a member',
              'Show a QR code, then check the safety words',
              key: const Key('share-add-member'),
              onTap: owner ? () => _addMember(context, ref, overview) : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'A Household holds up to 6 people, a Savings group up to 30.',
          style: theme.textTheme.bodySmall!.copyWith(
            color: PesaColors.of(context).textMuted,
          ),
        ),
        if (syncShown) ...[const SectionLabel('Update files'), files],
        if (syncOn)
          const SharePrivacyNote(text: syncPrivacyNote)
        else
          const SharePrivacyNote(),
      ],
    );
  }

  static (String, DateTime)? _latest(ShareOverview o, {required bool sent}) {
    (String, DateTime)? best;
    for (final p in o.peers.values) {
      final t = sent ? p.lastSentAt : p.lastFromAt;
      if (t != null && (best == null || t.isAfter(best.$2))) {
        best = (p.memberId, t);
      }
    }
    return best;
  }

  String _memberHint(ShareMember m, ShareOverview o) {
    if (m.role == ShareRole.owner) return 'Made this space';
    final joined = o.peers[m.id]?.joinedAt;
    final when = joined == null ? null : shortDate(CalendarDate.local(joined));
    if (!m.hasAccount) {
      return when == null ? 'No account' : 'No account · joined $when';
    }
    return when == null ? 'Joined' : 'Joined $when';
  }

  Future<void> _send(
    BuildContext context,
    WidgetRef ref,
    ShareOverview o,
  ) async {
    final others = o.others;
    if (others.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add a member first.')));
      return;
    }
    final to = others.length == 1
        ? others.single
        : await pickOne<ShareMember?>(
            context,
            title: 'Send to',
            options: [for (final m in others) (m, m.name)],
            selected: null,
          );
    if (to == null || !context.mounted) return;
    final repo = ref.read(shareRepositoryProvider)!;
    final out = await repo.buildUpdate(to.id, spaceName: space.name);
    if (!context.mounted) return;
    await showAppSheet<void>(
      context: context,
      builder: (_) => ShareSendSheet(spaceName: space.name, out: out),
    );
    ref.invalidate(shareOverviewProvider);
  }

  Future<void> _addMember(
    BuildContext context,
    WidgetRef ref,
    ShareOverview o,
  ) async {
    final repo = ref.read(shareRepositoryProvider)!;
    if (!o.shared) {
      final mine = await _askName(
        context,
        'Your name in this space',
        ref.read(displayNameProvider) ?? '',
      );
      if (mine == null || !context.mounted) return;
      await repo.start(
        myName: mine,
        hasAccount: ref.read(authControllerProvider).value != null,
      );
    }
    if (!context.mounted) return;
    await showAppSheet<void>(
      context: context,
      builder: (_) => AddMemberSheet(spaceName: space.name, kind: space.kind),
    );
    ref.invalidate(shareOverviewProvider);
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.letter,
    required this.name,
    required this.hint,
    required this.role,
    this.onTap,
    super.key,
  });

  final String letter;
  final String name;
  final String hint;
  final ShareRole role;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ValueTile(
    leading: InitialsBadge(letter),
    title: Text(name),
    subtitle: Text(hint),
    // The role moves under the name at larger text, rather than break it.
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(role.label, style: Theme.of(context).textTheme.labelMedium),
        if (onTap != null) const Icon(Icons.chevron_right),
      ],
    ),
    onTap: onTap,
  );
}

Future<String?> _askName(
  BuildContext context,
  String title,
  String initial,
) async {
  final controller = TextEditingController(text: initial);
  final name = await showAppSheet<String>(
    context: context,
    builder: (context) => SheetBody(
      title: title,
      children: [
        LabeledField(
          label: 'Name',
          child: TextField(
            key: const Key('share-name-field'),
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('share-name-save'),
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  return name == null || name.isEmpty ? null : name;
}

/// A member's role: Owner, Treasurer (chamas only), Member or Viewer; the
/// chosen one in red text with a check. Remove from group is red text.
Future<void> showRoleSheet(BuildContext context, ShareMember member) =>
    showAppSheet<void>(
      context: context,
      builder: (_) => RoleSheet(member: member),
    );

class RoleSheet extends ConsumerStatefulWidget {
  const RoleSheet({required this.member, super.key});

  final ShareMember member;

  @override
  ConsumerState<RoleSheet> createState() => _RoleSheetState();
}

class _RoleSheetState extends ConsumerState<RoleSheet> {
  late var _role = widget.member.role;
  late var _approver = widget.member.approver;

  @override
  Widget build(BuildContext context) {
    final space = ref.watch(activeSpaceProvider);
    final overview = ref.watch(shareOverviewProvider).value;
    final error = Theme.of(context).colorScheme.error;
    final chama = space.kind == SpaceKind.savingsGroup;
    return SheetBody(
      title: widget.member.name,
      subtitle:
          '${space.name} · ${overview?.count ?? 1} of '
          '${memberLimit(space.kind)} members',
      children: [
        const SectionLabel('Role', padding: EdgeInsets.only(bottom: 8)),
        GroupedSection(
          children: [
            for (final r in ShareRole.offeredIn(space.kind))
              LinePick(
                key: Key('share-role-${r.name}'),
                title: r.label,
                hint: r.hint,
                chosen: _role == r,
                onTap: () => setState(() => _role = r),
              ),
          ],
        ),
        if (_role == ShareRole.member) ...[
          const SizedBox(height: 12),
          GroupedSection(
            children: [
              SwitchListTile.adaptive(
                key: const Key('share-can-approve'),
                title: const Text('Can approve'),
                subtitle: const Text(
                  "Says yes or no to other members' changes that need "
                  'approval',
                ),
                value: _approver,
                onChanged: (on) => setState(() => _approver = on),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '${chama ? 'Treasurer is offered in Savings groups only. ' : ''}'
          'A role is kept on every phone and checked when an update is '
          'opened.',
          style: _muted(context),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('share-role-save'),
          onPressed: () async {
            final repo = ref.read(shareRepositoryProvider)!;
            await repo.setRole(widget.member.id, _role);
            await repo.setApprover(
              widget.member.id,
              approver: _role == ShareRole.member && _approver,
            );
            ref
              ..invalidate(shareOverviewProvider)
              ..invalidate(toApproveProvider);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('share-remove'),
          onPressed: _remove,
          child: Text('Remove from group', style: TextStyle(color: error)),
        ),
      ],
    );
  }

  Future<void> _remove() async {
    final name = widget.member.name;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('Remove $name?'),
        content: Text(
          "$name's phone keeps what it already has; nothing can take that "
          'back. The space gets a new key, so nothing you send from now on '
          'opens there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            key: const Key('share-remove-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Remove',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await ref.read(shareRepositoryProvider)!.remove(widget.member.id);
    ref.invalidate(shareOverviewProvider);
    if (mounted) Navigator.pop(context);
  }
}

/// A QR code, black on white whatever the theme, so any phone reads it.
class ShareQrCode extends StatelessWidget {
  const ShareQrCode(this.data, {this.size = 168, super.key});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'QR code',
    image: true,
    child: Center(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: CustomPaint(size: Size.square(size), painter: _QrPainter(data)),
      ),
    ),
  );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.data);

  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    for (final e in Barcode.qrCode().make(
      data,
      width: size.width,
      height: size.height,
    )) {
      if (e is BarcodeBar && e.black) {
        canvas.drawRect(Rect.fromLTWH(e.left, e.top, e.width, e.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}

/// The words, large, as both phones show them.
class SafetyWordsText extends StatelessWidget {
  const SafetyWordsText(this.words, {super.key});

  final List<String> words;

  @override
  Widget build(BuildContext context) => Text(
    safetyLine(words),
    key: const Key('share-words'),
    style: Theme.of(context).textTheme.titleLarge!
        .copyWith(fontWeight: FontWeight.w600),
  );
}

Widget _card(BuildContext context, List<Widget> children) => Card(
  margin: EdgeInsets.zero,
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  ),
);

/// Update file ready: the encrypted file to send, and the first time, the
/// safety words and their QR code.
class ShareSendSheet extends ConsumerStatefulWidget {
  const ShareSendSheet({required this.spaceName, required this.out, super.key});

  final String spaceName;
  final OutgoingShare out;

  @override
  ConsumerState<ShareSendSheet> createState() => _ShareSendSheetState();
}

class _ShareSendSheetState extends ConsumerState<ShareSendSheet> {
  var _sending = false;

  @override
  Widget build(BuildContext context) {
    final out = widget.out;
    final theme = Theme.of(context);
    final kb = (out.bytes.length / 1024).ceil();
    return SheetBody(
      title: 'Update file ready',
      subtitle:
          '${widget.spaceName} · ${out.added} new, ${out.changed} changed '
          'since you last sent · $kb KB',
      children: [
        _card(context, [
          Row(
            children: [
              const Icon(Icons.lock_outline),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // One long word: smaller at large text, never broken.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        out.fileName,
                        style: theme.textTheme.bodyLarge!.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      'Encrypted. Send it any way you like.',
                      style: _muted(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('share-send-file'),
          onPressed: _sending ? null : _sendFile,
          child: const Text('Send by WhatsApp, email…'),
        ),
        if (!out.wordsChecked) ...[
          const SectionLabel('Check the key, once per person'),
          _card(context, [
            Text(
              'Read these out, or let their phone scan the code. They should '
              'see the same.',
              style: _muted(context),
            ),
            const SizedBox(height: 8),
            SafetyWordsText(out.words),
            const SizedBox(height: 12),
            ShareQrCode('pcshare-words:${out.words.join('-')}'),
          ]),
        ],
        const SizedBox(height: 8),
        const SharePrivacyNote(),
      ],
    );
  }

  Future<void> _sendFile() async {
    setState(() => _sending = true);
    final repo = ref.read(shareRepositoryProvider)!;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${widget.out.fileName}');
      await file.writeAsBytes(widget.out.bytes, flush: true);
      await ref
          .read(fileSharerProvider)
          .shareFile(file, subject: widget.out.fileName);
      await repo.markSent(widget.out);
      ref.invalidate(shareOverviewProvider);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

/// Add a member, in two steps: their role, then their join request
/// (made on their phone, with their own key) and its safety words; then
/// the invite, sealed to their key, to send back.
class AddMemberSheet extends ConsumerStatefulWidget {
  const AddMemberSheet({
    required this.spaceName,
    required this.kind,
    super.key,
  });

  final String spaceName;
  final SpaceKind kind;

  @override
  ConsumerState<AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<AddMemberSheet> {
  var _role = ShareRole.member;

  /// Their join request, its name and words, once added.
  (String, String, List<String>)? _request;
  (String, ShareMember, List<String>)? _invite;
  String? _problem;

  @override
  Widget build(BuildContext context) {
    final request = _request;
    final invite = _invite;
    if (invite != null) {
      final (text, member, words) = invite;
      return SheetBody(
        title: 'Invite ${member.name}',
        subtitle:
            'Let their phone scan the code, or send the invite file. '
            'Only their phone can open it.',
        children: [
          _card(context, [
            Text(
              'Read these out once they open it. They should see the same.',
              style: _muted(context),
            ),
            const SizedBox(height: 6),
            SafetyWordsText(words),
            const SizedBox(height: 12),
            ShareQrCode(text, size: 220),
          ]),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('share-invite-send'),
            onPressed: () => _sendInvite(text, member.name),
            child: const Text('Send the invite file'),
          ),
          const SizedBox(height: 8),
          const SharePrivacyNote(),
        ],
      );
    }
    if (request != null) {
      final (_, name, words) = request;
      return SheetBody(
        title: 'Add $name',
        subtitle: '${_role.label} · ${widget.spaceName}',
        children: [
          _card(context, [
            Text(
              'Check these words match their screen',
              style: _muted(context),
            ),
            const SizedBox(height: 6),
            SafetyWordsText(words),
          ]),
          if (_problem != null) ...[
            const SizedBox(height: 8),
            Notice(_problem!, problem: true),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('share-invite-make'),
            onPressed: _make,
            child: const Text('The words match, send the invite'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('share-request-no'),
            onPressed: () => setState(() => _request = null),
            child: const Text("They don't match"),
          ),
          const SizedBox(height: 8),
          const SharePrivacyNote(),
        ],
      );
    }
    return SheetBody(
      title: 'Add a member',
      children: [
        const SectionLabel('Role', padding: EdgeInsets.only(bottom: 8)),
        GroupedSection(
          children: [
            for (final r in ShareRole.offeredIn(widget.kind))
              if (r != ShareRole.owner)
                LinePick(
                  key: Key('share-invite-${r.name}'),
                  title: r.label,
                  hint: r.hint,
                  chosen: _role == r,
                  onTap: () => setState(() => _role = r),
                ),
          ],
        ),
        const SectionLabel('Ask them for their join request'),
        Text(
          'On their phone: Profile, Spaces, Join a shared space, then Send '
          'this to the owner. Their key stays on their phone.',
          style: _muted(context),
        ),
        if (_problem != null) ...[
          const SizedBox(height: 8),
          Notice(_problem!, problem: true),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('share-request-scan'),
          onPressed: () async {
            final text = await ref
                .read(shareCodeScannerProvider)
                .scan(context, ShareCodeKind.joinRequest);
            if (text != null) _takeRequest(text);
          },
          child: const Text('Scan their join request'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('share-request-add'),
          onPressed: _addRequest,
          child: const Text('Add their join request file'),
        ),
      ],
    );
  }

  Future<void> _addRequest() async {
    final picked = await ref.read(shareFilePickerProvider).pick();
    if (picked == null) return;
    _takeRequest(utf8.decode(picked.$2, allowMalformed: true));
  }

  /// A join request, scanned or from a file: read the same way either way.
  void _takeRequest(String text) {
    try {
      if (readShareCode(text) != ShareCodeKind.joinRequest) {
        throw const ShareFileException('not a join request');
      }
      final (name, words) = ShareRepository.readJoinRequest(text);
      setState(() {
        _request = (text, name, words);
        _problem = null;
      });
    } on ShareFileException {
      setState(() => _problem = "That isn't a join request.");
    }
  }

  Future<void> _make() async {
    try {
      final (text, member, words) = await ref
          .read(shareRepositoryProvider)!
          .invite(
            request: _request!.$1,
            role: _role,
            spaceName: widget.spaceName,
          );
      ref.invalidate(shareOverviewProvider);
      setState(() => _invite = (text, member, words));
    } on ShareLimitReached catch (e) {
      setState(() => _problem = e.toString());
    }
  }

  Future<void> _sendInvite(String text, String name) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/invite-${_slug(name)}.pcshare');
    await file.writeAsString(text, flush: true);
    await ref
        .read(fileSharerProvider)
        .shareFile(file, subject: 'Join ${widget.spaceName}');
  }
}

String _slug(String name) =>
    name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');

/// Picks an update file and shows what it holds, or the join screen for an
/// invite.
Future<void> receiveShareFile(BuildContext context, WidgetRef ref) async {
  final picked = await ref.read(shareFilePickerProvider).pick();
  if (picked == null || !context.mounted) return;
  final (name, bytes) = picked;
  if (_starts(bytes, ShareCodec.invitePrefix)) {
    await context.push(AppRoutes.joinSpace, extra: utf8.decode(bytes));
    return;
  }
  if (_starts(bytes, ShareCodec.joinPrefix)) {
    if (context.mounted) {
      _say(context, 'This is a join request. Add it from Add a member.');
    }
    return;
  }
  final repo = ref.read(shareRepositoryProvider);
  if (repo == null || await repo.state() == null) {
    if (context.mounted) _say(context, const ShareRefused.unreadable().message);
    return;
  }
  try {
    final incoming = await repo.preview(bytes);
    if (!context.mounted) return;
    await showAppSheet<void>(
      context: context,
      builder: (_) => ShareReceiveSheet(fileName: name, incoming: incoming),
    );
  } on ShareRefused catch (e) {
    if (context.mounted) _say(context, e.message);
  }
}

bool _starts(List<int> bytes, String text) {
  final prefix = ascii.encode(text);
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

void _say(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// The title of the receive sheet: "From Jane: 14 new, 2 changed, 1
/// conflict (later wins)".
String receiveTitle(String from, MergeOutcome o, {bool mine = false}) {
  final waiting = o.waiting.length;
  final parts = [
    '${o.added.length} new',
    if (waiting == 0 || o.changed.isNotEmpty) '${o.changed.length} changed',
    if (waiting > 0) '$waiting waiting for ${mine ? 'your ' : ''}approval',
    if (o.conflicts.isNotEmpty)
      '${o.conflicts.length} conflict${o.conflicts.length == 1 ? '' : 's'} '
          '(later wins)',
  ];
  return 'From ${from.split(' ').first}: ${parts.join(', ')}';
}

/// What an update file holds, the conflicts in words, then Apply.
class ShareReceiveSheet extends ConsumerStatefulWidget {
  const ShareReceiveSheet({
    required this.fileName,
    required this.incoming,
    super.key,
  });

  final String fileName;
  final IncomingShare incoming;

  @override
  ConsumerState<ShareReceiveSheet> createState() => _ShareReceiveSheetState();
}

class _ShareReceiveSheetState extends ConsumerState<ShareReceiveSheet> {
  var _applying = false;

  @override
  Widget build(BuildContext context) {
    final i = widget.incoming;
    final o = i.outcome;
    final conflicts = o.conflicts.length;
    final waiting = o.waiting.length;
    final overview = ref.watch(shareOverviewProvider).value;
    final mine =
        overview != null &&
        overview.myRole != ShareRole.viewer &&
        (overview.myRole == ShareRole.owner ||
            (overview.kind == SpaceKind.savingsGroup &&
                overview.myRole == ShareRole.treasurer) ||
            (overview.me?.approver ?? false));
    return SheetBody(
      title: receiveTitle(i.from.name, o, mine: mine),
      subtitle:
          '${widget.fileName}${i.wordsChecked ? ' · key checked' : ''} · '
          '${_day(i.header.at)}',
      children: [
        GroupedSection(
          children: [
            LabelValueRow(
              label: 'New transactions',
              value: '${o.added.length}',
            ),
            LabelValueRow(label: 'Changed', value: '${o.changed.length}'),
            if (waiting > 0)
              LabelValueRow(
                key: const Key('share-waiting'),
                label: 'Waiting for approval',
                value: '$waiting',
              ),
            if (conflicts > 0)
              ListTile(
                key: const Key('share-conflicts'),
                title: Text('$conflicts conflict${conflicts == 1 ? '' : 's'}'),
                subtitle: Text(i.conflictLines.join('\n')),
              ),
          ],
        ),
        if (waiting > 0 && !i.alreadyApplied) ...[
          const SizedBox(height: 8),
          Text(
            'The ${o.added.length} new one${o.added.length == 1 ? '' : 's'} '
            'count now. The $waiting change${waiting == 1 ? '' : 's'} '
            '${waiting == 1 ? 'waits' : 'wait'} '
            '${mine ? 'in Changes to approve' : 'for an approver'}.',
            style: _muted(context),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          i.alreadyApplied
              ? 'This file was applied already: applying it again changes '
                    'nothing.'
              : 'Already applied files are skipped, so opening the same one '
                    'twice changes nothing.',
          style: _muted(context),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('share-apply'),
          onPressed: _applying ? null : _apply,
          child: const Text('Apply'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Not now'),
        ),
      ],
    );
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      await ref.read(shareRepositoryProvider)!.apply(widget.incoming.bytes);
      ref
        ..invalidate(shareOverviewProvider)
        ..invalidate(toApproveProvider);
      if (mounted) Navigator.pop(context);
    } on ShareRefused catch (e) {
      if (mounted) _say(context, e.message);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }
}

final spaceHistoryProvider = FutureProvider<List<HistoryGroup>>(
  (ref) => ref.watch(shareRepositoryProvider)!.history(),
);

/// Every change by every member, grouped by file, newest first. A conflict
/// says who won and why, with "Use mine instead"; a removal offers "Bring
/// it back".
class SpaceHistoryScreen extends ConsumerWidget {
  const SpaceHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(spaceHistoryProvider);
    final overview = ref.watch(shareOverviewProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Space history')),
      body: switch (groups) {
        AsyncData(:final value) => ListView(
          padding: _pad,
          children: [
            Text(
              'Every change, from every member, newest first.',
              style: _muted(context),
            ),
            for (final g in value) ...[
              SectionLabel(
                '${_day(g.at)} · '
                '${g.fromMember == null ? 'on this phone' : "from ${_cap(overview?.nameOf(g.fromMember!) ?? 'someone')}'s file"}',
              ),
              GroupedSection(
                children: [for (final l in g.lines) _HistoryRow(line: l)],
              ),
            ],
          ],
        ),
        AsyncError() => const EmptyNote("Space history can't be read."),
        _ => const LoadingView(),
      },
    );
  }
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.line});

  final HistoryLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final action = line.useMine != null
        ? 'Use mine instead'
        : line.bringBack != null
        ? 'Bring it back'
        : null;
    return ListTile(
      title: Text(line.title),
      subtitle: line.detail == null && action == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (line.detail != null) Text(line.detail!),
                if (action != null)
                  InkWell(
                    key: Key('history-$action'),
                    onTap: () => _act(ref),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: Layout.minTouch,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          action,
                          style: theme.textTheme.bodyMedium!.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _act(WidgetRef ref) async {
    final repo = ref.read(shareRepositoryProvider)!;
    if (line.useMine case final id?) {
      await repo.useMine(id);
    } else if (line.bringBack case final key?) {
      final [entity, uid] = key.split('|');
      await repo.bringBack(ShareEntity.byName(entity)!, uid);
    }
    ref.invalidate(spaceHistoryProvider);
  }
}

/// Where the join request's key pair waits, on the invitee's phone, until
/// the invite comes: in the main database, which is encrypted.
const joinRequestKey = 'share.joinRequest';

/// The join request this phone is waiting on: its name and key pair.
final pendingJoinProvider = FutureProvider<(String, ShareKeyPair)?>((
  ref,
) async {
  final json = await ref
      .watch(mainSettingsRepositoryProvider)
      .readJson(joinRequestKey);
  final seed = json?['seed'];
  final name = json?['name'];
  if (seed is! String || name is! String) return null;
  return (name, await ShareKeyPair.fromSeed(base64Url.decode(seed)));
});

/// Join a shared space, step 1: this phone makes its own key and a join
/// request to send to the owner, then opens the invite they send back.
class JoinRequestScreen extends ConsumerStatefulWidget {
  const JoinRequestScreen({super.key});

  @override
  ConsumerState<JoinRequestScreen> createState() => _JoinRequestScreenState();
}

class _JoinRequestScreenState extends ConsumerState<JoinRequestScreen> {
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.text = ref.read(displayNameProvider) ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingJoinProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Join a shared space')),
      body: switch (pending) {
        AsyncData(value: final (String, ShareKeyPair) p) => _ready(p),
        AsyncData() => _ask(),
        AsyncError() => const EmptyNote("This can't be opened."),
        _ => const LoadingView(),
      },
    );
  }

  Widget _ask() => ListView(
    padding: _pad,
    children: [
      Text(
        'You make a join request here, with a key that stays on this phone. '
        'The owner adds it and sends back an invite only this phone can '
        "open. You don't need an account.",
        style: _muted(context),
      ),
      const SizedBox(height: 16),
      LabeledField(
        label: 'Your name in this space',
        child: TextField(
          key: const Key('join-request-name'),
          controller: _name,
          textCapitalization: TextCapitalization.words,
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('join-request-make'),
        onPressed: () async {
          final name = _name.text.trim();
          if (name.isEmpty) return;
          final (_, pair, _) = await ShareRepository.makeJoinRequest(name);
          await ref.read(mainSettingsRepositoryProvider).writeJson(
            joinRequestKey,
            {'name': name, 'seed': base64Url.encode(pair.seed)},
          );
          ref.invalidate(pendingJoinProvider);
        },
        child: const Text('Make my join request'),
      ),
      const SharePrivacyNote(),
    ],
  );

  Widget _ready((String, ShareKeyPair) p) {
    final (name, pair) = p;
    final text = ShareCodec().joinRequest(
      name: name,
      publicKey: pair.publicKey,
    );
    return ListView(
      padding: _pad,
      children: [
        Text(
          'Send this to the owner, or let their phone scan the code. When '
          'the invite comes back, open it here.',
          style: _muted(context),
        ),
        const SizedBox(height: 16),
        _card(context, [
          Text(
            "Read these out. They should see the same on the owner's phone.",
            style: _muted(context),
          ),
          const SizedBox(height: 6),
          SafetyWordsText(joinWords(pair.publicKey)),
          const SizedBox(height: 12),
          ShareQrCode(text),
        ]),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('join-request-send'),
          onPressed: () async {
            final dir = await getTemporaryDirectory();
            final file = File('${dir.path}/join-${_slug(name)}.pcshare');
            await file.writeAsString(text, flush: true);
            await ref
                .read(fileSharerProvider)
                .shareFile(file, subject: 'Join request from $name');
          },
          child: const Text('Send this to the owner'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('join-request-scan'),
          onPressed: () async {
            final text = await ref
                .read(shareCodeScannerProvider)
                .scan(context, ShareCodeKind.invite);
            if (text != null && mounted) {
              await context.push(AppRoutes.joinSpace, extra: text);
            }
          },
          child: const Text('Scan the invite'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('join-request-open'),
          onPressed: () => receiveShareFile(context, ref),
          child: const Text('Open the invite file'),
        ),
        const SharePrivacyNote(),
      ],
    );
  }
}

/// Joining, step 3: opened from the invite file. No sign-in: check the
/// words, give a name, join.
class JoinSpaceScreen extends ConsumerStatefulWidget {
  const JoinSpaceScreen({required this.invite, super.key});

  final String invite;

  @override
  ConsumerState<JoinSpaceScreen> createState() => _JoinSpaceScreenState();
}

class _JoinSpaceScreenState extends ConsumerState<JoinSpaceScreen> {
  Map<String, Object?>? _details;
  ShareKeyPair? _pair;
  String? _name;
  String? _bad;
  var _joining = false;

  @override
  void initState() {
    super.initState();
    Future(() async {
      try {
        final details = ShareRepository.readInvite(widget.invite);
        final pending = await ref.read(pendingJoinProvider.future);
        if (pending == null) {
          if (mounted) {
            setState(
              () => _bad =
                  'This invite was made for another phone. Make a join '
                  'request first, from Join a shared space.',
            );
          }
          return;
        }
        // Only the phone whose key the invite was sealed to opens it.
        await ShareCodec().openInvite(widget.invite, pending.$2);
        if (!mounted) return;
        setState(() {
          _details = details;
          _pair = pending.$2;
          _name = pending.$1;
        });
      } on Object {
        if (mounted) {
          setState(() => _bad = 'This invite was made for another phone.');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = _details;
    if (_bad != null) {
      return Scaffold(appBar: AppBar(), body: EmptyNote(_bad!));
    }
    if (d == null) return const Scaffold(body: LoadingView());
    final owner = ((d['owner'] as Map?)?['name'] as String? ?? 'The owner')
        .split(' ')
        .first;
    final role = ShareRole.byName((d['you'] as Map?)?['role'])?.label ?? '';
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: _pad,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Join ${d['name']}',
              style: theme.textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "$owner invited you as a $role. You don't need an account; the "
            'space lives only on this phone and theirs.',
            style: _muted(context),
          ),
          const SizedBox(height: 16),
          _card(context, [
            Text(
              "Check these words match $owner's screen",
              style: _muted(context),
            ),
            const SizedBox(height: 6),
            SafetyWordsText(ShareRepository.inviteWords(widget.invite, _pair!)),
          ]),
          const SizedBox(height: 12),
          GroupedSection(
            children: [
              ListTile(
                key: const Key('join-name'),
                title: const Text('Your name in this space'),
                subtitle: Text(_name ?? ''),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final name = await _askName(
                    context,
                    'Your name in this space',
                    _name ?? '',
                  );
                  if (name != null) setState(() => _name = name);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'They see what you add here and who added it. Your Personal '
            'space stays apart.',
            style: theme.textTheme.bodySmall!.copyWith(
              color: PesaColors.of(context).textMuted,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('join-yes'),
            onPressed: _joining ? null : _join,
            child: const Text('The words match, join'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('join-no'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                scrollable: true,
                title: const Text("Don't join"),
                content: Text(
                  'The words differ, so this invite may not be from $owner. '
                  'Ask them to show the code again, face to face or on a '
                  'call.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      this.context.pop();
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
            child: const Text("They don't match"),
          ),
          const SizedBox(height: 8),
          const SharePrivacyNote(),
        ],
      ),
    );
  }

  Future<void> _join() async {
    final d = _details!;
    final kind = SpaceKind.values.asNameMap()[d['kind']];
    if (kind == null || !canShare(kind)) return;
    setState(() => _joining = true);
    final router = GoRouter.of(context);
    final settings = ref.read(mainSettingsRepositoryProvider);
    final id = await ref
        .read(spacesProvider.notifier)
        .add(d['name']! as String, kind);
    final repo = ShareRepository(ref.read(appDatabaseProvider), kind: kind);
    await repo.join(
      widget.invite,
      mine: _pair!,
      myName: _name ?? '',
      hasAccount: ref.read(authControllerProvider).value != null,
    );
    // The key now lives in the space's own database.
    await settings.writeJson(joinRequestKey, const {});
    ref
      ..invalidate(pendingJoinProvider)
      ..invalidate(shareOverviewProvider);
    router.go(AppRoutes.shareSpace(id));
  }
}
