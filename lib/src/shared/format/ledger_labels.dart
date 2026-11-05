import '../../domain/enums.dart';
import '../../domain/ledger/activity_lines.dart';
import '../../domain/ledger/ledger_entry.dart';

/// A plain name for an entry of [kind], for when nothing better is known.
String kindLabel(TransactionKind kind) => switch (kind) {
  TransactionKind.sent => 'Money sent',
  TransactionKind.received => 'Money received',
  TransactionKind.paybill => 'Paybill',
  TransactionKind.till => 'Buy Goods',
  TransactionKind.withdrawal => 'Cash withdrawal',
  TransactionKind.deposit => 'Cash deposit',
  TransactionKind.airtime => 'Airtime',
  TransactionKind.fulizaDraw => 'Fuliza',
  TransactionKind.fulizaRepayment => 'Fuliza repayment',
  TransactionKind.roundUp => 'Round-up',
  TransactionKind.charge => 'Charge',
  TransactionKind.reversal => 'Reversal',
  TransactionKind.bank => 'Bank transaction',
};

/// The title of a day's [NoiseGroup] line.
String noiseTitle(NoiseGroup group) => switch (group) {
  NoiseGroup.fulizaDraws => 'Fuliza draws',
  NoiseGroup.fulizaRepayments => 'Fuliza repayments',
  NoiseGroup.roundUps => 'Round-ups to savings',
  NoiseGroup.charges => 'Charges',
  NoiseGroup.airtime => 'Airtime',
};

/// A cash book line's title: what it was for, then who with, such as
/// `Sale · Grace W.`; without a category, who with or what kind it was.
String cashBookTitle(LedgerEntry entry, {String? categoryName}) {
  final party = entry.payeeName ?? entry.counterpartyName ?? entry.note;
  final parts = [?categoryName, ?party];
  if (parts.isNotEmpty) return parts.join(' · ');
  return entry.counterpartyValue ?? kindLabel(entry.kind);
}
