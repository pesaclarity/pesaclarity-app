import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/time/calendar.dart';
import '../../../theme/pesa_colors.dart';
import '../application/statement_import_controller.dart';
import '../application/statement_importer.dart';

/// Imports an M-Pesa statement PDF to fill gaps and check the balance.
class StatementImportScreen extends ConsumerStatefulWidget {
  const StatementImportScreen({super.key});

  @override
  ConsumerState<StatementImportScreen> createState() =>
      _StatementImportScreenState();
}

class _StatementImportScreenState extends ConsumerState<StatementImportScreen> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submitPassword() {
    final password = _password.text;
    _password.clear();
    if (password.isEmpty) return;
    ref
        .read(statementImportControllerProvider.notifier)
        .submitPassword(password);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(statementImportControllerProvider);
    final controller = ref.read(statementImportControllerProvider.notifier);
    final busy = state.stage == StatementImportStage.reading;

    Widget chooseAnother() => OutlinedButton(
      onPressed: controller.pickAndImport,
      child: const Text('Choose another file'),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import a statement'),
        automaticallyImplyLeading: !busy,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: switch (state.stage) {
            StatementImportStage.intro => [
              const _Explanation(),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: controller.pickAndImport,
                child: const Text('Choose a PDF'),
              ),
            ],
            StatementImportStage.reading => const [
              _Heading('Reading your statement'),
              SizedBox(height: 16),
              LinearProgressIndicator(semanticsLabel: 'Import progress'),
              SizedBox(height: 12),
              _Body('This happens on your phone.'),
            ],
            StatementImportStage.password => [
              const _Heading('This statement has a password'),
              const SizedBox(height: 8),
              const _Body(
                'Safaricom sends the password by SMS when you request a '
                'statement. It is used once to open the file, then forgotten.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                autofocus: true,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitPassword(),
                decoration: InputDecoration(
                  labelText: 'Statement password',
                  errorText: state.wrongPassword
                      ? 'That password did not open the file. Try again.'
                      : null,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitPassword,
                child: const Text('Open statement'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: controller.startOver,
                child: const Text('Cancel'),
              ),
            ],
            StatementImportStage.imported => [
              const _Heading('Statement imported'),
              const SizedBox(height: 16),
              _SummaryCard(state.summary!),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Done'),
              ),
              const SizedBox(height: 8),
              chooseAnother(),
            ],
            StatementImportStage.alreadyImported => [
              _Heading(
                'You imported this statement on '
                '${dayLabel(CalendarDate.nairobi(state.summary!.importedAt))}',
              ),
              const SizedBox(height: 8),
              const _Body(
                'Its transactions are already in your ledger. Here is how it '
                'matched then.',
              ),
              const SizedBox(height: 16),
              _SummaryCard(state.summary!),
              const SizedBox(height: 24),
              chooseAnother(),
            ],
            StatementImportStage.comingSoon => [
              _Heading('${state.bankName} statements are coming soon'),
              const SizedBox(height: 8),
              const _Body(
                'For now Pesa Clarity reads M-Pesa statements. Your bank '
                'alerts are still captured from SMS as they arrive.',
              ),
              const SizedBox(height: 24),
              chooseAnother(),
            ],
            StatementImportStage.notStatement => [
              const _Heading('We could not find M-Pesa transactions here'),
              const SizedBox(height: 8),
              const _Body(
                'Choose the full M-Pesa statement PDF, as Safaricom sent it.',
              ),
              const SizedBox(height: 24),
              chooseAnother(),
            ],
            StatementImportStage.notPdf => [
              const _Heading('This file could not be opened'),
              const SizedBox(height: 8),
              const _Body('Choose a statement saved as a PDF.'),
              const SizedBox(height: 24),
              chooseAnother(),
            ],
            StatementImportStage.failed => [
              const _Heading('The import stopped'),
              const SizedBox(height: 8),
              const _Body(
                'Something went wrong while reading the statement. Try '
                'again; transactions already imported are matched, so '
                'nothing is counted twice.',
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: controller.pickAndImport,
                child: const Text('Try again'),
              ),
            ],
          },
        ),
      ),
    );
  }
}

class _Explanation extends StatelessWidget {
  const _Explanation();

  static const _points = [
    'Choose an M-Pesa statement PDF. Bank statements are coming soon.',
    'The file is read on this phone and stays here.',
    'If it has a password, you type it once. It opens the file and is then '
        'forgotten.',
    'Transactions already captured from SMS are matched and counted once.',
    'The result is checked against the statement closing balance, and any '
        'gap is shown.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('Fill gaps from a statement'),
        const SizedBox(height: 8),
        const _Body(
          'A statement adds history from before Pesa Clarity was installed '
          'and any messages that were missed.',
        ),
        const SizedBox(height: 16),
        for (final point in _points)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 12),
                  child: Icon(
                    Icons.check_circle_outline,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Expanded(child: Text(point, style: theme.textTheme.bodyLarge)),
              ],
            ),
          ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(this.summary);

  final StatementImportSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final closing = summary.closingBalanceMinor;
    final gap = summary.gapMinor;

    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          Text(
            value,
            style: theme.textTheme.bodyLarge!.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(
              summary.institutionName,
              '${dayLabel(summary.firstDay)} to ${dayLabel(summary.lastDay)}',
            ),
            const Divider(),
            row('Transactions on the statement', '${summary.transactionCount}'),
            row('Added', '${summary.addedCount}'),
            row('Already captured from SMS', '${summary.duplicateCount}'),
            const Divider(),
            if (summary.reconciles)
              Text(
                closing == null
                    ? 'Matches the closing balance'
                    : 'Matches the closing balance of '
                          '${formatMoney(Money(closing))}',
                style: theme.textTheme.titleMedium!.copyWith(
                  color: colors.successText,
                ),
              )
            else ...[
              Text(
                '${formatMoney(Money(gap.abs()))} gap against the closing '
                'balance${closing == null ? '' : ' of ${formatMoney(Money(closing))}'}',
                style: theme.textTheme.titleMedium!.copyWith(
                  color: colors.warning,
                ),
              ),
              const SizedBox(height: 4),
              _Body(
                gap > 0
                    ? 'Your ledger shows less than the statement. Some money '
                          'in may be missing from this period.'
                    : 'Your ledger shows more than the statement. Some money '
                          'out may be missing, or a transaction may be '
                          'counted twice.',
              ),
            ],
            if (summary.unreadCount > 0) ...[
              const SizedBox(height: 8),
              _Body(
                summary.unreadCount == 1
                    ? '1 line of the statement could not be read.'
                    : '${summary.unreadCount} lines of the statement could '
                          'not be read.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A date as the import screen shows it, for example `1 Oct 2026`.
String dayLabel(CalendarDate day) =>
    '${day.day} ${_months[day.month - 1]} ${day.year}';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.headlineSmall);
}

class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodyLarge!
        .copyWith(color: PesaColors.of(context).textMuted),
  );
}
