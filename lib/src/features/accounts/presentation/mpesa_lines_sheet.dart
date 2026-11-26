import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/database/database_providers.dart';
import '../../../domain/accounts/mpesa_lines.dart';
import '../../../domain/spaces/space.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/pesa_colors.dart';
import '../../sms/presentation/read_again_card.dart' show countLabel;
import '../../spaces/application/spaces_providers.dart';
import '../application/mpesa_lines_providers.dart';

/// Opens "Two M-Pesa lines" to split the lines read as one, or, once they
/// are split, "M-Pesa lines" to rename one or move it to another space.
Future<void> showMpesaLinesSheet(BuildContext context) => showAppSheet<void>(
  context: context,
  builder: (_) => const MpesaLinesSheet(),
);

/// `Balance 12,500 · 268 messages`.
String lineFacts(BuildContext context, MpesaLine line) => [
  if (line.balanceMinor != null)
    'Balance ${shownMoney(context, line.balanceMinor!, withCurrency: false)}',
  '${countLabel(line.messages)} ${line.messages == 1 ? 'message' : 'messages'}',
].join(' · ');

/// Where a line's money can go, from the open space: each other space,
/// Personal, and Both (Personal reads it and the business asks), as in
/// Business or personal. A choice is a space id, or `both:` and a
/// business's id.
List<(String, String)> lineDestinations(List<Space> spaces) {
  final businesses = [
    for (final s in spaces)
      if (s.kind == SpaceKind.business) s,
  ];
  return [
    for (final s in spaces)
      if (s.id != personalSpaceId) (s.id, s.name),
    (personalSpaceId, 'Personal'),
    for (final b in businesses)
      (
        'both:${b.id}',
        businesses.length == 1 ? 'Both' : 'Personal and ${b.name}',
      ),
  ];
}

/// The choice [destination] stands for, named [name].
LineSetting settingFor(String destination, String name) =>
    destination.startsWith('both:')
    ? LineSetting(
        name: name,
        spaceId: personalSpaceId,
        sharedWith: destination.substring(5),
      )
    : LineSetting(name: name, spaceId: destination);

/// Where [line] goes now, as a destination.
String destinationOf(MpesaLine line) =>
    line.sharedWith == null ? line.spaceId : 'both:${line.sharedWith}';

class MpesaLinesSheet extends ConsumerStatefulWidget {
  const MpesaLinesSheet({super.key});

  @override
  ConsumerState<MpesaLinesSheet> createState() => _MpesaLinesSheetState();
}

class _MpesaLinesSheetState extends ConsumerState<MpesaLinesSheet> {
  final _names = <String, TextEditingController>{};
  final _destinations = <String, String>{};
  var _saving = false;

  /// Whether this sheet started the split, so it shows how it goes.
  var _splitting = false;

