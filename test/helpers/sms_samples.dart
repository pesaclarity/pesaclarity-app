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

/// A message from M-Pesa with [body], received at [receivedAt].
SmsMessage mpesaSms(String body, DateTime receivedAt) =>
    SmsMessage(sender: 'MPESA', body: body, receivedAt: receivedAt);

/// A message from KCB with [body], received at [receivedAt].
SmsMessage kcbSms(String body, DateTime receivedAt) =>
    SmsMessage(sender: 'KCB', body: body, receivedAt: receivedAt);

/// KCB's plain alert when a KES 8,000.00 PesaLink transfer starts. It
/// prints no reference; [kcbPesalinkDone] is the same transfer.
SmsMessage kcbPesalinkAlert() => kcbSms(
  'Dear Customer, your acc 1234567890 has been debited KES 8,000.00 '
  'Pesalink Outgoing at KCB DATA PROCESSING CENTRE at 10:12:30 on 06 NOV '
  '2026. For any queries call KCB on  +254700000000',
  DateTime.utc(2026, 11, 6, 7, 12, 35),
);

/// KCB's confirmation, with its reference, once that transfer completes.
SmsMessage kcbPesalinkDone() => kcbSms(
  '0001000720261106101500abcd1234 Completed. Your SEND TO PESALINK request '
  'of KES 8,000.00 from 123****890 to 555****321 - JANE AKINYI DOE at '
  '2026-11-06 10:15:00 AM has been processed successfully. Transaction cost '
  'KES 15.00  Incl. Tax Amount KES 2.00. Pata extra cash with a flexible '
  'Mobile Loan of up to KES 100K. Dial *000# or use the KCB App.',
  DateTime.utc(2026, 11, 6, 7, 15, 5),
);

/// KCB taking a salary advance repayment of [amount], with what is [left]
/// on the loan and when the next instalment is [due].
SmsMessage kcbLoanRepaid(
  String amount,
  String left,
  DateTime receivedAt, {
  String due = '05/12/2026',
}) => kcbSms(
  'Dear JANE, KES $amount was debited from your KCB account to repay your '
  'KCB Salary Advance 12345. The loan has been partially paid. Your loan '
  'balance is KES $left, next instalment is due on $due.',
  receivedAt,
);
