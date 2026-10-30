import 'package:drift/drift.dart';
import 'package:ujumbe/ujumbe.dart' show dedupeKeyFor;

import '../../../data/database/app_database.dart';
import '../../../domain/payees/payee_identifier.dart';
import '../../../domain/reader/field_values.dart';
import '../../../domain/reader/message_reading.dart';
import '../../../domain/time/calendar.dart';

/// The values of a message under review: the reader's suggestions, then
/// whatever the person changes. Becomes a ledger transaction once it has an
/// amount and is money in or out.
class ReviewDraft {
  const ReviewDraft({
    required this.kind,
    this.amountMinor,
    this.counterparty,
    this.date,
    this.minutes,
    this.balanceMinor,
    this.reference,
    this.feeMinor,
    this.phoneNumber,
  });

  factory ReviewDraft.fromReading(MessageReading reading) {
    String? text(ReaderField f) => reading.fields[f]?.text;
    final party = text(ReaderField.counterparty);
    return ReviewDraft(
      kind: reading.kind,
      amountMinor: _maybe(text(ReaderField.amount), amountMinorFrom),
      counterparty: party == null ? null : counterpartyFrom(party),
      date: _maybe(text(ReaderField.date), dateFrom),
      minutes: _maybe(text(ReaderField.time), minutesFrom),
      balanceMinor: _maybe(text(ReaderField.balance), amountMinorFrom),
      reference: text(ReaderField.reference),
      feeMinor: _maybe(text(ReaderField.fee), amountMinorFrom),
      phoneNumber: party == null
          ? null
          : RegExp(r'[0-9]{2,4}\s*\*+\s*[0-9]+|0[17][0-9]{8}')
                .firstMatch(party)
                ?.group(0),
    );
  }

  static T? _maybe<T>(String? text, T? Function(String) parse) =>
      text == null ? null : parse(text);

  final MessageKind kind;
  final int? amountMinor;
  final String? counterparty;
  final CalendarDate? date;

  /// Minutes after midnight, in the person's timezone.
  final int? minutes;
  final int? balanceMinor;
  final String? reference;
  final int? feeMinor;

  /// A phone number printed with the payee, masked or not.
  final String? phoneNumber;

  /// Whether it can be added to the ledger.
  bool get isComplete =>
      kind != MessageKind.notTransaction &&
      amountMinor != null &&
      amountMinor! > 0;

  /// When it happened: the date and time read, or when the message arrived.
  DateTime occurredAt(DateTime receivedAt) {
    final day = date;
    if (day == null) return receivedAt.toUtc();
    return day.startInstant.add(Duration(minutes: minutes ?? 0));
  }

  ReviewDraft copyWith({
    MessageKind? kind,
    int? amountMinor,
    String? counterparty,
    CalendarDate? date,
    int? minutes,
    String? reference,
  }) => ReviewDraft(
    kind: kind ?? this.kind,
    amountMinor: amountMinor ?? this.amountMinor,
    counterparty: counterparty ?? this.counterparty,
    date: date ?? this.date,
    minutes: minutes ?? this.minutes,
    balanceMinor: balanceMinor,
    reference: reference ?? this.reference,
    feeMinor: feeMinor,
    phoneNumber: phoneNumber,
  );

  /// The ledger row for the institution's account [accountId]. Keeps the
  /// values and the message hash, never the message text.
  TransactionsCompanion toTransaction({
    required int accountId,
    required DateTime receivedAt,
    required String messageHash,
    required String currency,
  }) {
    final when = occurredAt(receivedAt);
    final out = kind == MessageKind.moneyOut;
    final name = counterparty;
    // A phone number in the payee lets a named payee apply; a printed name
    // alone is kept as the name only.
    final phone = phoneNumber == null
        ? null
        : PayeeIdentifier.phone(phoneNumber!);
    return TransactionsCompanion.insert(
      accountId: accountId,
      occurredAt: when,
      amountMinor: amountMinor!,
      direction: out
          ? TransactionDirection.outflow
          : TransactionDirection.inflow,
      kind: Value(out ? TransactionKind.sent : TransactionKind.received),
      feeMinor: Value(feeMinor ?? 0),
      currency: Value(currency),
      counterpartyKind: Value(phone?.kind),
      counterpartyValue: Value(phone?.value),
      counterpartyName: Value(name),
      receiptNo: Value(reference),
      source: TransactionSource.sms,
      messageHash: Value(messageHash),
      dedupeKey: Value(
        dedupeKeyFor(receipt: reference, amountMinor: amountMinor!, time: when),
      ),
      balanceAfterMinor: Value(balanceMinor),
    );
  }
}
