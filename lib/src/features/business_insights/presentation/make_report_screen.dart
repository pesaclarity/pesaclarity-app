import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../domain/books/business_report.dart';
import '../../../domain/books/report_setup.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../theme/pesa_colors.dart';
import '../../spaces/application/spaces_providers.dart';
import '../application/report_maker.dart';
import 'business_insights_screen.dart';

/// Make a report: who it is for, the period, what goes in, the cover, its
/// style, and a name to make it again in one tap.
class MakeReportScreen extends ConsumerStatefulWidget {
  const MakeReportScreen({super.key});

  @override
  ConsumerState<MakeReportScreen> createState() => _MakeReportScreenState();
}

class _MakeReportScreenState extends ConsumerState<MakeReportScreen> {
  var _audience = ReportAudience.sacco;
  late ReportRange? _range = ref.read(insightsRangeProvider);
  ReportPeriod? _dates;
  late Set<ReportSection> _sections = {..._audience.sections};
  late ReportDetail _detail = _audience.detail;
  var _style = const ReportStyle();
  String? _name;
  var _busy = false;

  CalendarDate get _today => CalendarDate.local(ref.read(clockProvider)());

  ReportPeriod get _period =>
      _dates ?? periodFor(_range ?? ReportRange.lastMonth, _today);

  void _use(ReportSetup s) => setState(() {
    _audience = s.audience;
    _sections = {...s.sections};
    _detail = s.detail;
    _style = s.style;
    _range = s.range;
    _dates = s.range == null ? s.periodOn(_today) : null;
    _name = s.name;
  });

