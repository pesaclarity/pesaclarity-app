import '../../domain/enums.dart';
import '../../domain/ledger/activity_lines.dart';

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
