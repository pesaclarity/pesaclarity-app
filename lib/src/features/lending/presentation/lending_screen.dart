import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/debts_repository.dart';
import '../../../data/repositories/lending_repository.dart';
import '../../../domain/lending/lent_loan.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
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
      appBar: AppBar(
        title: const Text('Lent and borrowed'),
        actions: const [AmountsEye(), SizedBox(width: 8)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showLoanSheet(context, today: today),
        icon: const Icon(Icons.add),
        label: const Text('Add a loan'),
      ),
      body: switch (overview) {
        AsyncData(:final value) => _LendingBody(value),
        AsyncError() => ErrorView(
          'Your loans could not load.',
          onRetry: () =>
              refreshGoals(ProviderScope.containerOf(context, listen: false)),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _LendingBody extends StatelessWidget {
  const _LendingBody(this.overview);

  final LendingOverview overview;

  @override
  Widget build(BuildContext context) {
    final today = overview.today;
    return ListView(
      // Clear of the round add button.
      padding: const EdgeInsets.fromLTRB(
        Layout.gutter,
        8,
        Layout.gutter,
        Layout.tabBottom,
      ),
      children: [
        FigureRow(
          children: [
            FigureTile(
              label: 'Owed to you',
              value: shownMoney(
                context,
                overview.owedToYouMinor,
                withCurrency: false,
              ),
            ),
            FigureTile(
              label: 'You owe',
              value: shownMoney(
                context,
                overview.youOweMinor,
                withCurrency: false,
              ),
            ),
          ],
        ),
        if (overview.isEmpty)
          const EmptyNote(
            'Record money you lend to or borrow from friends and family. '
            'Add part payments as they come, and send a polite reminder '
            'on WhatsApp when one is due.',
          ),
        if (overview.lent.isNotEmpty) ...[
          const SectionTitle('You lent'),
          _LoanList([
            for (final loan in overview.lent)
              _LoanView.lent(loan, today, hidden: AmountsHidden.of(context)),
          ]),
        ],
        if (overview.borrowed.isNotEmpty) ...[
          const SectionTitle('You borrowed'),
          _LoanList([
            for (final loan in overview.borrowed)
              _LoanView.borrowed(
                loan,
                today,
                hidden: AmountsHidden.of(context),
              ),
          ]),
        ],
      ],
    );
  }
}

/// One loan as a row shows it, whichever side it is on.
class _LoanView {
  _LoanView.lent(LentLoan this.lent, CalendarDate today, {bool hidden = false})
    : borrowed = null,
      person = lent.person,
      remainingMinor = lent.status(today).remainingMinor,
      caption = lentCaption(lent, today, hidden: hidden),
      isOverdue = lent.status(today).overdueMinor > 0;

  _LoanView.borrowed(
    BorrowedLoan this.borrowed,
    CalendarDate today, {
    bool hidden = false,
  }) : lent = null,
       person = borrowed.debt.lender,
       remainingMinor = borrowed.debt.balanceMinor,
       caption = borrowedCaption(borrowed, today, hidden: hidden),
       isOverdue = borrowed.status.overdueMinor > 0 && !borrowed.isCleared;

  final LentLoan? lent;
  final BorrowedLoan? borrowed;
  final String person;
  final int remainingMinor;
  final String caption;
  final bool isOverdue;
}

/// The line under money lent, such as `Lent 3 Oct · due 31 Oct`.
String lentCaption(LentLoan loan, CalendarDate today, {bool hidden = false}) {
  final status = loan.status(today);
  String day(CalendarDate d) => dayLabel(d, thisYear: today.year);
  if (status.isCleared) return 'Paid back · lent ${day(loan.lentOn)}';
  final parts = ['Lent ${day(loan.lentOn)}'];
  if (status.paidMinor > 0) {
    parts.add('${moneyOrHidden(hidden: hidden, status.paidMinor)} paid');
  }
  if (loan.dueDate case final due?) {
    parts.add(
      status.overdueMinor > 0 ? 'was due ${day(due)}' : 'due ${day(due)}',
    );
  }
  return parts.join(' · ');
}

/// The line under a family loan the user owes, such as `Next 5,000, 31 Jan`.
String borrowedCaption(
  BorrowedLoan loan,
  CalendarDate today, {
  bool hidden = false,
}) {
  if (loan.isCleared) return 'Paid';
  final status = loan.status;
  final next = status.nextDue;
  final parts = <String>[];
  if (status.paidMinor > 0) {
    parts.add('${moneyOrHidden(hidden: hidden, status.paidMinor)} paid');
  }
  if (next != null) {
    final day = dayLabel(next.dueDate, thisYear: today.year);
    final amount = moneyOrHidden(
      hidden: hidden,
      next.amountMinor,
      withCurrency: false,
    );
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
      child: Column(
        children: [
          for (var i = 0; i < loans.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              title: Text(loans[i].person),
              subtitle: Text(
                loans[i].caption,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: loans[i].isOverdue ? colors.warning : null,
                ),
              ),
              trailing: Text(
                shownMoney(
                  context,
                  loans[i].remainingMinor,
                  withCurrency: false,
                ),
                style: AppTypography.rowAmount(
                  loans[i].remainingMinor == 0
                      ? colors.textMuted
                      : theme.colorScheme.onSurface,
                ),
              ),
              onTap: () => showAppSheet<void>(
                context: context,
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
      final confirmed = await confirmDelete(
        context,
        title: 'Delete ${loan.person}?',
        body: lent != null
            ? 'The loan and its payments are removed.'
            : 'The loan is removed from Debts too.',
      );
      if (!confirmed) return;
      if (lent != null) {
        await container.read(lendingRepositoryProvider).remove(lent.id);
      } else {
        await container.read(debtsRepositoryProvider).remove(borrowed!.debt.id);
      }
      refreshGoals(container);
      if (context.mounted) Navigator.of(context).pop();
    }

    final actions = <Widget>[
      if (open && lent != null)
        FilledButton.icon(
          onPressed: () async {
            final message = lentReminderMessage(lent, today: today);
            Navigator.of(context).pop();
            await confirmReminder(
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
        OutlinedButton(
          onPressed: () async {
            Navigator.of(context).pop();
            await showPaymentSheet(
              screenContext,
              person: loan.person,
              remainingMinor: loan.remainingMinor,
              firstDate: lent?.lentOn ?? CalendarDate(today.year - 10, 1, 1),
              today: today,
              now: now,
              onSave: recordPayment,
            );
          },
          child: const Text('Record a payment'),
        ),
        OutlinedButton(
          onPressed: () async {
            await recordPayment(loan.remainingMinor, now);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(lent != null ? 'Mark as paid back' : 'Mark as paid'),
        ),
      ],
      if (lent != null)
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            showLoanSheet(screenContext, today: today, lent: lent);
          },
          child: const Text('Edit'),
        ),
      TextButton(
        onPressed: remove,
        style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
        child: const Text('Delete loan'),
      ),
    ];

    return SheetBody(
      title: loan.person,
      subtitle: open
          ? '${shownMoney(context, loan.remainingMinor)} left. '
                '${loan.caption}.'
          : '${loan.caption}.',
      children: [
        for (final (i, action) in actions.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          action,
        ],
      ],
    );
  }
}

/// Shows the reminder as it will read, then hands it to the share sheet.
/// Copies it when sharing is unavailable.
Future<void> confirmReminder(
  BuildContext context,
  ReminderSharer sharer,
  String person,
  String message,
) async {
  final share = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text('Reminder for $person'),
      content: Text(message),
      actions: [
        DialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        DialogAction(
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
      showNote(context, 'Sharing is unavailable. The message is copied.');
    }
  }
}
