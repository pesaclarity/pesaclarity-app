import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/time/calendar.dart';
import '../../../theme/pesa_colors.dart';
import '../../sms/presentation/explain_text.dart';
import '../application/statement_import_controller.dart';
import '../application/statement_importer.dart';
import '../application/statement_password_hints.dart';

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
            StatementImportStage.reading => [
              ExplainHeading(
                state.isBatch
                    ? 'Reading statement ${state.fileNumber} of '
                          '${state.fileCount}'
                    : 'Reading your statement',
              ),
              const SizedBox(height: 16),
              const LinearProgressIndicator(semanticsLabel: 'Import progress'),
              const SizedBox(height: 12),
              const ExplainBody('This happens on your phone.'),
            ],
            StatementImportStage.password => [
              const ExplainHeading('This statement has a password'),
              if (state.isBatch) ...[
                const SizedBox(height: 4),
                ExplainBody(state.fileName ?? ''),
              ],
              const SizedBox(height: 8),
              for (final hint in ref.watch(statementPasswordHintsProvider))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ExplainBody(hint),
                ),
              ExplainBody(
                state.isBatch
                    ? 'It is used to open the files you chose, then '
                          'forgotten.'
                    : 'It is used once to open the file, then forgotten.',
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
                  errorText: state.retryAt != null
                      ? 'Try again in ${passwordWait.inSeconds} seconds.'
                      : state.wrongPassword
                      ? 'That password did not open the file. Try again.'
                      : null,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: state.retryAt == null ? _submitPassword : null,
                child: const Text('Open statement'),
              ),
              const SizedBox(height: 8),
              if (state.isBatch)
                TextButton(
                  onPressed: controller.skipFile,
                  child: const Text('Skip this file'),
                ),
              TextButton(
                onPressed: controller.startOver,
                child: const Text('Cancel'),
              ),
            ],
            StatementImportStage.imported => [
              const ExplainHeading('Statement imported'),
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
              ExplainHeading(
                'You imported this statement on '
                '${dayLabel(CalendarDate.local(state.summary!.importedAt))}',
              ),
              const SizedBox(height: 8),
              const ExplainBody(
                'Its transactions are already in your ledger. Here is how it '
                'matched then.',
              ),
              const SizedBox(height: 16),
              _SummaryCard(state.summary!),
              const SizedBox(height: 24),
              chooseAnother(),
            ],
            StatementImportStage.comingSoon => [
              ExplainHeading('${state.bankName} statements are coming soon'),
              const SizedBox(height: 8),
              const ExplainBody(
                'For now Pesa Clarity reads M-Pesa statements. Your bank '
                'alerts are still captured from SMS as they arrive.',
              ),
              const SizedBox(height: 24),
              chooseAnother(),
            ],
            StatementImportStage.notStatement => [
              const ExplainHeading(
                'We could not find M-Pesa transactions here',
              ),
              const SizedBox(height: 8),
              const ExplainBody(
                'Choose the full M-Pesa statement PDF, as Safaricom sent it.',
              ),
              const SizedBox(height: 24),
              chooseAnother(),
            ],
            StatementImportStage.noText => [
              const ExplainHeading('This PDF is a scanned picture'),
              const SizedBox(height: 8),
              const ExplainBody(noTextAdvice),
              const SizedBox(height: 24),
              chooseAnother(),
            ],
            StatementImportStage.batchDone => [
              const ExplainHeading('Your statements'),
              const SizedBox(height: 16),
              for (final result in state.results) ...[
                Text(
                  result.fileName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (result.outcome case StatementImported(:final summary))
                  _SummaryCard(summary)
                else
                  ExplainBody(_resultLine(result)),
                const SizedBox(height: 20),
              ],
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Done'),
              ),
              const SizedBox(height: 8),
              chooseAnother(),
            ],
            StatementImportStage.notPdf => [
              const ExplainHeading('This file could not be opened'),
              const SizedBox(height: 8),
              const ExplainBody('Choose a statement saved as a PDF.'),
              const SizedBox(height: 24),
              chooseAnother(),
            ],
            StatementImportStage.failed => [
              const ExplainHeading('The import stopped'),
              const SizedBox(height: 8),
              const ExplainBody(
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
    'Choose one or more M-Pesa statement PDFs. Bank statements are coming '
        'soon.',
    'The file is read on this phone and stays here.',
    'If it has a password, you type it once. It opens the file and is then '
        'forgotten.',
    'Transactions already captured from SMS are matched and counted once.',
    'The result is checked against the statement closing balance, and any '
        'gap is shown.',
  ];

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExplainHeading('Fill gaps from a statement'),
      SizedBox(height: 8),
      ExplainBody(
        'A statement adds history from before Pesa Clarity was installed '
        'and any messages that were missed.',
      ),
      SizedBox(height: 16),
      TickPoints(_points),
    ],
  );
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
            const Divider(height: 1),
            row('Transactions on the statement', '${summary.transactionCount}'),
            row('Added', '${summary.addedCount}'),
            row('Already captured from SMS', '${summary.duplicateCount}'),
            const Divider(height: 1),
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
              ExplainBody(
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
              ExplainBody(
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

/// What to do with a scanned statement.
const noTextAdvice =
    'Pesa Clarity reads statements saved from the M-Pesa app or your bank '
    'website. Download it again from there and choose that file.';

/// One line about a file of a batch that was not imported.
String _resultLine(StatementFileResult result) {
  if (result.skipped) return 'Skipped.';
  return switch (result.outcome) {
    null => 'The import stopped. Try this file again.',
    StatementAlreadyImported(:final summary) =>
      'You imported this statement on '
          '${dayLabel(CalendarDate.local(summary.importedAt))}. Its '
          'transactions are already in your ledger.',
    StatementComingSoon(:final bankName) =>
      '$bankName statements are coming soon.',
    StatementHasNoText() => 'This PDF is a scanned picture. $noTextAdvice',
    StatementNotRead(isPdf: true) =>
      'We could not find M-Pesa transactions here.',
    StatementNotRead(isPdf: false) => 'This file could not be opened.',
    StatementImported() || StatementNeedsPassword() => '',
  };
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
