import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/repositories/tax_repository.dart';
import '../../../domain/books/business_report.dart' show periodText;
import '../../../domain/books/business_report.dart' as report;
import '../../../domain/tax/tax_estimate.dart';
import '../../../domain/tax/tax_pack.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/hero_figure_card.dart';
import '../../../theme/pesa_colors.dart';
import '../../security/application/balance_visibility.dart';
import '../application/tax_providers.dart';

/// Tax: what the business may owe, as an estimate from its records and the
/// tax pack in this app version.
class TaxScreen extends ConsumerWidget {
  const TaxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(taxViewProvider).value;
    final hidden = ref.watch(balancesHiddenProvider);
    String plain(int minor) =>
        hidden ? maskedDigits : formatMoney(Money(minor), withCurrency: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Tax')),
      body: view == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                ...switch (view.kind) {
                  TaxKind.incomeTax => _incomeTax(context, view, plain),
                  TaxKind.turnover => _turnover(context, view, plain),
                  TaxKind.belowTurnover => _below(context, view, plain),
                },
                const SizedBox(height: 12),
                _Settings(view.settings),
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
      _card([
        _Row(
          view.services ? 'Fees earned' : 'Sales',
          plain(f.incomeMinor),
          detail: through,
        ),
        _Row(
          'Costs',
          _minus(plain, f.costsMinor),
          detail: f.costNames.isEmpty ? null : f.costNames.join(', '),
        ),
        _Row('Profit', _signed(plain, f.profitMinor)),
        _Row(
          'Income tax on profit',
          plain(e.taxMinor),
          detail: e.company
              ? 'Company rate, from the tax pack'
              : 'Individual rates and relief, from the tax pack',
        ),
      ]),
      const SizedBox(height: 12),
      _card([
        _Row(
          'Withheld by clients',
          _minus(plain, f.withheldMinor),
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
              : () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => const _CertificatesSheet(),
                ),
        ),
        _Row(
          'Paid to KRA',
          _minus(plain, f.paidToKraMinor),
          detail: 'From your KRA payment messages',
        ),
        _Row(
          'Left to pay',
          plain(e.leftMinor),
          color: e.leftMinor > 0 ? colors.warning : colors.successText,
          bold: true,
        ),
      ]),
      ..._sentences(context, [
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
      _card([
        _Row('Sales in $lastName', plain(last.salesMinor)),
        _Row('Turnover Tax ($rate)', plain(last.taxMinor)),
        _Row(
          'Paid to KRA',
          _minus(plain, last.paidMinor),
          detail:
              'From your KRA payment messages since '
              '${shortDate(now.month.firstDay)}',
        ),
        _Row(
          'Left to pay for $lastName',
          plain(last.leftMinor),
          detail: 'Due ${shortDate(last.due)}',
          color: last.leftMinor > 0 ? colors.warning : colors.successText,
          bold: true,
        ),
      ]),
      const SizedBox(height: 12),
      _card([
        _Row(
          'Sales this month',
          plain(now.salesMinor),
          detail: periodText(
            report.ReportPeriod(now.month.firstDay, view.today.addDays(1), ''),
            thisYear: view.today.year,
          ),
        ),
        _Row(
          'Turnover Tax so far',
          plain(now.taxMinor),
          detail: 'Due ${shortDate(now.due)}',
        ),
      ]),
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

  static String _minus(String Function(int) plain, int minor) =>
      minor == 0 ? plain(0) : '− ${plain(minor)}';

  static String _signed(String Function(int) plain, int minor) =>
      minor < 0 ? '− ${plain(-minor)}' : plain(minor);

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
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            children: [
              for (final (i, l) in lines.indexed) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
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

Widget _card(List<Widget> rows) => Card(
  margin: EdgeInsets.zero,
  child: Column(
    children: [
      for (final (i, r) in rows.indexed) ...[
        if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
        r,
      ],
    ],
  ),
);

class _Row extends StatelessWidget {
  const _Row(
    this.name,
    this.amount, {
    this.detail,
    this.color,
    this.bold = false,
    this.onTap,
    super.key,
  });

  final String name;
  final String amount;
  final String? detail;
  final Color? color;
  final bool bold;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final style = theme.textTheme.titleMedium!.copyWith(
      fontWeight: bold ? FontWeight.w700 : null,
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: style),
                  if (detail case final d?) ...[
                    const SizedBox(height: 2),
                    Text(
                      d,
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(amount, style: style.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _Settings extends ConsumerWidget {
  const _Settings(this.settings);

  final TaxSettings settings;

  Future<void> _save(WidgetRef ref, TaxSettings next) =>
      ref.read(taxSettingsProvider.notifier).save(next);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            key: const Key('tax-file-as'),
            title: const Text('You file as'),
            subtitle: Text(
              'Changes the rates used',
              style: theme.textTheme.bodySmall!.copyWith(
                color: colors.textMuted,
              ),
            ),
            trailing: Text(
              settings.company ? 'Company' : 'Individual',
              style: theme.textTheme.titleMedium,
            ),
            onTap: () async {
              final company = await showModalBottomSheet<bool>(
                context: context,
                showDragHandle: true,
                builder: (context) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (value, label, detail) in [
                        (false, 'Individual', 'Individual rates and relief'),
                        (true, 'Company', 'The company rate'),
                      ])
                        ListTile(
                          key: Key('file-as-$label'),
                          title: Text(label),
                          subtitle: Text(detail),
                          trailing: settings.company == value
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.pop(context, value),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );
              if (company == null) return;
              await _save(ref, settings.copyWith(company: company));
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
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
    final number = await showDialog<String>(
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
    String plain(int minor) => formatMoney(Money(minor), withCurrency: false);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Withheld by clients', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
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
                  style: TextStyle(color: colors.textMuted),
                ),
                trailing: Text(
                  w.certificate == null ? 'Add' : 'Edit',
                  style: TextStyle(color: colors.link),
                ),
                onTap: () => _edit(context, ref, w),
              ),
          ],
        ),
      ),
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
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Certificate from ${widget.withheld.person}'),
    content: TextField(
      key: const Key('certificate-number'),
      controller: _number,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Certificate number'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: const Key('certificate-save'),
        onPressed: () => Navigator.pop(context, _number.text),
        child: const Text('Save'),
      ),
    ],
  );
}
