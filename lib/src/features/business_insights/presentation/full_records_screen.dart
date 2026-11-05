import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../domain/books/business_report.dart';
import '../../../domain/books/report_setup.dart';
import '../../../domain/spaces/space_categories.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/application/activity_providers.dart';
import '../../books/presentation/money_screen.dart';
import '../../sales/presentation/pay_sheet.dart';
import '../../security/application/balance_visibility.dart';
import '../application/business_report_providers.dart';
import '../application/report_maker.dart';
import 'business_insights_screen.dart';

enum _View {
  profitAndLoss('Profit and loss'),
  cashBook('Cash book'),
  customers('Customers'),
  suppliers('Suppliers');

  const _View(this.label);

  final String label;
}

/// The formal records for the Insights period: profit and loss with the
/// balance summary, the cash book, customers and suppliers. Shared as a
/// PDF or exported as CSV.
class FullRecordsScreen extends ConsumerStatefulWidget {
  const FullRecordsScreen({super.key});

  @override
  ConsumerState<FullRecordsScreen> createState() => _FullRecordsScreenState();
}

class _FullRecordsScreenState extends ConsumerState<FullRecordsScreen> {
  var _view = _View.profitAndLoss;
  var _busy = false;

  static const _sections = {
    ReportSection.profitAndLoss,
    ReportSection.balance,
    ReportSection.customers,
    ReportSection.suppliers,
    ReportSection.cashBook,
  };

