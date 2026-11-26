import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/categories_repository.dart';
import '../../../data/repositories/loan_links_repository.dart';
import '../../../domain/categories/default_categories.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/lending/loan_link.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/calendar.dart';
import '../../goals/application/goals_overview_provider.dart';
import 'loan_sheet.dart';

/// A transaction as "I lent this" and the other Lent and borrowed answers
/// see it.
class LoanSubject {
  const LoanSubject({
    required this.transactionId,
    required this.outflow,
    required this.amountMinor,
    required this.occurredAt,
    required this.currency,
    required this.person,
    required this.canLink,
  });

  final int transactionId;
  final bool outflow;
  final int amountMinor;
  final DateTime occurredAt;
  final String currency;

  /// The payee, else the name the message printed; null with neither.
  final String? person;

  /// False for an own transfer, a correction or money between spaces,
  /// which are never a loan.
  final bool canLink;
}

/// What [subject] can be in Lent and borrowed, in a space of [kind]: only
/// Personal-style spaces, since a business keeps what customers owe in
/// People. Paying back and borrowing need a name to find the loan by.
List<LoanLink> loanLinksFor(SpaceKind kind, LoanSubject subject) {
  if (!kind.tracksLending || !subject.canLink) return const [];
  return [
    for (final link in LoanLink.forDirection(outflow: subject.outflow))
      if (subject.person != null || link == LoanLink.lent) link,
  ];
}

/// [subject] as a loan when [categoryId], picked from the list, is Money
/// lent and [links] offer it: "I lent this" for money out, "Paying me
/// back" for money in. Null otherwise.
Future<LoanLink?> loanLinkOfCategory(
  CategoriesRepository categories,
  List<LoanLink> links,
  LoanSubject subject,
  int categoryId,
) async {
  final link = subject.outflow ? LoanLink.lent : LoanLink.repaidLent;
  if (!links.contains(link)) return null;
  final moneyLent = await categories.byKey(moneyLentSeed.key);
  return moneyLent?.id == categoryId ? link : null;
}

/// [entry] as the Lent and borrowed answers see it, in the currency the
/// money moved in.
LoanSubject loanSubjectOf(LedgerEntry entry) {
  final printed = entry.counterpartyName?.trim();
  return LoanSubject(
    transactionId: entry.id,
    outflow: entry.isOutflow,
    amountMinor: entry.originalAmountMinor ?? entry.amountMinor,
    occurredAt: entry.occurredAt,
    currency: entry.originalCurrency ?? entry.currency,
    person:
        entry.payeeName ??
        (printed == null || printed.isEmpty ? null : printed),
    canLink:
        entry.transferPairId == null &&
        entry.transferAccountId == null &&
        !entry.isCorrection &&
        !entry.isBalanceRecord &&
        entry.linkedSpaceId == null,
  );
}

/// Links [subject] to its loan as [link] says. "I lent this" opens the
/// loan sheet as "I lent", filled in from the transaction; the others are
/// filed at once, with a note when there is no loan to lower.
Future<void> linkToLoan(
  BuildContext context,
  LoanSubject subject,
  LoanLink link,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final links = container.read(loanLinksRepositoryProvider);
  final id = subject.transactionId;
  final person = subject.person;
  void say(String text) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
  switch (link) {
    case LoanLink.lent:
      await showLoanSheet(
        context,
        today: CalendarDate.local(container.read(clockProvider)()),
        fromTransaction: LentFromTransaction(
          transactionId: id,
          amountMinor: subject.amountMinor,
          on: CalendarDate.local(subject.occurredAt),
          person: person,
          currency: subject.currency,
        ),
      );
    case LoanLink.repaidBorrowed:
      if (!await links.payBack(id)) {
        say(
          'Nothing you borrowed from $person is still owed, so this is a '
          'loan repayment on its own.',
        );
      }
    case LoanLink.borrowed:
      await links.borrow(id);
    case LoanLink.repaidLent:
      if (!await links.paidBack(id)) {
        say(
          'Nothing you lent $person is still owed, so this is filed as an '
          'own transfer.',
        );
      }
  }
  refreshGoals(container);
}
