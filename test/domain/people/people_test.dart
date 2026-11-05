import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/debts/debt.dart';
import 'package:pesaclarity/src/domain/debts/family_loan.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/lending/lent_loan.dart';
import 'package:pesaclarity/src/domain/people/people.dart';
import 'package:pesaclarity/src/domain/people/reminder_text.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

void main() {
  final today = CalendarDate(2026, 11, 5);
  var id = 1;
  LentLoan loan(
    String person,
    int amount,
    CalendarDate on, {
    CalendarDate? due,
    List<LoanPayment> payments = const [],
    String? note = 'Sale',
  }) => LentLoan(
    id: id++,
    person: person,
    amountMinor: amount,
    lentOn: on,
    dueDate: due,
    note: note,
    payments: payments,
  );

  test('customers group by name, with what is owed and since when', () {
    final list = customersFrom([
      loan('Kamau', 70000, CalendarDate(2026, 10, 18)),
      loan('otieno ', 80000, CalendarDate(2026, 10, 29), due: today),
      loan(
        'Otieno',
        50000,
        CalendarDate(2026, 10, 20),
        payments: [
          LoanPayment(date: CalendarDate(2026, 10, 27), amountMinor: 50000),
        ],
      ),
      loan(
        'Njeri',
        20000,
        CalendarDate(2026, 10, 1),
        payments: [
          LoanPayment(date: CalendarDate(2026, 10, 2), amountMinor: 20000),
        ],
      ),
    ], today: today);

    expect(list.map((c) => c.name), ['Kamau', 'Otieno', 'Njeri']);
    final kamau = list[0];
    expect(kamau.owedMinor, 70000);
    expect(kamau.overTwoWeeksMinor, 70000);
    final otieno = list[1];
    expect(otieno.owedMinor, 80000);
    expect(otieno.overTwoWeeksMinor, 0);
    expect(otieno.since, CalendarDate(2026, 10, 29));
    expect(otieno.nextDue, today);
    expect(otieno.history.map((l) => l.amountMinor), [80000, -50000, 50000]);
    expect(list[2].owedMinor, 0);
  });

  test('suppliers are supplier debts still owed, soonest due first', () {
    Debt debt(
      int id,
      String lender,
      int balance, {
      DebtType type = DebtType.supplier,
      CalendarDate? due,
    }) => Debt(
      id: id,
      lender: lender,
      type: type,
      balanceMinor: balance,
      isFormal: false,
      instalments: [
        if (due != null) DebtInstalment(dueDate: due, amountMinor: balance),
      ],
    );
    final list = suppliersFrom([
      debt(1, 'Mzee Juma', 150000),
      debt(2, 'Wakulima', 450000, due: CalendarDate(2026, 11, 7)),
      debt(3, 'Cousin', 100000, type: DebtType.family),
      debt(4, 'Paid up', 0),
    ], today: today);
    expect(list.map((s) => s.name), ['Wakulima', 'Mzee Juma']);
    expect(list.first.nextDue, CalendarDate(2026, 11, 7));
    expect(dueWithin(list, today: today), 450000);
  });

  test('the friendly reminder leaves out what it does not know', () {
    expect(
      friendlyReminder(
        name: 'Otieno Ouma',
        business: 'Vegetable stall',
        amount: 'KES 1,200',
        due: 'today',
      ),
      'Hi Otieno, a friendly reminder from Vegetable stall: KES 1,200, due '
      'today. Thank you!',
    );
    expect(
      friendlyReminder(
        name: 'Kamau',
        business: 'Vegetable stall',
        amount: 'KES 700',
        what: 'vegetables',
      ),
      'Hi Kamau, a friendly reminder from Vegetable stall: KES 700 for '
      'vegetables. Thank you!',
    );
  });
}
