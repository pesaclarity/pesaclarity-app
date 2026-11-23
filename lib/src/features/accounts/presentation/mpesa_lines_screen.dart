import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../domain/accounts/mpesa_lines.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/sections.dart';
import '../../../theme/pesa_colors.dart';
import '../../sms/presentation/read_again_card.dart' show countLabel;
import '../../spaces/application/spaces_providers.dart';
import '../application/mpesa_lines_providers.dart';
import 'mpesa_lines_sheet.dart';

/// The words of M-Pesa lines, its sheets and its questions.
abstract final class LinesText {
  static const title = 'M-Pesa lines';
  static String found(int n) =>
      '$n ${n == 1 ? 'line' : 'lines'} found on this phone, newest first. '
      'Tap one to name it, merge it or stop tracking it.';
  static String tracked(int n) =>
      '$n ${n == 1 ? 'line' : 'lines'} tracked, newest first.';
  static const quick = 'Keep my 2 most recent lines, set the rest aside';
  static String quickHint(String a, String b, int n, {required bool old}) =>
      '$a and $b stay. $n ${old ? 'old ' : 'other '}'
      '${n == 1 ? 'line stops' : 'lines stop'} being tracked.';
  static String oldLines(int n) => 'Old lines ($n)';
  static const oldHint = 'No messages for over 90 days';
  static const recentStays = 'A line used in the last 90 days stays up top.';
  static String notTracked(int n) =>
      '$n ${n == 1 ? 'line' : 'lines'} not tracked';
  static const manage = 'Manage';
  static String notTrackedHeading(int n) => 'Not tracked ($n)';
  static const mostRecent = 'Most recent';
  static const secondMostRecent = '2nd most recent';
  static const mainLine = 'Main line';
  static const secondLine = 'Second line';
  static const sameLine = 'Same line as…';
  static const dontTrack = "Don't track this line";
  static const mainHint = "Its balance is M-Pesa's first balance on Home.";
  static const secondHint = 'Its balance is added to the M-Pesa total.';
  static const sameHint =
      'One SIM replaced another. Its messages join that line.';
  static const samePick = 'Pick the line that replaced it.';
  static const dontHint = 'Its balance leaves every total.';
  static const dontPicked = 'New messages from it are skipped, without asking.';
  static const keep = 'Keep its past records';
  static String keepHint(String name, String balance) =>
      'They stay in Activity as "$name". Its $balance leaves the M-Pesa '
      "total; past months' totals stay.";
  static const delete = 'Delete its records';
  static String deleteHint(int n) =>
      'Its $n ${n == 1 ? 'record leaves' : 'records leave'} Activity, Plan '
      'and Insights. Balances are worked out again.';
  static String deleteQuestion(String name, int n) =>
      "Delete $name's $n ${n == 1 ? 'record' : 'records'}?";
  static String deleteBody(String balance) =>
      'They leave Activity, Plan and Insights, and balances are worked out '
      'again: the M-Pesa total drops by $balance and past months change. '
      'This cannot be undone.';
  static String stop(String name) => 'Stop tracking $name';
  static String mergeInto(String name) => 'Merge into $name';
  static const merge = 'Merge';
  static const mergeQuestion = 'Make them one line?';
  static String mergeBody({
    required String from,
    required String into,
    required int messages,
    required String newer,
    required String newerBalance,
    required String older,
    required String olderBalance,
  }) =>
      '$from and $into become one line. ${countLabel(messages)} messages, '
      'balance continues from the newer one ($newer, $newerBalance). '
      "$older's $olderBalance leaves the total; its records keep their dates.";
  static const quickTitle = 'Keep your 2 most recent lines?';
  static String quickSubtitle(int n) =>
      'Past records stay; new messages from the other $n are ignored.';
  static const kept = 'Kept';
  static const setAside = 'Set aside';
  static String pastMessages(int n) => '${countLabel(n)} past messages';
  static const quickNote =
      "The M-Pesa total keeps only the two kept lines. Undo from any line's "
      'sheet.';
  static const keepThese = 'Keep these 2';
  static const nameHint = 'Such as Work line';
  static const whereMoneyGoes = 'Where its money goes';
  static const thisLineIs = 'This line is';
  static String skipped(String name) =>
      'A new message from $name was skipped, as you stopped tracking it. '
      'Later ones are skipped without a note.';
}

