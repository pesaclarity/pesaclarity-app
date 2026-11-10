import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../domain/books/business_report.dart';
import '../../../domain/books/report_setup.dart';
import '../../../domain/spaces/space_categories.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/application/activity_providers.dart';
import '../../books/presentation/money_screen.dart';
import '../../sales/presentation/pay_sheet.dart';
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
      if (mounted) showNote(context, 'The report was not made. Try again.');
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
    final loaded = ref.watch(businessReportProvider(period));
    final report = loaded.value;
    final hidden = AmountsHidden.of(context);
    String plain(int minor) =>
        moneyOrHidden(minor, hidden: hidden, withCurrency: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Full records'),
        actions: const [AmountsEye(), SizedBox(width: 8)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ChoiceMenu<_View>(
              key: const Key('records-view'),
              name: 'Show',
              options: [for (final v in _View.values) (v, v.label)],
              value: _view,
              itemKey: (v) => Key('records-${v.name}'),
              onChanged: (v) => setState(() => _view = v),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            periodText(period, thisYear: today.year),
            style: theme.textTheme.bodyMedium!.copyWith(
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          if (report == null && loaded.hasError)
            ErrorView(
              'Your records could not load.',
              onRetry: () => ref.invalidate(businessReportProvider(period)),
            )
          else if (report == null)
            const LoadingView(inList: true)
          else
            switch (_view) {
              _View.profitAndLoss => _ProfitAndLoss(report, plain: plain),
              _View.cashBook => _CashBook(period, plain: plain),
              _View.customers => _Owed(
                empty: 'Customers who owe the business show here.',
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
                empty: 'Suppliers the business owes show here.',
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
          ButtonPair(
            primary: OutlinedButton(
              key: const Key('records-share-pdf'),
              onPressed: _busy || report == null
                  ? null
                  : () => _share(period, csv: false),
              child: const Text('Share PDF'),
            ),
            secondary: OutlinedButton(
              key: const Key('records-csv'),
              onPressed: _busy || report == null
                  ? null
                  : () => _share(period, csv: true),
              child: const Text('CSV'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfitAndLoss extends StatelessWidget {
  const _ProfitAndLoss(this.report, {required this.plain});

  final BusinessReport report;
  final String Function(int minor) plain;

  String _cost(int minor) => minor == 0 ? '0' : '-${plain(minor)}';

  @override
  Widget build(BuildContext context) {
    final pnl = report.pnl;
    final b = report.balance;
    final named = [for (final w in report.byWay.keys) methodName(w)].join(', ');
    final ways = named.isEmpty
        ? named
        : '${named[0].toUpperCase()}${named.substring(1)}';
    return Column(
      children: [
        GroupedSection(
          children: [
            if (pnl.income.isEmpty && pnl.costs.isEmpty)
              const LabelValueRow(
                label: 'No sales or costs in this period',
                value: '',
              ),
            for (final l in pnl.income)
              LabelValueRow(
                label: l.name,
                value: plain(l.amountMinor),
                detail: l.name == salesCategoryName && ways.isNotEmpty
                    ? ways
                    : null,
              ),
            for (final l in pnl.costs)
              LabelValueRow(label: l.name, value: _cost(l.amountMinor)),
            LabelValueRow(
              key: const Key('records-profit'),
              label: 'Profit',
              value: pnl.profitMinor < 0
                  ? '-${plain(-pnl.profitMinor)}'
                  : plain(pnl.profitMinor),
              strong: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        GroupedSection(
          children: [
            LabelValueRow(
              label: 'Cash, M-Pesa and bank',
              value: plain(b.moneyMinor),
              detail: 'What the business has',
            ),
            LabelValueRow(
              label: 'Customers owe you',
              value: plain(b.owedToYouMinor),
            ),
            if (b.stockMinor != 0)
              LabelValueRow(
                label: 'Stock',
                value: plain(b.stockMinor),
                detail: 'At what it cost',
              ),
            LabelValueRow(
              label: 'You owe suppliers',
              value: _cost(b.owedToSuppliersMinor),
            ),
            if (b.paidYourselfMinor > 0)
              LabelValueRow(
                label: 'Paid yourself',
                value: plain(b.paidYourselfMinor),
                detail: 'Moved to Personal',
              ),
          ],
        ),
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
    final loaded = ref.watch(reportCashBookProvider(period));
    final book = loaded.value;
    final accounts = ref.watch(activityAccountsProvider).value ?? const {};
    final categories = ref.watch(activityCategoriesProvider).value ?? const {};
    final today = CalendarDate.local(ref.watch(clockProvider)());
    if (book == null && loaded.hasError) {
      return ErrorView(
        'The cash book could not load.',
        onRetry: () => ref.invalidate(reportCashBookProvider(period)),
      );
    }
    if (book == null) return const LoadingView(inList: true);
    if (book.days.isEmpty) {
      return const EmptyNote('Money in and out for this period shows here.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in book.days) ...[
          SectionLabel(
            dayHeading(day.date, today: today),
            trailing: Text(
              'In ${plain(day.inMinor)} · Out ${plain(day.outMinor)}',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
          ),
          GroupedSection(
            children: [
              for (final line in day.lines)
                CashBookRow(
                  line: line,
                  accounts: accounts,
                  categories: categories,
                  plain: plain,
                ),
            ],
          ),
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
    if (rows.isEmpty) return EmptyNote(empty);
    final total = rows.fold(0, (sum, r) => sum + r.owed);
    return GroupedSection(
      children: [
        for (final r in rows)
          LabelValueRow(
            key: Key(r.key),
            label: r.name,
            value: plain(r.owed),
            detail: r.detail,
            onTap: () => context.push(r.open),
          ),
        LabelValueRow(label: 'Total', value: plain(total), strong: true),
      ],
    );
  }
}
