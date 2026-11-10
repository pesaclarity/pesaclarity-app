import 'package:ujumbe/ujumbe.dart';

// Synthetic messages in the shape of the ujumbe pack fixtures: fake names,
// masked fake numbers and made-up receipts.

SmsMessage mpesaSent({
  String receipt = 'TJA0000001',
  DateTime? receivedAt,
}) => SmsMessage(
  sender: 'MPESA',
  body:
      '$receipt Confirmed. Ksh1,500.00 sent to JANE DOE 0700***001 on '
      '26/10/26 at 9:15 AM. New M-PESA balance is Ksh3,250.00. Transaction '
      'cost, Ksh15.00. Amount you can transact within the day is 498,500.00.',
  receivedAt: receivedAt ?? DateTime.utc(2026, 10, 26, 6, 15, 5),
);

SmsMessage mpesaTill({DateTime? receivedAt}) => SmsMessage(
  sender: 'MPESA',
  body:
      'TJA0000004 Confirmed. Ksh350.00 paid to EXAMPLE GROCERS. on 26/10/26 '
      'at 1:45 PM.New M-PESA balance is Ksh3,685.00. Transaction cost, '
      'Ksh0.00. Amount you can transact within the day is 496,950.00.',
  receivedAt: receivedAt ?? DateTime.utc(2026, 10, 26, 10, 45, 5),
);

SmsMessage mpesaNotice({DateTime? receivedAt}) => SmsMessage(
  sender: 'MPESA',
  body:
      'Dear Customer, M-PESA services will be briefly unavailable tonight '
      'from 11:00 PM for planned maintenance.',
  receivedAt: receivedAt ?? DateTime.utc(2026, 10, 26, 12),
);

SmsMessage kcbDebit({DateTime? receivedAt}) => SmsMessage(
  sender: 'KCB',
  body:
      'Dear Customer, KES 3,000.00 has been debited from your account '
      '****0001 on 26/10/2026 at 15:20. Transaction Ref: KCB0000000001. Your '
      'available balance is KES 7,000.00.',
  receivedAt: receivedAt ?? DateTime.utc(2026, 10, 26, 12, 20, 5),
);

SmsMessage personal({DateTime? receivedAt}) => SmsMessage(
  sender: '0700000000',
  body: 'See you at six. Bring the receipt, KES 500 sent.',
  receivedAt: receivedAt ?? DateTime.utc(2026, 10, 26, 13),
);

/// A credit to an Equity account in [currency], numbered [account].
SmsMessage equityReceived({
  String currency = 'KES',
  String account = '0170****4321',
  String amount = '2,000.00',
  String receipt = 'EQB0000000000002',
  DateTime? receivedAt,
}) => SmsMessage(
  sender: 'EQUITYBANK',
  body:
      'You have received $amount $currency from EXAMPLE TRADERS to your '
      'Equity account $account. Ref. $receipt on 12 Sep 2026 at 14:05 EAT',
  receivedAt: receivedAt ?? DateTime.utc(2026, 9, 12, 11, 5, 5),
);