/// When [at] was, for a line: `today`, `yesterday`, `3 days ago`, or
/// `30 Jul 2026`.
String lineWhen(DateTime at, CalendarDate today) {
  final day = CalendarDate.local(at);
  final days = day.daysUntil(today);
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  return lineDate(at);
}

/// `3 Feb 2024`.
String lineDate(DateTime at) {
  final day = CalendarDate.local(at);
  return '${shortDate(day)} ${day.year}';
}

/// A line's balance without the currency, `0` when none was printed.
String _balance(BuildContext context, MpesaLine line) =>
    shownMoney(context, line.balanceMinor ?? 0, withCurrency: false);

String _withUnit(BuildContext context, MpesaLine line) => shownMoney(
  context,
  line.balanceMinor ?? 0,
  currency: 'KES',
  withCurrency: true,
);

/// The small word beside a line's name: its role once chosen, else how
/// recent it is.
String? lineTag(MpesaLines lines, MpesaLine line) {
  switch (lines.roleOf(line.id)) {
    case LineRole.main:
      return LinesText.mainLine;
    case LineRole.second:
      return LinesText.secondLine;
    case null:
  }
  if (lines.mainId != null || lines.secondId != null || !line.tracked) {
    return null;
  }
  final recent = [
    for (final l in lines.newestFirst)
      if (l.tracked) l.id,
  ];
  if (recent.isNotEmpty && recent.first == line.id) return LinesText.mostRecent;
  if (recent.length > 1 && recent[1] == line.id) {
    return LinesText.secondMostRecent;
  }
  return null;
}

/// Opens M-Pesa lines.
Future<void> openMpesaLines(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => const MpesaLinesScreen()));

/// M-Pesa lines: every line, newest first, with its last message, count,
/// balance and first day. Lines quiet for 90 days fold under "Old lines";
/// lines not tracked wait behind the note at the foot.
class MpesaLinesScreen extends ConsumerStatefulWidget {
  const MpesaLinesScreen({super.key});

  @override
  ConsumerState<MpesaLinesScreen> createState() => _MpesaLinesScreenState();
}