  Future<void> _pickDates() async {
    final today = _today;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year, today.month, today.day),
      initialDateRange: DateTimeRange(
        start: DateTime(
          _period.from.year,
          _period.from.month,
          _period.from.day,
        ),
        end: DateTime(
          _period.lastDay.year,
          _period.lastDay.month,
          _period.lastDay.day,
        ),
      ),
    );
    if (picked == null) return;
    final from = CalendarDate(
      picked.start.year,
      picked.start.month,
      picked.start.day,
    );
    final last = CalendarDate(
      picked.end.year,
      picked.end.month,
      picked.end.day,
    );
    setState(() {
      _range = null;
      _dates = ReportPeriod(from, last.addDays(1), 'Dates');
    });
  }

  Future<void> _editCover(ReportSettings settings) async {
    final space = ref.read(activeSpaceProvider).name;
    final cover = await showDialog<ReportCover>(
      context: context,
      builder: (context) => _CoverDialog(cover: settings.cover, space: space),
    );
    if (cover == null) return;
    await ref
        .read(reportSettingsProvider.notifier)
        .save(settings.copyWith(cover: cover));
  }

  Future<void> _editStyle() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _StyleSheet(
      style: _style,
      onChanged: (s) => setState(() => _style = s),
    ),
  );

  Future<void> _save(ReportSettings settings) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(initial: _name ?? _suggestedName()),
    );
    if (name == null || name.trim().isEmpty) return;
    final dates = _dates;
    await ref
        .read(reportSettingsProvider.notifier)
        .save(
          settings.withSaved(
            ReportSetup(
              name: name.trim(),
              audience: _audience,
              sections: _sections,
              range: dates == null ? _range : null,
              from: dates?.from,
              to: dates?.to,
              detail: _detail,
              style: _style,
            ),
          ),
        );
    setState(() => _name = name.trim());
  }

  Future<void> _remove(ReportSettings settings, ReportSetup s) async {
    await ref
        .read(reportSettingsProvider.notifier)
        .save(
          settings.copyWith(
            saved: [
              for (final x in settings.saved)
                if (x.name != s.name) x,
            ],
          ),
        );
    if (_name == s.name) setState(() => _name = null);
  }

  String _suggestedName() {
    final when = switch (_range) {
      ReportRange.thisMonth || ReportRange.lastMonth => 'Monthly',
      ReportRange.threeMonths => '3-month',
      null => 'My',
    };
    return switch (_audience) {
      ReportAudience.sacco => '$when Sacco report',
      ReportAudience.accountant => '$when report for the accountant',
      ReportAudience.me => '$when report',
    };
  }

  Future<void> _make({required bool csv}) async {
    final messenger = ScaffoldMessenger.of(context);
    final previewer = ref.read(reportPreviewerProvider);
    setState(() => _busy = true);
    try {
      final maker = ref.read(reportMakerProvider);
      final doc = await maker.make(
        period: _period,
        sections: _sections,
        title: _name ?? 'Business report',
        detail: _detail,
        style: _style,
      );
      if (csv) {
        await maker.shareCsv(doc);
      } else {
        final pdf = await maker.pdf(doc);
        if (!mounted) return;
        await previewer(context, doc, pdf);
      }
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('The report was not made. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final settings = ref.watch(reportSettingsProvider).value;
    final space = ref.watch(activeSpaceProvider).name;
    TextStyle label() =>
        theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted);

    return Scaffold(
      appBar: AppBar(title: const Text('Make a report')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                if (settings.saved.isNotEmpty) ...[
                  Text('Your reports', style: label()),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in settings.saved)
                        InputChip(
                          key: Key('saved-${s.name}'),
                          label: Text(s.name),
                          selected: _name == s.name,
                          onPressed: () => _use(s),
                          onDeleted: () => _remove(settings, s),
                          deleteButtonTooltipMessage: 'Remove ${s.name}',
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                Text('Who is it for?', style: label()),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ChoiceMenu<ReportAudience>(
                    key: const Key('report-audience'),
                    name: 'Who is it for',
                    options: [
                      for (final a in ReportAudience.values) (a, a.label),
                    ],
                    value: _audience,
                    itemKey: (a) => Key('audience-${a.name}'),
                    onChanged: (a) => setState(() {
                      _audience = a;
                      _sections = {...a.sections};
                      _detail = a.detail;
                    }),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Period', style: label()),
                const SizedBox(height: 8),
                RangeMenu(
                  selected: _range,
                  custom: _dates != null,
                  onSelected: (r) => setState(() {
                    _range = r;
                    _dates = null;
                  }),
                  onCustom: _pickDates,
                ),
                const SizedBox(height: 16),
                Text('Detail', style: label()),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final d in ReportDetail.values)
                      ChoiceChip(
                        key: Key('detail-${d.name}'),
                        label: Text(d.label),
                        selected: _detail == d,
                        onSelected: (_) => setState(() => _detail = d),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, s) in ReportSection.values.indexed) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 16, endIndent: 16),
                        CheckboxListTile(
                          key: Key('section-${s.name}'),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(s.label),
                          value: _sections.contains(s),
                          onChanged: (on) => setState(() {
                            if (on ?? false) {
                              _sections.add(s);
                            } else {
                              _sections.remove(s);
                            }
                          }),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        key: const Key('report-cover'),
                        title: const Text('On the cover'),
                        subtitle: Text(settings.cover.line(space)),
                        trailing: Text(
                          'Edit',
                          style: TextStyle(color: colors.link),
                        ),
                        onTap: () => _editCover(settings),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        key: const Key('report-style'),
                        title: const Text('Style'),
                        subtitle: Text(_style.summary),
                        trailing: Text(
                          'Change',
                          style: TextStyle(color: colors.link),
                        ),
                        onTap: _editStyle,
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        key: const Key('report-save'),
                        title: const Text('Saved as'),
                        subtitle: Text(
                          _name ?? 'Save it to make it again in one tap',
                        ),
                        trailing: Text(
                          _name == null ? 'Save' : 'Rename',
                          style: TextStyle(color: colors.link),
                        ),
                        onTap: () => _save(settings),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        key: const Key('report-preview'),
                        onPressed: _busy || _sections.isEmpty
                            ? null
                            : () => _make(csv: false),
                        child: const Text('Preview PDF'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      key: const Key('report-csv'),
                      onPressed: _busy || _sections.isEmpty
                          ? null
                          : () => _make(csv: true),
                      child: const Text('CSV'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _CoverDialog extends StatefulWidget {
  const _CoverDialog({required this.cover, required this.space});

  final ReportCover cover;
  final String space;

  @override
  State<_CoverDialog> createState() => _CoverDialogState();
}

class _CoverDialogState extends State<_CoverDialog> {
  late final _business = TextEditingController(
    text: widget.cover.business ?? widget.space,
  );
  late final _owner = TextEditingController(text: widget.cover.owner ?? '');
  late final _phone = TextEditingController(text: widget.cover.phone ?? '');
  late final _place = TextEditingController(text: widget.cover.place ?? '');
  late final _permit = TextEditingController(text: widget.cover.permit ?? '');

  @override
  void dispose() {
    for (final c in [_business, _owner, _phone, _place, _permit]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('On the cover'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('cover-business'),
            controller: _business,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Business name'),
          ),
          TextField(
            key: const Key('cover-owner'),
            controller: _owner,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Your name'),
          ),
          TextField(
            key: const Key('cover-phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone'),
          ),
          TextField(
            key: const Key('cover-place'),
            controller: _place,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Place'),
          ),
          TextField(
            key: const Key('cover-permit'),
            controller: _permit,
            decoration: const InputDecoration(
              labelText: 'Business permit number',
              helperText: 'Shows when the style asks for it',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: const Key('cover-save'),
        onPressed: () => Navigator.of(context).pop(
          ReportCover(
            business: _text(_business) == widget.space
                ? null
                : _text(_business),
            owner: _text(_owner),
            phone: _text(_phone),
            place: _text(_place),
            permit: _text(_permit),
          ),
        ),
        child: const Text('Save'),
      ),
    ],
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save this report'),
    content: TextField(
      key: const Key('report-name'),
      controller: _name,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(labelText: 'Name'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: const Key('report-name-save'),
        onPressed: () => Navigator.of(context).pop(_name.text),
        child: const Text('Save'),
      ),
    ],
  );
}

/// How the report looks: cover, colour, length, words and what else goes
/// on it. Each change shows at once.
class _StyleSheet extends StatefulWidget {
  const _StyleSheet({required this.style, required this.onChanged});

  final ReportStyle style;
  final ValueChanged<ReportStyle> onChanged;

  @override
  State<_StyleSheet> createState() => _StyleSheetState();
}

class _StyleSheetState extends State<_StyleSheet> {
  late var _style = widget.style;

  void _set(ReportStyle s) {
    setState(() => _style = s);
    widget.onChanged(s);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final label = theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted);
    // A drop-down keyed `style-<title>` for more than two choices, else
    // chips. Each choice is keyed `style-<title>-<name>`.
    Widget choice<T extends Enum>(
      String title,
      List<T> values,
      T selected,
      String Function(T) name,
      ReportStyle Function(T) pick,
    ) {
      final id = 'style-${title.toLowerCase()}';
      Key rowKey(T v) => Key('$id-${v.name}');
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: label),
            const SizedBox(height: 8),
            if (values.length > 2)
              ChoiceMenu<T>(
                key: Key(id),
                name: title,
                options: [for (final v in values) (v, name(v))],
                value: selected,
                itemKey: rowKey,
                onChanged: (v) => _set(pick(v)),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in values)
                    ChoiceChip(
                      key: rowKey(v),
                      label: Text(name(v)),
                      selected: v == selected,
                      onSelected: (_) => _set(pick(v)),
                    ),
                ],
              ),
          ],
        ),
      );
    }

    Widget toggle(
      String key,
      String title,
      bool value,
      ReportStyle Function(bool) pick, {
      String? subtitle,
    }) => SwitchListTile(
      key: Key('style-$key'),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: value,
      onChanged: (on) => _set(pick(on)),
    );

    final s = _style;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('Style', style: theme.textTheme.titleLarge),
            ),
            choice(
              'Cover',
              ReportCoverStyle.values,
              s.cover,
              (v) => v.label,
              (v) => s.copyWith(cover: v),
            ),
            choice(
              'Colour',
              ReportColour.values,
              s.colour,
              (v) => v.label,
              (v) => s.copyWith(colour: v),
            ),
            choice(
              'Length',
              ReportLength.values,
              s.length,
              (v) => v.label,
              (v) => s.copyWith(length: v),
            ),
            choice(
              'Words',
              ReportWording.values,
              s.wording,
              (v) => v.label,
              (v) => s.copyWith(wording: v),
            ),
            toggle(
              'compare',
              'Compare with the period before',
              s.compare,
              (on) => s.copyWith(compare: on),
            ),
            toggle(
              'charts',
              'Add charts',
              s.charts,
              (on) => s.copyWith(charts: on),
              subtitle: 'How people paid, sales by day and profit by month',
            ),
            toggle(
              'signature',
              'A line to sign',
              s.signature,
              (on) => s.copyWith(signature: on),
            ),
            toggle(
              'kraPin',
              'KRA PIN on the cover',
              s.kraPin,
              (on) => s.copyWith(kraPin: on),
              subtitle: 'From Receipts and invoices',
            ),
            toggle(
              'permit',
              'Business permit on the cover',
              s.permit,
              (on) => s.copyWith(permit: on),
              subtitle: 'Add the number under On the cover',
            ),
            toggle(
              'branding',
              'Made with Pesa Clarity, at the foot',
              s.branding,
              (on) => s.copyWith(branding: on),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton(
                key: const Key('style-done'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
