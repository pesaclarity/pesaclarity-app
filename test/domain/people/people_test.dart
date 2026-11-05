import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/debts/debt.dart';
import 'package:pesaclarity/src/domain/debts/family_loan.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/lending/lent_loan.dart';
import 'package:pesaclarity/src/domain/people/people.dart';
import 'package:pesaclarity/src/domain/people/phone_number.dart';
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

  test('templates fill in, leaving out what is not known', () {
    final friendly = defaultTemplates('KES').first.text;
    expect(
      fillTemplate(friendly, {
        'name': 'Otieno Ouma',
        'business': 'Vegetable stall',
        'amount': '1,200',
        'due': 'today',
      }),
      'Hi Otieno, a friendly reminder from Vegetable stall: KES 1,200, due '
      'today. Thank you!',
    );
    expect(
      fillTemplate(friendly, {
        'name': 'Kamau',
        'business': 'Vegetable stall',
        'amount': '700',
        'what': 'vegetables',
        'due': '8 Nov',
        'till': '000000',
      }),
      'Hi Kamau, a friendly reminder from Vegetable stall: KES 700 for '
      'vegetables, due 8 Nov. You can pay to till 000000. Thank you!',
    );
    final aWhile = defaultTemplates('KES').last.text;
    expect(
      fillTemplate(aWhile, {
        'name': 'Njeri',
        'amount': '600',
        'date': '20 Oct',
      }),
      'Hi Njeri, just checking in on KES 600 from 20 Oct. Thank you!',
    );
  });

  test('numbers get their country code', () {
    final kenya = callingCodeFor('KE');
    expect(internationalNumber('0712 345 678', kenya), '+254712345678');
    expect(internationalNumber('712345678', kenya), '+254712345678');
    expect(internationalNumber('254712345678', kenya), '+254712345678');
    expect(internationalNumber('+44 7700 900123', kenya), '+447700900123');
    expect(internationalNumber('0044 7700 900123', kenya), '+447700900123');
    expect(internationalNumber('123', kenya), isNull);
    expect(callingCodeFor('UG').code, '256');
    expect(callingCodeFor(null).code, '254');
    expect(
      whatsAppLink('+254712345678', 'Hi there').toString(),
      'https://wa.me/254712345678?text=Hi%20there',
    );
    expect(
      smsLink('+254712345678', 'Hi').toString(),
      'sms:+254712345678?body=Hi',
    );
  });

  test('due customers: due today or late, or owing over two weeks', () {
    final list = customersFrom([
      loan('A', 100, today.addDays(-20)),
      loan('B', 100, today, due: today),
      loan('C', 100, today, due: today.addDays(3)),
    ], today: today);
    expect(dueCustomers(list, today: today).map((c) => c.name), ['A', 'B']);
  });
}