class _MpesaLinesScreenState extends ConsumerState<MpesaLinesScreen> {
  var _oldOpen = false;
  var _untrackedOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final lines = ref.watch(mpesaLinesProvider).value ?? MpesaLines.empty;
    final now = ref.watch(clockProvider)();
    final today = CalendarDate.local(now);
    final all = lines.newestFirst;
    final tracked = [
      for (final l in all)
        if (l.tracked) l,
    ];
    final untracked = [
      for (final l in all)
        if (!l.tracked) l,
    ];
    final recent = [
      for (final l in tracked)
        if (!l.isOld(now)) l,
    ];
    final old = [
      for (final l in tracked)
        if (l.isOld(now)) l,
    ];
    final muted = theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted);

    Widget card(List<Widget> rows) => Card(
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const Divider(height: 1),
            row,
          ],
        ],
      ),
    );
    Widget row(MpesaLine line) => _LineRow(
      line: line,
      tag: lineTag(lines, line),
      today: today,
      onTap: () => showLineSheet(context, line.id),
    );

    final (kept, aside) = lines.quickSetupSplit;
    return Scaffold(
      appBar: AppBar(title: const Text(LinesText.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            untracked.isEmpty
                ? LinesText.found(all.length)
                : LinesText.tracked(tracked.length),
            style: muted,
          ),
          const SizedBox(height: 16),
          if (lines.offersQuickSetup && kept.length == 2) ...[
            card([
              ListTile(
                key: const Key('lines-quick-setup'),
                title: const Text(LinesText.quick),
                subtitle: Text(
                  LinesText.quickHint(
                    kept[0].label,
                    kept[1].label,
                    aside.length,
                    old: aside.every((l) => l.isOld(now)),
                  ),
                ),
                trailing: Icon(Icons.chevron_right, color: colors.textMuted),
                onTap: () => showAppSheet<void>(
                  context: context,
                  builder: (_) => const QuickSetupSheet(),
                ),
              ),
            ]),
            const SizedBox(height: 12),
          ],
          if (recent.isNotEmpty) ...[
            card([for (final l in recent) row(l)]),
            const SizedBox(height: 12),
          ],
          if (old.isNotEmpty)
            card([
              Semantics(
                expanded: _oldOpen,
                button: true,
                child: ListTile(
                  key: const Key('lines-old'),
                  title: Text(LinesText.oldLines(old.length)),
                  subtitle: const Text(LinesText.oldHint),
                  trailing: Icon(
                    _oldOpen ? Icons.expand_less : Icons.expand_more,
                    color: colors.textMuted,
                  ),
                  onTap: () => setState(() => _oldOpen = !_oldOpen),
                ),
              ),
              if (_oldOpen)
                for (final l in old) row(l),
            ]),
          if (old.isNotEmpty && !_oldOpen && untracked.isEmpty) ...[
            const SizedBox(height: 8),
            Text(LinesText.recentStays, style: muted),
          ],
          if (untracked.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (_untrackedOpen) ...[
              SectionLabel(LinesText.notTrackedHeading(untracked.length)),
              card([for (final l in untracked) row(l)]),
            ] else
              Center(
                child: TextButton(
                  key: const Key('lines-manage-untracked'),
                  onPressed: () => setState(() => _untrackedOpen = true),
                  child: Text.rich(
                    TextSpan(
                      text: '${LinesText.notTracked(untracked.length)} · ',
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.textMuted,
                      ),
                      children: [
                        TextSpan(
                          text: LinesText.manage,
                          style: theme.textTheme.bodySmall!.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.tag,
    required this.today,
    required this.onTap,
  });

  final MpesaLine line;
  final String? tag;
  final CalendarDate today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final last = line.lastAt;
    final first = line.firstAt;
    final count =
        '${countLabel(line.messages)} '
        '${line.messages == 1 ? 'message' : 'messages'}';
    return ListTile(
      key: Key('line-row-${line.id}'),
      title: Text.rich(
        TextSpan(
          text: line.label,
          children: [
            if (tag != null)
              TextSpan(
                text: '  $tag',
                style: theme.textTheme.labelSmall!.copyWith(
                  color: colors.textMuted,
                ),
              ),
          ],
        ),
      ),
      subtitle: Text(
        [
          [
            if (last != null) 'Last message ${lineWhen(last, today)}',
            count,
          ].join(' · '),
          [
            'Balance ${_balance(context, line)}',
            if (first != null) 'since ${lineDate(first)}',
          ].join(' · '),
        ].join('\n'),
      ),
      trailing: Icon(Icons.chevron_right, color: colors.textMuted),
      onTap: onTap,
    );
  }
}

/// A choice in a sheet: red text and a check when chosen, no fill.
class LinePick extends StatelessWidget {
  const LinePick({
    required this.title,
    required this.chosen,
    required this.onTap,
    this.hint,
    this.indent = false,
    super.key,
  });

  final String title;
  final String? hint;
  final bool chosen;
  final bool indent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Semantics(
      selected: chosen,
      button: true,
      child: ListTile(
        contentPadding: EdgeInsetsDirectional.only(
          start: indent ? 32 : 16,
          end: 16,
        ),
        title: Text(
          title,
          style:
              (indent ? theme.textTheme.bodyMedium : theme.textTheme.bodyLarge)!
                  .copyWith(color: chosen ? colors.link : null),
        ),
        subtitle: hint == null ? null : Text(hint!),
        trailing: chosen ? Icon(Icons.check, color: colors.link) : null,
        onTap: onTap,
      ),
    );
  }
}

/// The quick setup: what is kept and what is set aside, then one tap.
class QuickSetupSheet extends ConsumerStatefulWidget {
  const QuickSetupSheet({super.key});

  @override
  ConsumerState<QuickSetupSheet> createState() => _QuickSetupSheetState();
}

class _QuickSetupSheetState extends ConsumerState<QuickSetupSheet> {
  var _saving = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final lines = ref.watch(mpesaLinesProvider).value ?? MpesaLines.empty;
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final (kept, aside) = lines.quickSetupSplit;
    final muted = theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted);

    Widget row(String name, String hint, String state) => ListTile(
      title: Text(name),
      subtitle: Text(hint),
      trailing: Text(state, style: theme.textTheme.labelMedium),
    );
    Widget card(List<Widget> rows) => Card(
      child: Column(
        children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0) const Divider(height: 1),
            r,
          ],
        ],
      ),
    );
    String when(MpesaLine l) =>
        l.lastAt == null ? '' : lineWhen(l.lastAt!, today);
    return SheetBody(
      title: LinesText.quickTitle,
      subtitle: LinesText.quickSubtitle(aside.length),
      children: [
        const SectionLabel(LinesText.kept),
        card([
          for (final (i, l) in kept.indexed)
            row(
              l.label,
              [
                if (i == 0) LinesText.mainLine else LinesText.secondLine,
                when(l),
                '${countLabel(l.messages)} messages',
              ].where((s) => s.isNotEmpty).join(' · '),
              LinesText.kept,
            ),
        ]),
        SectionLabel(
          LinesText.setAside,
          trailing: Text(
            LinesText.pastMessages(aside.fold(0, (s, l) => s + l.messages)),
            style: muted,
          ),
        ),
        card([
          for (final l in aside)
            row(
              l.label,
              l.lastAt == null ? '' : 'Last message ${lineDate(l.lastAt!)}',
              'Not tracked',
            ),
        ]),
        const SizedBox(height: 8),
        Text(LinesText.quickNote, style: muted),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('lines-quick-keep'),
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  await ref.read(mpesaLineRoutingProvider).keepTwoMostRecent();
                  if (context.mounted) Navigator.of(context).pop();
                },
          child: const Text(LinesText.keepThese),
        ),
      ],
    );
  }
}