  Future<void> _share(ReportPeriod period, {required bool csv}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final maker = ref.read(reportMakerProvider);
      final doc = await maker.make(
        period: period,
        sections: _sections,
        title: 'Full records',
      );
      if (csv) {
        await maker.shareCsv(doc);
      } else {
        await maker.sharePdf(doc);
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
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final period = periodFor(ref.watch(insightsRangeProvider), today);
    final report = ref.watch(businessReportProvider(period)).value;
    final hidden = ref.watch(balancesHiddenProvider);
    String plain(int minor) =>
        hidden ? maskedDigits : formatMoney(Money(minor), withCurrency: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Full records')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in _View.values)
                ChoiceChip(
                  key: Key('records-${v.name}'),
                  label: Text(v.label),
                  selected: _view == v,
                  onSelected: (_) => setState(() => _view = v),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            periodText(period, thisYear: today.year),
            style: theme.textTheme.bodyMedium!.copyWith(
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          if (report == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else
            switch (_view) {
              _View.profitAndLoss => _ProfitAndLoss(report, plain: plain),
              _View.cashBook => _CashBook(period, plain: plain),
              _View.customers => _Owed(
                empty: 'No customer owes the business.',
                rows: [
                  for (final c in report.customers)
                    (
                      key: 'customer-${c.name}',
                      name: c.name,
                      detail: c.overTwoWeeksMinor > 0
                          ? '${plain(c.overTwoWeeksMinor)} over two weeks'
                          : null,
                      owed: c.owedMinor,
                      open: AppRoutes.customerStatement(c.name),
                    ),
                ],
                plain: plain,
              ),
              _View.suppliers => _Owed(
                empty: 'The business owes no supplier.',
                rows: [
                  for (final s in report.suppliers)
                    if (s.owedMinor > 0)
                      (
                        key: 'supplier-${s.debt.id}',
                        name: s.name,
                        detail: s.nextDue == null
                            ? null
                            : 'Due ${shortDate(s.nextDue!)}',
                        owed: s.owedMinor,
                        open: AppRoutes.supplierStatement(s.debt.id),
                      ),
                ],
                plain: plain,
              ),
            },
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('records-share-pdf'),
                  onPressed: _busy || report == null
                      ? null
                      : () => _share(period, csv: false),
                  child: const Text('Share PDF'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  key: const Key('records-csv'),
                  onPressed: _busy || report == null
                      ? null
                      : () => _share(period, csv: true),
                  child: const Text('Export CSV'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A line of a records card: a name, an optional note, and an amount.
class _Line extends StatelessWidget {
  const _Line(
    this.name,
    this.amount, {
    this.detail,
    this.color,
    this.bold = false,
    super.key,
  });

  final String name;
  final String? detail;
  final String amount;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final style = theme.textTheme.titleMedium!.copyWith(
      fontWeight: bold ? FontWeight.w700 : null,
    );
    return Padding(
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
          Text(amount, style: style.copyWith(color: color)),
        ],
      ),
    );
  }
}

Widget _card(List<Widget> lines) => Card(
  margin: EdgeInsets.zero,
  child: Column(
    children: [
      for (final (i, l) in lines.indexed) ...[
        if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
        l,
      ],
    ],
  ),
);

class _ProfitAndLoss extends StatelessWidget {
  const _ProfitAndLoss(this.report, {required this.plain});

  final BusinessReport report;
  final String Function(int minor) plain;

  String _cost(int minor) => minor == 0 ? '0' : '− ${plain(minor)}';

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    final pnl = report.pnl;
    final b = report.balance;
    final named = [for (final w in report.byWay.keys) methodName(w)].join(', ');
    final ways = named.isEmpty
        ? named
        : '${named[0].toUpperCase()}${named.substring(1)}';
    return Column(
      children: [
        _card([
          if (pnl.income.isEmpty && pnl.costs.isEmpty)
            const _Line('No sales or costs in this period', ''),
          for (final l in pnl.income)
            _Line(
              l.name,
              plain(l.amountMinor),
              detail: l.name == salesCategoryName && ways.isNotEmpty
                  ? ways
                  : null,
              color: colors.successText,
            ),
          for (final l in pnl.costs) _Line(l.name, _cost(l.amountMinor)),
          _Line(
            'Profit',
            pnl.profitMinor < 0
                ? '− ${plain(-pnl.profitMinor)}'
                : plain(pnl.profitMinor),
            key: const Key('records-profit'),
            color: pnl.profitMinor >= 0 ? colors.successText : null,
            bold: true,
          ),
        ]),
        const SizedBox(height: 12),
        _card([
          _Line(
            'Cash, M-Pesa and bank',
            plain(b.moneyMinor),
            detail: 'What the business has',
          ),
          _Line(
            'Customers owe you',
            plain(b.owedToYouMinor),
            color: colors.successText,
          ),
          if (b.stockMinor != 0)
            _Line('Stock', plain(b.stockMinor), detail: 'At what it cost'),
          _Line('You owe suppliers', _cost(b.owedToSuppliersMinor)),
          if (b.paidYourselfMinor > 0)
            _Line(
              'Paid yourself',
              plain(b.paidYourselfMinor),
              detail: 'Moved to Personal',
            ),
        ]),
      ],
    );
  }
}

class _CashBook extends ConsumerWidget {
  const _CashBook(this.period, {required this.plain});

  final ReportPeriod period;
  final String Function(int minor) plain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final book = ref.watch(reportCashBookProvider(period)).value;
    final accounts = ref.watch(activityAccountsProvider).value ?? const {};
    final categories = ref.watch(activityCategoriesProvider).value ?? const {};
    final today = CalendarDate.local(ref.watch(clockProvider)());
    if (book == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    if (book.days.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          'Nothing came in or went out in this period.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in book.days) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    dayHeading(day.date, today: today).toUpperCase(),
                    style: theme.textTheme.labelLarge!.copyWith(
                      color: colors.textMuted,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Text(
                  'In ${plain(day.inMinor)} · Out ${plain(day.outMinor)}',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          _card([
            for (final line in day.lines)
              CashBookRow(
                line: line,
                accounts: accounts,
                categories: categories,
                plain: plain,
              ),
          ]),
        ],
      ],
    );
  }
}

typedef _OwedRow = ({
  String key,
  String name,
  String? detail,
  int owed,
  String open,
});

class _Owed extends StatelessWidget {
  const _Owed({required this.rows, required this.empty, required this.plain});

  final List<_OwedRow> rows;
  final String empty;
  final String Function(int minor) plain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          empty,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
        ),
      );
    }
    final total = rows.fold(0, (sum, r) => sum + r.owed);
    return _card([
      for (final r in rows)
        InkWell(
          key: Key(r.key),
          onTap: () => context.push(r.open),
          child: _Line(r.name, plain(r.owed), detail: r.detail),
        ),
      _Line('Total', plain(total), bold: true),
    ]);
  }
}
