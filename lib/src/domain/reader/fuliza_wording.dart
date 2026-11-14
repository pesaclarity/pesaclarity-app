import '../enums.dart';

final _repaid = RegExp(
  r'used to (?:fully |partially )?(?:re)?pay|'
  r'fuliza.{0,60}?\b(?:repaid|repayment|cleared|paid off)\b|'
  r'\b(?:repaid|repayment of|paid off)\b.{0,60}?fuliza',
);
final _drawn = RegExp(r'fuliza m-?pesa amount is');

/// What a message that no parser rule read is, when its own words say it
/// is Fuliza: a repayment or a draw. Null otherwise.
///
/// Fuliza wording varies ("Fuliza M-Pesa", "Fuliza M-PESA amount", ...),
/// so a repayment the rules missed still clears the debt once the person
/// checks it, instead of counting as money sent.
TransactionKind? fulizaKindIn(String message) {
  final m = message.toLowerCase();
  if (!m.contains('fuliza')) return null;
  if (_repaid.hasMatch(m)) return TransactionKind.fulizaRepayment;
  if (_drawn.hasMatch(m)) return TransactionKind.fulizaDraw;
  return null;
}
