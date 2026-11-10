import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../data/repositories/tax_repository.dart';
import '../../../domain/books/business_report.dart' show periodText;
import '../../../domain/books/business_report.dart' as report;
import '../../../domain/tax/tax_estimate.dart';
import '../../../domain/tax/tax_pack.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/hero_figure_card.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/tax_providers.dart';

/// Tax: what the business may owe, as an estimate from its records and the
/// tax pack in this app version.
class TaxScreen extends ConsumerWidget {
  const TaxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(taxViewProvider);
    final view = loaded.value;
    final hidden = AmountsHidden.of(context);
    String plain(int minor) =>
        moneyOrHidden(minor, hidden: hidden, withCurrency: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Tax')),
      body: view == null
          ? loaded.hasError
                ? ErrorView(
                    'Your tax estimate could not load.',
                    onRetry: () => ref.invalidate(taxViewProvider),
                  )
                : const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                ...switch (view.kind) {
                  TaxKind.incomeTax => _incomeTax(context, view, plain),
                  TaxKind.turnover => _turnover(context, view, plain),
                  TaxKind.belowTurnover => _below(context, view, plain),
                },
                ..._monthByMonth(context, view, plain),
                const SizedBox(height: 12),
                _Settings(view),
                const SizedBox(height: 12),
                Text(
                  'Estimates from the tax pack in this app version, rules as '
                  'of ${_date(view.pack.rulesAsOf)}. Check with KRA or a tax '
                  'adviser before you file.',
                  key: const Key('tax-footer'),
                  style: Theme.of(context).textTheme.bodySmall!
                      .copyWith(color: PesaColors.of(context).textMuted),
                ),
              ],
            ),
    );
  }

  List<Widget> _incomeTax(
    BuildContext context,
    TaxView view,
    String Function(int) plain,
  ) {
    final colors = PesaColors.of(context);
    final e = view.income;
    final f = e.figures;
    final count = view.withheld.length;
    final toCollect = view.certificatesToCollect;
    final missing = view.withheld.where((w) => w.certificate == null).length;
    final through = view.today.month == 1
        ? 'January'
        : 'Jan to ${monthName(view.today.yearMonth).substring(0, 3)}';
    return [
      HeroFigureCard(
        key: const Key('tax-owed'),
        label: 'Tax you may still owe for ${e.year}',
        figure: '${BaseCurrency.code} ${plain(e.leftMinor)}',
        caption: 'An estimate, for income to date',
      ),
      const SizedBox(height: 12),
      GroupedSection(
        children: [
          LabelValueRow(
            label: view.services ? 'Fees earned' : 'Sales',
            value: plain(f.incomeMinor),
            detail: through,
          ),
          LabelValueRow(
            label: 'Costs',
            value: _minus(plain, f.costsMinor),
            detail: f.costNames.isEmpty ? null : f.costNames.join(', '),
          ),
          LabelValueRow(label: 'Profit', value: _signed(plain, f.profitMinor)),
          LabelValueRow(
            label: 'Income tax on profit',
            value: plain(e.taxMinor),
            detail: e.company
                ? 'Company rate, from the tax pack'
                : 'Individual rates and relief, from the tax pack',
          ),
        ],
      ),
      const SizedBox(height: 12),
      GroupedSection(
        children: [
          LabelValueRow(
            label: 'Withheld by clients',
            value: _minus(plain, f.withheldMinor),
            key: const Key('tax-withheld'),
            detail: count == 0
                ? 'When a client keeps back ${rateText(view.pack.withholdingRate)}'
                : [
                    count == 1 ? '1 payment' : '$count payments',
                    if (missing > 0)
                      missing == 1
                          ? '1 certificate to collect'
                          : '$missing certificates to collect',
                  ].join(' · '),
            onTap: count == 0
                ? null
                : () => showAppSheet<void>(
                    context: context,
                    builder: (_) => const _CertificatesSheet(),
                  ),
          ),
          LabelValueRow(
            label: 'Paid to KRA',
            value: _minus(plain, f.paidToKraMinor),
            detail: 'From your KRA payment messages',
          ),
          LabelValueRow(
            label: 'Left to pay',
            value: plain(e.leftMinor),
            strong: true,
            valueColor: e.leftMinor > 0 ? colors.warning : colors.successText,
          ),
        ],
      ),
      if (view.costsCount > 0) ...[
        const SizedBox(height: 12),
        GroupedSection(
          children: [
            LabelValueRow(
              label: 'Costs with an eTIMS invoice',
              value: '${view.etimsCount} of ${view.costsCount}',
              key: const Key('tax-etims'),
              detail: 'This year. Mark them on each cost in Money',
            ),
          ],
        ),
      ],
      ..._sentences(context, [
        if (view.etimsCount < view.costsCount)
          'KRA asks for an eTIMS invoice for a cost to count against income '
              'tax. Mark the costs that have one.',
        if (view.setAsideMinor case final aside? when e.leftMinor > 0)
          aside >= e.leftMinor
              ? 'What you set aside, ${plain(aside)}, covers what is left to '
                    'pay.'
              : 'What you set aside, ${plain(aside)}, is '
                    '${plain(e.leftMinor - aside)} short of what is left to '
                    'pay.',
        if (e.nextInstalment case final next? when e.leftMinor > 0)
          'Next instalment is due ${shortDate(next)}. Paying about '
              '${plain(e.leftMinor)} by then keeps you even.',
        if (e.taxMinor > 0 && e.leftMinor == 0)
          'Tax withheld and paid covers the estimate so far.',
        if (toCollect.isNotEmpty)
          'Collect certificates from ${_names(toCollect)}, so the tax they '
              'withheld counts.',
      ]),
    ];
  }

  List<Widget> _turnover(
    BuildContext context,
    TaxView view,
    String Function(int) plain,
  ) {
    final colors = PesaColors.of(context);
    final last = view.lastMonth;
    final now = view.thisMonth;
    final rate = rateText(view.pack.turnoverRate);
    final lastName = monthName(last.month);
    return [
      HeroFigureCard(
        key: const Key('tax-owed'),
        label: 'Turnover Tax you may owe',
        figure: '${BaseCurrency.code} ${plain(view.owedMinor)}',
        caption: 'An estimate, $rate of sales',
      ),
      const SizedBox(height: 12),
      GroupedSection(
        children: [
          LabelValueRow(
            label: 'Sales in $lastName',
            value: plain(last.salesMinor),
          ),
          LabelValueRow(
            label: 'Turnover Tax ($rate)',
            value: plain(last.taxMinor),
          ),
          LabelValueRow(
            label: 'Paid to KRA',
            value: _minus(plain, last.paidMinor),
            detail:
                'From your KRA payment messages since '
                '${shortDate(now.month.firstDay)}',
          ),
          LabelValueRow(
            label: 'Left to pay for $lastName',
            value: plain(last.leftMinor),
            detail: 'Due ${shortDate(last.due)}',
            strong: true,
            valueColor: last.leftMinor > 0
                ? colors.warning
                : colors.successText,
          ),
        ],
      ),
      const SizedBox(height: 12),
      GroupedSection(
        children: [
          LabelValueRow(
            label: 'Sales this month',
            value: plain(now.salesMinor),
            detail: periodText(
              report.ReportPeriod(
                now.month.firstDay,
                view.today.addDays(1),
                '',
              ),
              thisYear: view.today.year,
            ),
          ),
          LabelValueRow(
            label: 'Turnover Tax so far',
            value: plain(now.taxMinor),
            detail: 'Due ${shortDate(now.due)}',
          ),
        ],
      ),
      ..._sentences(context, [
        'Sales over the last 12 months are ${plain(view.yearSalesMinor)}, '
            'inside the Turnover Tax band of '
            '${plain(view.pack.turnoverFromMinor)} to '
            '${plain(view.pack.turnoverUpToMinor)}.',
        ?thresholdWarning(
          view.pack,
          yearSalesMinor: view.yearSalesMinor,
          settings: view.settings,
          plain: plain,
        ),
      ]),
    ];
  }

  List<Widget> _below(
    BuildContext context,
    TaxView view,
    String Function(int) plain,
  ) => [
    HeroFigureCard(
      key: const Key('tax-owed'),
      label: 'Turnover Tax',
      figure: '${BaseCurrency.code} ${plain(0)}',
      caption: 'Sales are below the Turnover Tax band',
    ),
    ..._sentences(context, [
      'Sales over the last 12 months are ${plain(view.yearSalesMinor)}. '
          'Turnover Tax starts at ${plain(view.pack.turnoverFromMinor)} a '
          'year, at ${rateText(view.pack.turnoverRate)} of sales.',
    ]),
  ];

  List<Widget> _monthByMonth(
    BuildContext context,
    TaxView view,
    String Function(int) plain,
  ) {
    if (view.months.isEmpty) return const [];
    return [
      const SectionLabel('Month by month'),
      GroupedSection(
        children: [
          for (final m in view.months.reversed)
            LabelValueRow(
              label:
                  '${monthName(m.month)} ${m.month.year == view.today.year ? '' : m.month.year}'
                      .trim(),
              value: plain(m.estimatedMinor),
              key: Key('tax-month-${m.month}'),
              detail: switch (m.paidMinor) {
                null => 'An estimate, not due yet',
                final paid when paid >= m.estimatedMinor && paid > 0 =>
                  'Paid ${plain(paid)}',
                0 => 'An estimate, nothing paid',
                final paid => 'Paid ${plain(paid)}',
              },
            ),
        ],
      ),
    ];
  }

  static String _minus(String Function(int) plain, int minor) =>
      minor == 0 ? plain(0) : '-${plain(minor)}';

  static String _signed(String Function(int) plain, int minor) =>
      minor < 0 ? '-${plain(-minor)}' : plain(minor);

  static String _names(List<String> names) => names.length == 1
      ? names.single
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

  static String _date(CalendarDate d) =>
      periodText(report.ReportPeriod(d, d.addDays(1), ''));

  List<Widget> _sentences(BuildContext context, List<String> lines) {
    if (lines.isEmpty) return const [];
    final theme = Theme.of(context);
    return [
      const SizedBox(height: 12),
      Card(
        key: const Key('tax-sentences'),
        child: Padding(
          padding: const EdgeInsets.all(Layout.cardPadding),
          child: Column(
            children: [
              for (final (i, l) in lines.indexed) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: EdgeInsets.only(
                    top: i > 0 ? 12 : 0,
                    bottom: i < lines.length - 1 ? 12 : 0,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6, right: 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Text(l, style: theme.textTheme.bodyLarge),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }
}

class _Settings extends ConsumerWidget {
  const _Settings(this.view);

  final TaxView view;

  TaxSettings get settings => view.settings;

  Future<void> _save(WidgetRef ref, TaxSettings next) =>
      ref.read(taxSettingsProvider.notifier).save(next);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    final shares = {
      view.suggestedShare,
      150,
      300,
      500,
      1000,
      1500,
      2000,
      3000,
    }.toList()..sort();
    return Card(
      child: Column(
        children: [
          ListTile(
            title: const Text('You file as'),
            subtitle: Text('Changes the rates used', style: muted),
            trailing: ChoiceMenu<bool>(
              key: const Key('tax-file-as'),
              name: 'You file as',
              options: const [(false, 'Individual'), (true, 'Company')],
              value: settings.company,
              itemKey: (company) =>
                  Key('file-as-${company ? 'Company' : 'Individual'}'),
              onChanged: (company) =>
                  _save(ref, settings.copyWith(company: company)),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile.adaptive(
            key: const Key('tax-set-aside'),
            title: const Text('Set aside for tax'),
            subtitle: Text(switch (settings.setAside) {
              null => 'Keep ${rateText(view.suggestedShare)} of money in aside',
              final rate =>
                '${rateText(rate)} of money in · '
                    '${shownMoney(context, view.setAsideMinor ?? 0, withCurrency: false)} '
                    'this year',
            }, style: muted),
            value: settings.setAside != null,
            onChanged: (on) => _save(
              ref,
              settings.copyWith(
                setAside: () => on ? view.suggestedShare : null,
              ),
            ),
          ),
          if (settings.setAside case final rate?)
            ListTile(
              title: const Text('Share kept aside'),
              subtitle: Text(
                'Your records suggest ${rateText(view.suggestedShare)}',
                style: muted,
              ),
              trailing: ChoiceMenu<int>(
                key: const Key('tax-set-aside-share'),
                name: 'Share kept aside',
                options: [for (final share in shares) (share, rateText(share))],
                value: rate,
                itemKey: (share) => Key('set-aside-$share'),
                onChanged: (share) =>
                    _save(ref, settings.copyWith(setAside: () => share)),
              ),
            ),
          const Divider(height: 1),
          SwitchListTile.adaptive(
            key: const Key('tax-vat'),
            title: const Text('VAT registered'),
            value: settings.vatRegistered,
            onChanged: (on) => _save(ref, settings.copyWith(vatRegistered: on)),
          ),
        ],
      ),
    );
  }
}

/// What each client withheld, with its certificate number to add.
class _CertificatesSheet extends ConsumerWidget {
  const _CertificatesSheet();

  Future<void> _edit(BuildContext context, WidgetRef ref, Withheld w) async {
    final number = await showAdaptiveDialog<String>(
      context: context,
      builder: (context) => _CertificateDialog(w),
    );
    if (number == null) return;
    await ref.read(taxRepositoryProvider).setCertificate(w.id, number);
    ref.invalidate(taxViewProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final view = ref.watch(taxViewProvider).value;
    final withheld = view?.withheld ?? const <Withheld>[];
    String plain(int minor) => shownMoney(context, minor, withCurrency: false);
    return SheetBody(
      title: 'Withheld by clients',
      children: [
        for (final w in withheld.reversed)
          ListTile(
            key: Key('withheld-${w.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text('${w.person} · ${plain(w.amountMinor)}'),
            subtitle: Text(
              w.certificate == null
                  ? '${shortDate(CalendarDate.local(w.at))} · add the '
                        'certificate number'
                  : '${shortDate(CalendarDate.local(w.at))} · '
                        'certificate ${w.certificate}',
              style: theme.textTheme.bodySmall!.copyWith(
                color: colors.textMuted,
              ),
            ),
            trailing: TrailingLink(w.certificate == null ? 'Add' : 'Edit'),
            onTap: () => _edit(context, ref, w),
          ),
      ],
    );
  }
}

class _CertificateDialog extends StatefulWidget {
  const _CertificateDialog(this.withheld);

  final Withheld withheld;

  @override
  State<_CertificateDialog> createState() => _CertificateDialogState();
}

class _CertificateDialogState extends State<_CertificateDialog> {
  late final _number = TextEditingController(
    text: widget.withheld.certificate ?? '',
  );

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    title: Text('Certificate from ${widget.withheld.person}'),
    content: TextField(
      key: const Key('certificate-number'),
      controller: _number,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Certificate number'),
    ),
    actions: [
      DialogAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      DialogAction(
        key: const Key('certificate-save'),
        onPressed: () => Navigator.pop(context, _number.text),
        child: const Text('Save'),
      ),
    ],
  );
}
