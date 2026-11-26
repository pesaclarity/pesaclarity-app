import 'package:ujumbe/ujumbe.dart';

// A made-up month of M-Pesa and bank messages for the money totals audit.
// Every name, number, account and code here is invented.

SmsMessage _sms(String sender, String body, DateTime at) =>
    SmsMessage(sender: sender, body: body, receivedAt: at);

/// Nairobi time to UTC.
DateTime eatTime(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, day, hour - 3, minute);

String _d(int day) => '${day.toString().padLeft(2, '0')}/11/26';

SmsMessage salary() => _sms(
  'KCB',
  'Dear Customer, your acc 1234567890 has been credited KES 50,000.00 '
      'Direct Credits at KCB DATA PROCESSING CENTRE at 10:08:05 on 02 NOV '
      '2026. For any queries call KCB on  +254700000000',
  eatTime(2, 10, 9),
);

/// KCB to the person's own M-Pesa, both sides.
List<SmsMessage> kcbToMpesa() => [
  _sms(
    'KCB',
    'KCB0000000000901  KES 10,000.00 sent from 123****890 to 254****789 - '
        'JANE DOE on 2026-11-03 09:15:00 AM. M-PESA REF: TJA1000001',
    eatTime(3, 9, 15),
  ),
  _sms(
    'MPESA',
    'TJA1000001 Confirmed.You have received Ksh10,000.00 from KCB 1 522522 '
        'on ${_d(3)} at 9:16 AM New M-PESA balance is Ksh10,000.00.',
    eatTime(3, 9, 16),
  ),
];

/// M-Pesa paybill into the person's own KCB account, both sides.
List<SmsMessage> mpesaToKcb() => [
  _sms(
    'MPESA',
    'TJA1000002 Confirmed. Ksh3,000.00 sent to KCB for account 1234567890 on '
        '${_d(4)} at 7:45 PM New M-PESA balance is Ksh6,970.00. Transaction '
        'cost, Ksh30.00.Amount you can transact within the day is 497,000.00.',
    eatTime(4, 19, 45),
  ),
  _sms(
    'KCB',
    'Dear Customer, your acc 1234567890 has been credited KES 3,000.00 Mobi '
        'at KCB DATA PROCESSING CENTRE at 19:45:10 on 04 NOV 2026. For any '
        'queries call KCB on  +254700000000',
    eatTime(4, 19, 46),
  ),
];

List<SmsMessage> mshwari() => [
  _sms(
    'MPESA',
    'TJA1000003 Confirmed.Ksh500.00 transferred to M-Shwari account on '
        '${_d(5)} at 4:00 PM. M-PESA balance is Ksh6,470.00 .New M-Shwari '
        'saving account balance is Ksh500.00. Transaction cost Ksh.0.00',
    eatTime(5, 16),
  ),
  _sms(
    'MPESA',
    'TJA1000004 Confirmed.Ksh200.00 transferred from M-Shwari account on '
        '${_d(5)} at 4:10 PM. M-Shwari balance is Ksh300.00 .M-PESA balance '
        'is Ksh6,670.00 .Transaction cost Ksh.0.00',
    eatTime(5, 16, 10),
  ),
];

SmsMessage till() => _sms(
  'MPESA',
  'TJA1000005 Confirmed. Ksh350.00 paid to EXAMPLE GROCERS. on ${_d(6)} at '
      '1:45 PM.New M-PESA balance is Ksh6,320.00. Transaction cost, Ksh0.00. '
      'Amount you can transact within the day is 496,950.00.',
  eatTime(6, 13, 45),
);

SmsMessage sendToPerson() => _sms(
  'MPESA',
  'TJA1000006 Confirmed. Ksh1,500.00 sent to MARY ATIENO 0700***101 on '
      '${_d(7)} at 9:15 AM. New M-PESA balance is Ksh4,805.00. Transaction '
      'cost, Ksh15.00. Amount you can transact within the day is 498,500.00.',
  eatTime(7, 9, 15),
);

SmsMessage paybill() => _sms(
  'MPESA',
  'TJA1000007 Confirmed. Ksh1,200.00 sent to EXAMPLE POWER LTD for account '
      '1234500001 on ${_d(8)} at 11:30 AM New M-PESA balance is Ksh3,590.00. '
      'Transaction cost, Ksh15.00.Amount you can transact within the day is '
      '497,300.00.',
  eatTime(8, 11, 30),
);

SmsMessage withdraw() => _sms(
  'MPESA',
  'TJA1000008 Confirmed.on ${_d(9)} at 5:10 PMWithdraw Ksh1,000.00 from '
      '123456 - EXAMPLE AGENT SHOP NAIROBI New M-PESA balance is Ksh2,561.00. '
      'Transaction cost, Ksh29.00.',
  eatTime(9, 17, 10),
);

