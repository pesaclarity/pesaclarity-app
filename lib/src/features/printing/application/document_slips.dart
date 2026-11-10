import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/documents/receipt.dart';
import '../../../domain/printing/slip.dart';
import '../../../domain/printing/slips.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/format/date_labels.dart' show formatTime;
import '../../sales/presentation/pay_sheet.dart' show methodLabel;

String _plain(int minor) => formatMoney(Money(minor), withCurrency: false);

/// [r] as the counter printer prints it.
Slip slipForReceipt(Receipt r) => receiptSlip(
  r,
  label: methodLabel,
  plain: _plain,
  date: dateLabel(CalendarDate.local(r.at)),
  time: formatTime(r.at),
);
