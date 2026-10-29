import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/debts_repository.dart';
import '../../../data/repositories/lending_repository.dart';
import '../../../domain/lending/lent_loan.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/pesa_colors.dart';
import '../../goals/application/goals_overview_provider.dart';
import '../application/lending_providers.dart';
import '../data/reminder_sharer.dart';
import 'loan_sheet.dart';

/// Lent and borrowed, under Goals: who owes whom among friends and family.
class LendingScreen extends ConsumerWidget {
  const LendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(lendingOverviewProvider);
    final today = CalendarDate.local(ref.watch(clockProvider)());

    return Scaffold(
      appBar: AppBar(title: const Text('Lent and borrowed')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showLoanSheet(context, today: today),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: switch (overview) {
        AsyncData(:final value) => _LendingBody(value),
        AsyncError() => Center(
          child: TextButton(
            onPressed: () =>
                refreshGoals(ProviderScope.containerOf(context, listen: false)),
            child: const Text('This list could not load. Tap to try again.'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _LendingBody extends StatelessWidget {
  const _LendingBody(this.overview);

  final LendingOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = overview.today;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
      children: [
        _TotalsCard(overview),
        if (overview.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Record money you lend to or borrow from friends and family. '
              'Add part payments as they come, and send a polite reminder '
              'on WhatsApp when one is due.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        if (overview.lent.isNotEmpty) ...[
          const _Header('You lent'),
          _LoanList([
            for (final loan in overview.lent) _LoanView.lent(loan, today),
          ]),
        ],
        if (overview.borrowed.isNotEmpty) ...[
          const _Header('You borrowed'),
          _LoanList([
            for (final loan in overview.borrowed)
              _LoanView.borrowed(loan, today),
          ]),
        ],
      ],
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard(this.overview);

  final LendingOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget figure(String label, int minor) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            formatMoney(Money(minor), withCurrency: false),
            style: AppTypography.amount(
              size: 22,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            figure('Owed to you', overview.owedToYouMinor),
            figure('You owe', overview.youOweMinor),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 10),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// One loan as a row shows it, whichever side it is on.
class _LoanView {
  _LoanView.lent(LentLoan this.lent, CalendarDate today)
    : borrowed = null,
      person = lent.person,
      remainingMinor = lent.status(today).remainingMinor,
      caption = lentCaption(lent, today),
      isOverdue = lent.status(today).overdueMinor > 0;

  _LoanView.borrowed(BorrowedLoan this.borrowed, CalendarDate today)
    : lent = null,
      person = borrowed.debt.lender,
      remainingMinor = borrowed.debt.balanceMinor,
      caption = borrowedCaption(borrowed, today),
      isOverdue = borrowed.status.overdueMinor > 0 && !borrowed.isCleared;

  final LentLoan? lent;
  final BorrowedLoan? borrowed;
  final String person;
  final int remainingMinor;
  final String caption;
  final bool isOverdue;
}

/// The line under money lent, such as `Lent 3 Oct · due 31 Oct`.
String lentCaption(LentLoan loan, CalendarDate today) {
  final status = loan.status(today);
  String day(CalendarDate d) => dayLabel(d, thisYear: today.year);
  if (status.isCleared) return 'Paid back · lent ${day(loan.lentOn)}';
  final parts = ['Lent ${day(loan.lentOn)}'];
  if (status.paidMinor > 0) {
    parts.add('${formatMoney(Money(status.paidMinor))} paid');
  }
  if (loan.dueDate case final due?) {
    parts.add(
      status.overdueMinor > 0 ? 'was due ${day(due)}' : 'due ${day(due)}',
    );
  }
  return parts.join(' · ');
}

/// The line under a family loan the user owes, such as `Next 5,000, 31 Jan`.
String borrowedCaption(BorrowedLoan loan, CalendarDate today) {
  if (loan.isCleared) return 'Paid';
  final status = loan.status;
  final next = status.nextDue;
  final parts = <String>[];
  if (status.paidMinor > 0) {
    parts.add('${formatMoney(Money(status.paidMinor))} paid');
  }
  if (next != null) {
    final day = dayLabel(next.dueDate, thisYear: today.year);
    final amount = formatMoney(Money(next.amountMinor), withCurrency: false);
    parts.add(
      next.dueDate.isBefore(today)
          ? '$amount was due $day'
          : 'next $amount, $day',
    );
  }
  if (parts.isEmpty) return 'Interest-free';
  final text = parts.join(' · ');
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

class _LoanList extends StatelessWidget {
  const _LoanList(this.loans);

  final List<_LoanView> loans;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < loans.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: colors.border,
              ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text(loans[i].person),
              subtitle: Text(
                loans[i].caption,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: loans[i].isOverdue ? colors.warning : null,
                ),
              ),
              trailing: Text(
                formatMoney(
                  Money(loans[i].remainingMinor),
                  withCurrency: false,
                ),
                style: AppTypography.amount(
                  size: 16,
                  color: loans[i].remainingMinor == 0
                      ? colors.textMuted
                      : theme.colorScheme.onSurface,
                ),
              ),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => _LoanActions(loans[i], screenContext: context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoanActions extends StatelessWidget {
  const _LoanActions(this.loan, {required this.screenContext});

  final _LoanView loan;

  /// The screen under the sheet, for what opens after the sheet closes.
  final BuildContext screenContext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final now = container.read(clockProvider)();
    final today = CalendarDate.local(now);
    final lent = loan.lent;
    final borrowed = loan.borrowed;
    final open = loan.remainingMinor > 0;

    Future<void> recordPayment(int amountMinor, DateTime paidAt) async {
      if (lent != null) {
        await container
            .read(lendingRepositoryProvider)
            .recordPayment(lent.id, paidAt, amountMinor);
      } else {
        await container
            .read(debtsRepositoryProvider)
            .recordPayment(borrowed!.debt.id, paidAt, amountMinor);
      }
      refreshGoals(container);
    }

    Future<void> remove() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete ${loan.person}?'),
          content: Text(
            lent != null
                ? 'The loan and its payments are removed.'
                : 'The loan is removed from Debts too.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      if (lent != null) {
        await container.read(lendingRepositoryProvider).remove(lent.id);
      } else {
        await container.read(debtsRepositoryProvider).remove(borrowed!.debt.id);
      }
      refreshGoals(container);
      if (context.mounted) Navigator.of(context).pop();
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(loan.person, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              open
                  ? '${formatMoney(Money(loan.remainingMinor))} left. '
                        '${loan.caption}.'
                  : '${loan.caption}.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (open && lent != null)
              FilledButton.icon(
                onPressed: () async {
                  final message = lentReminderMessage(lent, today: today);
                  Navigator.of(context).pop();
                  await _confirmReminder(
                    screenContext,
                    container.read(reminderSharerProvider),
                    lent.person,
                    message,
                  );
                },
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Send a reminder'),
              ),
            if (open) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await showPaymentSheet(
                    screenContext,
                    person: loan.person,
                    remainingMinor: loan.remainingMinor,
                    firstDate:
                        lent?.lentOn ?? CalendarDate(today.year - 10, 1, 1),
                    today: today,
                    now: now,
                    onSave: recordPayment,
                  );
                },
                child: const Text('Record a payment'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  await recordPayment(loan.remainingMinor, now);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Text(
                  lent != null ? 'Mark as paid back' : 'Mark as paid',
                ),
              ),
            ],
            if (lent != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  showLoanSheet(screenContext, today: today, lent: lent);
                },
                child: const Text('Edit'),
              ),
            ],
            TextButton(onPressed: remove, child: const Text('Delete')),
          ],
        ),
      ),
    );
  }
}

/// Shows the reminder as it will read, then hands it to the share sheet.
Future<void> _confirmReminder(
  BuildContext context,
  ReminderSharer sharer,
  String person,
  String message,
) async {
  final share = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Reminder for $person'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Share'),
        ),
      ],
    ),
  );
  if (share != true) return;
  try {
    await sharer.share(message);
  } on PlatformException {
    await Clipboard.setData(ClipboardData(text: message));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sharing is unavailable. The message is copied.'),
        ),
      );
    }
  }
}
