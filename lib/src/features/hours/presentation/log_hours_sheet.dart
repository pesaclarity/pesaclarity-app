import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/hours_repository.dart';
import '../../../domain/hours/hours.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/pesa_colors.dart';
import '../application/hours_providers.dart';

/// Log hours for a client, or edit [entry]. Starts on [day].
Future<void> showLogHoursSheet(
  BuildContext context, {
  HourEntry? entry,
  CalendarDate? day,
}) => showAppSheet<void>(
  context: context,
  builder: (context) => _LogHours(entry: entry, day: day),
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
  final _form = GlobalKey<FormState>();

  /// Whether Save was tapped with something missing, so the fields show
  /// what to fix as they change.
  var _checked = false;

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
    if (!_form.currentState!.validate() || minutes == null) {
      setState(() => _checked = true);
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
          _checked = false;
          _what.clear();
          _hours.clear();
          // The rate just used is the one saved for this client now.
          if (rate != null) {
            _savedRate = rate;
            _rate.clear();
            _editRate = false;
          }
        });
        if (mounted) showNote(context, '${hoursText(minutes)} h logged.');
      } else {
        navigator.pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final entry = widget.entry!;
    final navigator = Navigator.of(context);
    final yes = await confirmDelete(
      context,
      title: 'Delete these hours?',
      body:
          'This takes ${hoursText(entry.minutes)} h off '
          '${weekdayName(entry.day)} ${shortDate(entry.day)}.',
    );
    if (!yes) return;
    await ref.read(hoursRepositoryProvider).remove(entry.id);
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

    return Form(
      key: _form,
      autovalidateMode: _checked
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: SheetBody(
        title: widget.entry == null ? 'Log hours' : 'Edit hours',
        children: [
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
                  validator: (t) => (t ?? '').trim().isEmpty
                      ? 'Enter the client, such as Bidii Traders Ltd.'
                      : null,
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
          TextFormField(
            key: const Key('hours-what'),
            controller: _what,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'What you did'),
            validator: (t) => (t ?? '').trim().isEmpty
                ? 'Enter what you did, such as Design review.'
                : null,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DateField(
                  key: const Key('hours-day'),
                  label: 'Day',
                  value: _day,
                  firstDate: CalendarDate(today.year - 2, 1, 1),
                  lastDate: CalendarDate(today.year + 1, 1, 1),
                  onChanged: (d) {
                    if (d != null) setState(() => _day = d);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const Key('hours-hours'),
                  controller: _hours,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Hours',
                    hintText: '1.5',
                  ),
                  validator: (t) => minutesFrom(t ?? '') == null
                      ? 'Enter the hours, such as 1.5.'
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            key: const Key('hours-bill'),
            contentPadding: EdgeInsets.zero,
            value: _bill,
            onChanged: (on) => setState(() => _bill = on),
            title: const Text('Bill this to the client'),
          ),
          if (_bill && _savedRate != null && !_editRate)
            ListTile(
              key: const Key('hours-change-rate'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                'At ${_plain(_savedRate!)} an hour, saved for '
                '${client.isEmpty ? 'this client' : client}',
                style: theme.textTheme.bodySmall!.copyWith(
                  color: colors.textMuted,
                ),
              ),
              trailing: const TrailingLink('Change'),
              onTap: () => setState(() => _editRate = true),
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
            SwitchListTile.adaptive(
              key: const Key('hours-another'),
              contentPadding: EdgeInsets.zero,
              value: _another,
              onChanged: (on) => setState(() => _another = on),
              title: const Text('Log another for the same day'),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('hours-save'),
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
          if (widget.entry != null) ...[
            const SizedBox(height: 8),
            TextButton(
              key: const Key('hours-remove'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: _delete,
              child: const Text('Delete these hours'),
            ),
          ],
        ],
      ),
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
    this.validator,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final List<String> options;
  final VoidCallback? onChanged;
  final FormFieldValidator<String>? validator;

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
    fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
      controller: controller,
      focusNode: focus,
      textCapitalization: TextCapitalization.words,
      onChanged: (_) => onChanged?.call(),
      validator: widget.validator,
      decoration: InputDecoration(labelText: label),
    ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        color: Theme.of(context).colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: PesaColors.of(context).border),
        ),
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
