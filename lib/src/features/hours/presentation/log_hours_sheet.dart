import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/hours_repository.dart';
import '../../../domain/hours/hours.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart' show dayLabel;
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../theme/pesa_colors.dart';
import '../application/hours_providers.dart';

/// Log hours for a client, or change [entry]. Starts on [day].
Future<void> showLogHoursSheet(
  BuildContext context, {
  HourEntry? entry,
  CalendarDate? day,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: _LogHours(entry: entry, day: day),
      ),
    ),
  ),
);

class _LogHours extends ConsumerStatefulWidget {
  const _LogHours({this.entry, this.day});

  final HourEntry? entry;
  final CalendarDate? day;

  @override
  ConsumerState<_LogHours> createState() => _LogHoursState();
}

class _LogHoursState extends ConsumerState<_LogHours> {
  late final _client = TextEditingController(text: widget.entry?.client);
  late final _project = TextEditingController(text: widget.entry?.project);
  late final _what = TextEditingController(text: widget.entry?.what);
  late final _hours = TextEditingController(
    text: widget.entry == null ? '' : hoursText(widget.entry!.minutes),
  );
  final _rate = TextEditingController();
  late CalendarDate _day =
      widget.entry?.day ??
      widget.day ??
      CalendarDate.local(ref.read(clockProvider)());
  late bool _bill = widget.entry?.billable ?? true;
  var _another = false;
  int? _savedRate;
  var _editRate = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final rate = widget.entry?.rateMinor;
    if (rate != null) _savedRate = rate;
    _client.addListener(_findRate);
    _project.addListener(_findRate);
    if (widget.entry == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _findRate());
    }
  }

  @override
  void dispose() {
    for (final c in [_client, _project, _what, _hours, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _findRate() async {
    if (widget.entry != null) return;
    final client = _client.text.trim();
    if (client.isEmpty) {
      if (mounted) setState(() => _savedRate = null);
      return;
    }
    final rate = await ref
        .read(hoursRepositoryProvider)
        .lastRate(client, project: _project.text);
    if (mounted && client == _client.text.trim()) {
      setState(() => _savedRate = rate);
    }
  }

  String _plain(int minor) => formatMoney(Money(minor), withCurrency: false);

  Future<void> _save() async {
    final client = _client.text.trim();
    final what = _what.text.trim();
    final minutes = minutesFrom(_hours.text);
    final messenger = ScaffoldMessenger.of(context);
    if (client.isEmpty || what.isEmpty || minutes == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Add the client, what you did and the hours.'),
        ),
      );
      return;
    }
    final typed = _rate.text.trim().isEmpty
        ? null
        : AmountField.amountFrom(_rate.text);
    final rate = _bill ? (typed ?? _savedRate) : null;
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final repo = ref.read(hoursRepositoryProvider);
      final entry = widget.entry;
      if (entry == null) {
        await repo.log(
          client: client,
          project: _project.text,
          what: what,
          day: _day,
          minutes: minutes,
          billable: _bill,
          rateMinor: rate,
          at: ref.read(clockProvider)(),
        );
      } else {
        await repo.update(
          HourEntry(
            id: entry.id,
            client: client,
            project: _project.text,
            what: what,
            day: _day,
            minutes: minutes,
            billable: _bill,
            rateMinor: rate,
            invoiceId: entry.invoiceId,
          ),
        );
      }
      if (_another && widget.entry == null) {
        setState(() {
          _what.clear();
          _hours.clear();
          // The rate just used is the one saved for this client now.
          if (rate != null) {
            _savedRate = rate;
            _rate.clear();
            _editRate = false;
          }
        });
        messenger.showSnackBar(
          SnackBar(content: Text('${hoursText(minutes)} h logged.')),
        );
      } else {
        navigator.pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final navigator = Navigator.of(context);
    await ref.read(hoursRepositoryProvider).remove(widget.entry!.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final clients = ref.watch(hourClientsProvider).value ?? const {};
    final projects = [
      for (final MapEntry(:key, :value) in clients.entries)
        if (key.toLowerCase() == _client.text.trim().toLowerCase()) ...value,
    ];
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final client = _client.text.trim();
    final showRate = _bill && (_savedRate == null || _editRate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.entry == null ? 'Log hours' : 'Change hours',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Suggest(
                key: const Key('hours-client'),
                controller: _client,
                label: 'Client',
                options: clients.keys.toList(),
                onChanged: () => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Suggest(
                key: const Key('hours-project'),
                controller: _project,
                label: 'Project',
                options: projects,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('hours-what'),
          controller: _what,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'What you did'),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InkWell(
                key: const Key('hours-day'),
                onTap: () async {
                  final picked = await pickDate(
                    context,
                    initialDate: DateTime(_day.year, _day.month, _day.day),
                    firstDate: DateTime(today.year - 2),
                    lastDate: DateTime(today.year + 1),
                  );
                  if (picked == null) return;
                  setState(
                    () => _day = CalendarDate(
                      picked.year,
                      picked.month,
                      picked.day,
                    ),
                  );
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Day'),
                  child: Text(
                    '${weekdayName(_day).substring(0, 3)} '
                    '${dayLabel(_day, thisYear: today.year)}',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('hours-hours'),
                controller: _hours,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Hours',
                  hintText: '1.5',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          key: const Key('hours-bill'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _bill,
          onChanged: (on) => setState(() => _bill = on ?? false),
          title: const Text('Bill this to the client'),
          subtitle: _bill && _savedRate != null && !_editRate
              ? Text(
                  'At ${_plain(_savedRate!)} an hour, saved for '
                  '${client.isEmpty ? 'this client' : client}',
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: colors.textMuted,
                  ),
                )
              : null,
          secondary: _bill && _savedRate != null && !_editRate
              ? TextButton(
                  onPressed: () => setState(() => _editRate = true),
                  child: Text('Change', style: TextStyle(color: colors.link)),
                )
              : null,
        ),
        if (showRate)
          AmountField(
            key: const Key('hours-rate'),
            controller: _rate,
            label: 'Rate an hour',
            allowZero: true,
          ),
        if (widget.entry == null) ...[
          const Divider(height: 1),
          CheckboxListTile(
            key: const Key('hours-another'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _another,
            onChanged: (on) => setState(() => _another = on ?? false),
            title: const Text('Log another for the same day'),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('hours-save'),
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
        if (widget.entry != null)
          TextButton(
            key: const Key('hours-remove'),
            onPressed: _remove,
            child: Text(
              'Remove these hours',
              style: TextStyle(color: colors.textMuted),
            ),
          ),
      ],
    );
  }
}

/// A text field that suggests from [options] as you type.
class _Suggest extends StatefulWidget {
  const _Suggest({
    required this.controller,
    required this.label,
    required this.options,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final List<String> options;
  final VoidCallback? onChanged;

  @override
  State<_Suggest> createState() => _SuggestState();
}

class _SuggestState extends State<_Suggest> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  List<String> get options => widget.options;
  String get label => widget.label;
  VoidCallback? get onChanged => widget.onChanged;

  @override
  Widget build(BuildContext context) => RawAutocomplete<String>(
    textEditingController: widget.controller,
    focusNode: _focus,
    optionsBuilder: (value) {
      final q = value.text.trim().toLowerCase();
      if (q.isEmpty) return const [];
      return options.where(
        (o) => o.toLowerCase().contains(q) && o.toLowerCase() != q,
      );
    },
    onSelected: (_) => onChanged?.call(),
    fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
      controller: controller,
      focusNode: focus,
      textCapitalization: TextCapitalization.words,
      onChanged: (_) => onChanged?.call(),
      decoration: InputDecoration(labelText: label),
    ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 280),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (final o in options)
                ListTile(
                  dense: true,
                  title: Text(o),
                  onTap: () => onSelected(o),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