  @override
  void dispose() {
    for (final c in _names.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, LineSetting> _settings(List<MpesaLine> lines) => {
    for (final line in lines)
      line.id: settingFor(
        _destinations[line.id] ?? destinationOf(line),
        _names[line.id]?.text ?? line.name ?? '',
      ),
  };

  Future<void> _split(List<MpesaLine> lines) async {
    setState(() => _splitting = true);
    await ref
        .read(lineSplitControllerProvider.notifier)
        .split(_settings(lines));
  }

  Future<void> _save(List<MpesaLine> lines) async {
    setState(() => _saving = true);
    final routing = ref.read(mpesaLineRoutingProvider);
    for (final MapEntry(:key, :value) in _settings(lines).entries) {
      await routing.choose(key, value);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(mpesaLinesProvider).value ?? MpesaLines.empty;
    final split = ref.watch(lineSplitControllerProvider);
    if (_splitting && split.stage == LineSplitStage.splitting) {
      return _Splitting(split);
    }
    if (_splitting && split.stage == LineSplitStage.finished) {
      return _Sorted(lines: lines);
    }
    final spaces = ref.watch(spacesProvider).value ?? const [Space.personal];
    final here = ref.watch(activeSpaceIdProvider);
    final shown = lines.shown;
    final splitting = !lines.split;
    final destinations = lineDestinations(spaces);
    return SheetBody(
      title: splitting ? 'Two M-Pesa lines' : 'M-Pesa lines',
      subtitle: splitting
          ? 'Name each line and choose its space.'
          : 'Rename a line or move it to another space.',
      children: [
        for (final line in shown) ...[
          _LineFields(
            line: line,
            name: _names[line.id] ??= TextEditingController(
              text: line.name ?? '',
            ),
            destination:
                _destinations[line.id] ??
                (splitting ? here : destinationOf(line)),
            destinations: destinations,
            onDestination: (d) => setState(() => _destinations[line.id] = d),
          ),
          const SizedBox(height: 16),
        ],
        Notice(
          splitting
              ? 'Past messages are read again into the right line. Nothing '
                    'leaves the phone.'
              : 'A line that moves takes its payments and balance with it. '
                    'Nothing leaves the phone.',
        ),
        if (split.stage == LineSplitStage.failed && _splitting) ...[
          const SizedBox(height: 12),
          const Notice(
            'The lines could not be split. Nothing was changed. Try again.',
            tone: Tone.warning,
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('mpesa-lines-save'),
          onPressed: _saving || split.stage == LineSplitStage.splitting
              ? null
              : () => splitting ? _split(shown) : _save(shown),
          child: Text(splitting ? 'Split them' : 'Save'),
        ),
      ],
    );
  }
}

class _LineFields extends StatelessWidget {
  const _LineFields({
    required this.line,
    required this.name,
    required this.destination,
    required this.destinations,
    required this.onDestination,
  });

  final MpesaLine line;
  final TextEditingController name;
  final String destination;
  final List<(String, String)> destinations;
  final ValueChanged<String> onDestination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Column(
      key: Key('mpesa-line-${line.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          children: [
            Text(line.slot, style: theme.textTheme.titleSmall),
            Text(
              lineFacts(context, line),
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LabeledField(
          label: 'Name',
          child: TextField(
            key: Key('mpesa-line-name-${line.id}'),
            controller: name,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 30,
            decoration: InputDecoration(hintText: line.slot, counterText: ''),
          ),
        ),
        const SizedBox(height: 12),
        ExcludeSemantics(
          child: Text(
            'Where its money goes',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: colors.textMuted,
            ),
          ),
        ),
        const SizedBox(height: 6),
        ChoiceMenu<String>(
          key: Key('mpesa-line-space-${line.id}'),
          name: 'Where ${line.label} money goes',
          expand: true,
          value: destination,
          options: destinations,
          itemKey: (d) => Key('mpesa-line-space-${line.id}-$d'),
          onChanged: onDestination,
        ),
      ],
    );
  }
}

class _Splitting extends StatelessWidget {
  const _Splitting(this.state);

  final LineSplitState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final total = state.total;
    final progress = total == 0
        ? 'Looking for your messages'
        : '${countLabel(state.done)} of ${countLabel(total)} messages';
    return SheetBody(
      title: 'Splitting your lines',
      children: [
        Text('Reading your messages again', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(BrandTokens.pillRadius),
          child: LinearProgressIndicator(
            value: total == 0 ? null : state.done / total,
            minHeight: 6,
            color: theme.colorScheme.onSurface,
            backgroundColor: colors.border,
            semanticsLabel: 'Reading progress',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '$progress · You can leave this screen',
          style: theme.textTheme.bodySmall!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Sorted extends ConsumerWidget {
  const _Sorted({required this.lines});

  final MpesaLines lines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final spaces = {
      for (final s in ref.watch(spacesProvider).value ?? const [Space.personal])
        s.id: s.name,
    };
    final shown = lines.lines;
    final total = shown.fold(0, (sum, l) => sum + l.messages);
    return SheetBody(
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: colors.successSoft,
              child: Icon(Icons.check, color: colors.success, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      '${countLabel(total)} messages sorted',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  Text(
                    [
                      for (final l in shown)
                        '${countLabel(l.messages)} on ${l.label}',
                    ].join(', '),
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              for (final (i, line) in shown.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  key: Key('mpesa-line-sorted-${line.id}'),
                  title: Text('M-Pesa · ${line.label}'),
                  subtitle: Text('In ${spaces[line.spaceId] ?? 'Personal'}'),
                  trailing: line.balanceMinor == null
                      ? null
                      : Text(
                          shownMoney(
                            context,
                            line.balanceMinor!,
                            withCurrency: false,
                          ),
                          style: theme.textTheme.titleMedium,
                        ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Names and categories stay. Nothing left the phone.',
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('mpesa-lines-done'),
          onPressed: () {
            ref.read(lineSplitControllerProvider.notifier).reset();
            Navigator.of(context).pop();
          },
          child: const Text('Done'),
        ),
      ],
    );
  }
}
