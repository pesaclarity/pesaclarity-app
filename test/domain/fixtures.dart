import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';

/// A UTC instant for a Nairobi wall-clock time (EAT is UTC+3).
DateTime eat(int year, int month, int day, [int hour = 12, int minute = 0]) =>
    DateTime.utc(year, month, day, hour - 3, minute);

/// KES shillings to minor units.
int kes(int shillings) => shillings * 100;

var _nextId = 1;

LedgerEntry entry({
  required DateTime at,
  required int amount,
  TransactionDirection direction = TransactionDirection.outflow,
  TransactionKind kind = TransactionKind.till,
  int? id,
  int accountId = 1,
  String currency = 'KES',
  int fee = 0,
  int? payeeId,
  int? categoryId,
  CategoryType? categoryType,
  bool isDailySpending = false,
  int? transferPairId,
}) => LedgerEntry(
  id: id ?? _nextId++,
  accountId: accountId,
  occurredAt: at,
  amountMinor: amount,
  direction: direction,
  kind: kind,
  currency: currency,
  feeMinor: fee,
  payeeId: payeeId,
  categoryId: categoryId,
  categoryType: categoryType,
  isDailySpending: isDailySpending,
  transferPairId: transferPairId,
);

LedgerEntry inflow({
  required DateTime at,
  required int amount,
  TransactionKind kind = TransactionKind.received,
  int? id,
  int accountId = 1,
  String currency = 'KES',
  int? payeeId,
  int? categoryId,
  CategoryType? categoryType,
}) => entry(
  at: at,
  amount: amount,
  direction: TransactionDirection.inflow,
  kind: kind,
  id: id,
  accountId: accountId,
  currency: currency,
  payeeId: payeeId,
  categoryId: categoryId,
  categoryType: categoryType,
);