SmsMessage deposit() => _sms(
  'MPESA',
  'TJA1000009 Confirmed. On ${_d(10)} at 2:30 PM Give Ksh2,000.00 cash to '
      'EXAMPLE AGENT SHOP New M-PESA balance is Ksh4,561.00.',
  eatTime(10, 14, 30),
);

SmsMessage airtimeSelf() => _sms(
  'MPESA',
  'TJA1000010 confirmed.You bought Ksh100.00 of airtime on ${_d(11)} at '
      '7:00 PM.New M-PESA balance is Ksh4,461.00. Transaction cost, Ksh0.00.',
  eatTime(11, 19),
);

SmsMessage airtimeOther() => _sms(
  'MPESA',
  'TJA1000011 Confirmed.Ksh50.00 of airtime for 0700000103 on ${_d(11)} at '
      '7:05 PM  New M-PESA balance is Ksh4,411.00.',
  eatTime(11, 19, 5),
);

List<SmsMessage> fuliza() => [
  _sms(
    'MPESA',
    'TJA1000012 Confirmed. Fuliza M-Pesa amount is Ksh 150.00. Access Fee '
        'charged Ksh 1.50. Total Fuliza M-Pesa outstanding amount is Ksh '
        '151.50 due on 12/12/26. To check daily charges, Dial *000*0#OK '
        'Select Query Charges',
    eatTime(12, 8),
  ),
  _sms(
    'MPESA',
    'TJA1000013 Confirmed. Ksh 151.50 from your M-PESA has been used to '
        'fully pay your outstanding Fuliza M-PESA. Available Fuliza M-PESA '
        'limit is Ksh 2,000.00. M-PESA balance is Ksh4,259.50.',
    eatTime(13, 8),
  ),
];

List<SmsMessage> reversedSend() => [
  _sms(
    'MPESA',
    'TJA1000014 Confirmed. Ksh300.00 sent to PETER OTIENO 0700***104 on '
        '${_d(14)} at 9:20 AM. New M-PESA balance is Ksh3,959.50. Transaction '
        'cost, Ksh0.00. Amount you can transact within the day is 498,200.00.',
    eatTime(14, 9, 20),
  ),
  _sms(
    'MPESA',
    'TJA1000015 Confirmed. Reversal of transaction TJA1000014 has been '
        'successfully reversed  on ${_d(14)} at 8:00 PM and Ksh300.00 is '
        'credited to your M-PESA account. New M-PESA account balance is '
        'Ksh4,259.50.',
    eatTime(14, 20),
  ),
];

SmsMessage declinedCard() => _sms(
  'KCB',
  'KES 1,250.00 transaction made on KCB card 4111***0107 at EXAMPLE GROCERS '
      'on 15/11/2026 09:05am has been declined. Reason - Insufficient '
      'funds.Balance KES 120.00. Queries call +254711000000.',
  eatTime(15, 9, 5),
);

SmsMessage loanRepayment() => _sms(
  'KCB',
  'Dear JANE DOE, KES 5000.00 was debited from your KCB account to repay '
      'your KCB Salary Advance 100000101. The loan has been partially paid. '
      'Your loan balance is KES 20000.00, next instalment is due on '
      '15/12/2026. Pay the loan to borrow again.',
  eatTime(16, 9),
);

SmsMessage bankDebit() => _sms(
  'KCB',
  'Dear Customer, KES 2,000.00 has been debited from your account ****7890 '
      'on 17/11/2026 at 15:20. Transaction Ref: KCB0000000107. Your available '
      'balance is KES 37,000.00.',
  eatTime(17, 15, 20),
);

/// To the person's own Airtel Money, both sides.
List<SmsMessage> mpesaToAirtel() => [
  _sms(
    'MPESA',
    'TJA1000016 Confirmed. Ksh100.00 sent to AIRTEL MONEY for account '
        '0730000101 on ${_d(18)} at 3:00 PM New M-PESA balance is '
        'Ksh4,144.50. Transaction cost, Ksh15.00.',
    eatTime(18, 15),
  ),
  _sms(
    'AirtelMoney',
    'TID:TJA1000017. Received Ksh 100 from JANE DOE 254700000101 on '
        '${_d(18)} 03:00 PM. Bal:Ksh 100.0 Sender TID:TJA1000016.',
    eatTime(18, 15),
  ),
];

/// Every message once, in time order.
List<SmsMessage> month() => [
  salary(),
  ...kcbToMpesa(),
  ...mpesaToKcb(),
  ...mshwari(),
  till(),
  sendToPerson(),
  paybill(),
  withdraw(),
  deposit(),
  airtimeSelf(),
  airtimeOther(),
  ...fuliza(),
  ...reversedSend(),
  declinedCard(),
  loanRepayment(),
  bankDebit(),
  ...mpesaToAirtel(),
];
