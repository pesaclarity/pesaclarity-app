import '../debts/debt.dart';
import '../enums.dart';
import '../lending/lent_loan.dart';
import '../time/calendar.dart';

/// Days after which money owed counts as "over 2 weeks".
const overdueAfterDays = 14;

/// One line of a statement: something owed (positive) or paid (negative).
class StatementLine {
  const StatementLine({
    required this.date,
    required this.label,
    required this.amountMinor,
  });

  final CalendarDate date;
  final String label;

  /// Positive adds to what is owed; negative is a payment.
  final int amountMinor;
}

/// A customer and what they owe, from their credit sales.
class CustomerAccount {
  const CustomerAccount({
    required this.name,
    required this.owedMinor,
    required this.overTwoWeeksMinor,
    required this.history,
    this.since,
    this.nextDue,
  });

  final String name;
  final int owedMinor;

  /// What they owe from credit more than [overdueAfterDays] old.
  final int overTwoWeeksMinor;

  /// The oldest credit not yet paid.
  final CalendarDate? since;

  /// The earliest agreed date still to pay.
  final CalendarDate? nextDue;

  /// Newest first.
  final List<StatementLine> history;
}

String _key(String name) => name.trim().toLowerCase();

/// Customers from [loans], grouped by name: those who owe first, longest
/// owing first, then the rest by name.
List<CustomerAccount> customersFrom(
  Iterable<LentLoan> loans, {
  required CalendarDate today,
}) {
  final byName = <String, List<LentLoan>>{};
  for (final l in loans) {
    (byName[_key(l.person)] ??= []).add(l);
  }
  final out = <CustomerAccount>[];
  for (final group in byName.values) {
    group.sort((a, b) => a.lentOn.compareTo(b.lentOn));
    var owed = 0;
    var over = 0;
    CalendarDate? since;
    CalendarDate? nextDue;
    final history = <StatementLine>[];
    for (final l in group) {
      final status = l.status(today);
      final left = status.remainingMinor;
      owed += left;
      if (left > 0) {
        since ??= l.lentOn;
        if (l.lentOn.daysUntil(today) > overdueAfterDays) over += left;
        final due = status.nextDue?.dueDate;
        if (due != null && (nextDue == null || due.isBefore(nextDue))) {
          nextDue = due;
        }
      }
      history.add(
        StatementLine(
          date: l.lentOn,
          label: l.note == null || l.note == 'Sale'
              ? 'On credit'
              : '${l.note} on credit',
          amountMinor: l.amountMinor,
        ),
      );
      for (final p in l.payments) {
        history.add(
          StatementLine(
            date: p.date,
            label: 'Paid',
            amountMinor: -p.amountMinor,
          ),
        );
      }
    }
    history.sort((a, b) => b.date.compareTo(a.date));
    out.add(
      CustomerAccount(
        name: group.first.person.trim(),
        owedMinor: owed,
        overTwoWeeksMinor: over,
        since: since,
        nextDue: nextDue,
        history: history,
      ),
    );
  }
  out.sort((a, b) {
    if ((a.owedMinor > 0) != (b.owedMinor > 0)) return a.owedMinor > 0 ? -1 : 1;
    final s = (a.since ?? today).compareTo(b.since ?? today);
    return s != 0 ? s : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
}

/// A supplier the business owes.
class SupplierAccount {
  const SupplierAccount({
    required this.debt,
    required this.owedMinor,
    this.nextDue,
  });

  final Debt debt;
  final int owedMinor;
  final CalendarDate? nextDue;

  String get name => debt.lender;
}

/// Suppliers in [debts] the business still owes, the soonest due first.
List<SupplierAccount> suppliersFrom(
  Iterable<Debt> debts, {
  required CalendarDate today,
}) {
  final out = [
    for (final d in debts)
      if (d.type == DebtType.supplier && d.balanceMinor > 0)
        SupplierAccount(
          debt: d,
          owedMinor: d.balanceMinor,
          nextDue: _nextDue(d.instalments, d.balanceMinor),
        ),
  ];
  out.sort((a, b) {
    final x = a.nextDue, y = b.nextDue;
    if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
    return x.compareTo(y);
  });
  return out;
}

/// The first agreed date not yet covered, as payments clear the oldest
/// instalment first.
CalendarDate? _nextDue(List<DebtInstalment> agreed, int owedMinor) {
  final sorted = agreed.toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  final paid = sorted.fold(0, (sum, i) => sum + i.amountMinor) - owedMinor;
  var covered = 0;
  for (final i in sorted) {
    covered += i.amountMinor;
    if (covered > paid) return i.dueDate;
  }
  return null;
}

/// What is due within [days] of [today] across [suppliers], including what
/// is late.
int dueWithin(
  Iterable<SupplierAccount> suppliers, {
  required CalendarDate today,
  int days = 7,
}) => suppliers
    .where((s) => s.nextDue != null && today.daysUntil(s.nextDue!) <= days)
    .fold(0, (sum, s) => sum + s.owedMinor);

/// Customers to remind today: due today or late, or owing over two weeks.
List<CustomerAccount> dueCustomers(
  Iterable<CustomerAccount> customers, {
  required CalendarDate today,
}) => [
  for (final c in customers)
    if (c.owedMinor > 0 &&
        ((c.nextDue != null && !c.nextDue!.isAfter(today)) ||
            c.overTwoWeeksMinor > 0))
      c,
];