/// Opens the sheet of line [lineId].
Future<void> showLineSheet(BuildContext context, String lineId) =>
    showAppSheet<void>(
      context: context,
      builder: (_) => LineSheet(lineId: lineId),
    );

enum _Is { main, second, same, dont }

/// One line: its name, where its money goes, and what it is: the main
/// line, the second, the same line as another, or not tracked.
class LineSheet extends ConsumerStatefulWidget {
  const LineSheet({required this.lineId, super.key});

  final String lineId;

  @override
  ConsumerState<LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends ConsumerState<LineSheet> {
  TextEditingController? _name;
  String? _destination;
  _Is? _is;
  var _delete = false;
  String? _target;
  var _saving = false;
  var _started = false;

  /// How many records the line has, once counted.
  int? _records;

  @override
  void dispose() {
    _name?.dispose();
    super.dispose();
  }

  void _start(MpesaLines lines, MpesaLine line) {
    if (_started) return;
    _started = true;
    ref.read(mpesaLineRoutingProvider).recordCount(line.id).then((n) {
      if (mounted) setState(() => _records = n);
    });
    _name = TextEditingController(text: line.name ?? '');
    _destination = destinationOf(line);
    _is = !line.tracked
        ? _Is.dont
        : switch (lines.roleOf(line.id)) {
            LineRole.main => _Is.main,
            LineRole.second => _Is.second,
            null => null,
          };
  }

  Future<void> _save(MpesaLines lines, MpesaLine line) async {
    final routing = ref.read(mpesaLineRoutingProvider);
    final navigator = Navigator.of(context);
    final name = _name!.text;
    if (_is == _Is.dont && _delete) {
      final count = _records ?? await routing.recordCount(line.id);
      if (!mounted) return;
      final yes = await confirmDelete(
        context,
        title: LinesText.deleteQuestion(line.label, count),
        body: LinesText.deleteBody(_withUnit(context, line)),
      );
      if (!yes) return;
    }
    if (_is == _Is.same) {
      final into = lines.line(_target ?? '');
      if (into == null) return;
      final newerIsInto = (into.lastAt ?? DateTime(0)).isAfter(
        line.lastAt ?? DateTime(0),
      );
      final (newer, older) = newerIsInto ? (into, line) : (line, into);
      if (!mounted) return;
      final yes = await showAdaptiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: const Text(LinesText.mergeQuestion),
          content: Text(
            LinesText.mergeBody(
              from: line.label,
              into: into.label,
              messages: line.messages + into.messages,
              newer: newer.label,
              newerBalance: _withUnit(context, newer),
              older: older.label,
              olderBalance: _balance(context, older),
            ),
          ),
          actions: [
            DialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            DialogAction(
              key: const Key('line-merge-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(LinesText.merge),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    setState(() => _saving = true);
    // Name and space first, so a merged or untracked line keeps them.
    if (name != (line.name ?? '') || _destination != destinationOf(line)) {
      if (lines.split) {
        await routing.choose(line.id, settingFor(_destination!, name));
      } else {
        await ref
            .read(mpesaLinesProvider.notifier)
            .apply((l) => l.withChoice(line.id, name: name));
      }
    }
    switch (_is) {
      case _Is.main:
        await routing.setRole(line.id, LineRole.main);
      case _Is.second:
        await routing.setRole(line.id, LineRole.second);
      case _Is.dont:
        if (line.tracked || _delete) {
          await routing.untrack(line.id, deleteRecords: _delete);
        }
      case _Is.same:
        await routing.merge(line.id, _target!);
      case null:
    }
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final lines = ref.watch(mpesaLinesProvider).value ?? MpesaLines.empty;
    final line = lines.line(widget.lineId);
    if (line == null) return const SizedBox.shrink();
    _start(lines, line);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final spaces = ref.watch(spacesProvider).value ?? const [Space.personal];
    final last = line.lastAt;
    final subtitle = [
      if (last != null) 'Last message ${lineWhen(last, today)}',
      '${countLabel(line.messages)} messages',
      'balance ${_balance(context, line)}',
      if (line.firstAt != null) 'since ${lineDate(line.firstAt!)}',
    ].join(' · ');
    final targets = [
      for (final l in lines.newestFirst)
        if (l.id != line.id && l.tracked) l,
    ];
    final narrowed = _is == _Is.same || _is == _Is.dont;
    String? hint(_Is c, String full, [String? picked]) {
      if (_is == c) return picked ?? full;
      return narrowed ? null : full;
    }

    LinePick pick(_Is c, String title, String full, [String? picked]) =>
        LinePick(
          key: Key('line-is-${c.name}'),
          title: title,
          hint: hint(c, full, picked),
          chosen: _is == c,
          onTap: () => setState(() => _is = c),
        );

    final rows = <Widget>[
      pick(_Is.main, LinesText.mainLine, LinesText.mainHint),
      pick(_Is.second, LinesText.secondLine, LinesText.secondHint),
      pick(
        _Is.same,
        LinesText.sameLine,
        LinesText.sameHint,
        LinesText.samePick,
      ),
      if (_is == _Is.same)
        for (final t in targets)
          LinePick(
            key: Key('line-same-${t.id}'),
            title: t.label,
            hint: t.firstAt == null ? null : 'Since ${lineDate(t.firstAt!)}',
            chosen: _target == t.id,
            indent: true,
            onTap: () => setState(() => _target = t.id),
          ),
      pick(
        _Is.dont,
        LinesText.dontTrack,
        LinesText.dontHint,
        LinesText.dontPicked,
      ),
      if (_is == _Is.dont) ...[
        LinePick(
          key: const Key('line-keep-records'),
          title: LinesText.keep,
          hint: LinesText.keepHint(line.label, _balance(context, line)),
          chosen: !_delete,
          indent: true,
          onTap: () => setState(() => _delete = false),
        ),
        LinePick(
          key: const Key('line-delete-records'),
          title: LinesText.delete,
          hint: LinesText.deleteHint(_records ?? line.messages),
          chosen: _delete,
          indent: true,
          onTap: () => setState(() => _delete = true),
        ),
      ],
    ];
    final target = lines.line(_target ?? '');
    final (label, ready) = switch (_is) {
      _Is.dont when line.tracked || _delete => (
        LinesText.stop(line.label),
        true,
      ),
      _Is.same => (
        target == null ? LinesText.merge : LinesText.mergeInto(target.label),
        target != null,
      ),
      _ => ('Save', true),
    };
    return SheetBody(
      title: line.label,
      subtitle: subtitle,
      children: [
        LabeledField(
          label: 'Name',
          child: TextField(
            key: const Key('line-name'),
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 30,
            decoration: const InputDecoration(
              hintText: LinesText.nameHint,
              counterText: '',
            ),
          ),
        ),
        if (lines.split) ...[
          const SizedBox(height: 12),
          ExcludeSemantics(
            child: Text(
              LinesText.whereMoneyGoes,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 6),
          ChoiceMenu<String>(
            key: const Key('line-space'),
            name: 'Where ${line.label} money goes',
            expand: true,
            value: _destination!,
            options: lineDestinations(spaces),
            itemKey: (d) => Key('line-space-$d'),
            onChanged: (d) => setState(() => _destination = d),
          ),
        ],
        const SectionLabel(LinesText.thisLineIs),
        Card(
          child: Column(
            children: [
              for (final (i, r) in rows.indexed) ...[
                if (i > 0) const Divider(height: 1),
                r,
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('line-save'),
          onPressed: _saving || !ready ? null : () => _save(lines, line),
          child: Text(label),
        ),
      ],
    );
  }
}
