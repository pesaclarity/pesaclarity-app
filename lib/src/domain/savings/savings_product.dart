import '../enums.dart';

/// A savings app, fund or SACCO the app knows by the name its payments
/// print, so money paid into it counts as saved in an account of the
/// person's own rather than as spending.
class SavingsProduct {
  const SavingsProduct({
    required this.id,
    required this.name,
    required this.provider,
    required this.payeeNames,
    required this.paidThrough,
    this.moneyBackNames,
    this.type = AccountType.moneyMarket,
    this.currency = 'KES',
  });

  /// Kept on the account (`Accounts.product`), so it is never renamed.
  final String id;

  /// What people call it, and the account's first name.
  final String name;

  /// Who holds the money.
  final String provider;

  /// The names paying in prints, as [savingsPayeeKey] reads them. A printed
  /// name fits when its key is one of these, or starts with one and a space.
  final List<String> payeeNames;

  /// The names money coming back prints; [payeeNames] when not given.
  final List<String>? moneyBackNames;

  /// How money gets there, as the person knows it.
  final String paidThrough;

  /// The kind of account it is: one that holds savings.
  final AccountType type;
  final String currency;

  /// Whether paying in to [printed] is paying into this product.
  bool takesPayIn(String? printed) => _fits(printed, payeeNames);

  /// Whether money from [printed] is this product paying back.
  bool paysBack(String? printed) =>
      _fits(printed, moneyBackNames ?? payeeNames);

  static bool _fits(String? printed, List<String> names) {
    if (printed == null) return false;
    final key = savingsPayeeKey(printed);
    if (key.isEmpty) return false;
    return names.any((name) => key == name || key.startsWith('$name '));
  }
}

/// Chumz: a goal-saving app whose money Nabo Capital holds. People pay in
/// through Nabo Capital's M-Pesa paybill, with one account code per goal.
const chumz = SavingsProduct(
  id: 'chumz',
  name: 'Chumz',
  provider: 'Nabo Capital',
  payeeNames: ['NABO CAPITAL'],
  paidThrough: 'M-Pesa paybill NABO CAPITAL LTD',
);

/// Every savings product the app knows. Another savings app, fund or SACCO
/// is one more entry.
const savingsProducts = <SavingsProduct>[chumz];

/// The product with [id] among [products]; null when it is not one of them.
SavingsProduct? savingsProductById(
  String? id, {
  List<SavingsProduct> products = savingsProducts,
}) {
  for (final product in products) {
    if (product.id == id) return product;
  }
  return null;
}

/// How M-Pesa marks the channel a business was paid or paid through.
const _channelWords = {'C2B', 'B2C', 'B2B'};

/// [printed], a business name as a message or statement prints it, in the
/// form products are matched by: upper case, single spaces, no dots at the
/// end and no channel word after the name, so `Nabo Capital Ltd C2B.` reads
/// `NABO CAPITAL LTD`.
String savingsPayeeKey(String printed) {
  final words = printed
      .toUpperCase()
      .replaceAll(RegExp(r'[.\s]+$'), '')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.length > 1 && _channelWords.contains(words.last)) {
    words.removeLast();
  }
  return words.join(' ').replaceAll(RegExp(r'\.+$'), '');
}

/// Money moving between one of the person's accounts and a savings product.
sealed class SavingsMove {
  const SavingsMove(this.product);

  final SavingsProduct product;
}

/// Money paid into [product] under the account [code], which is empty when
/// the payment names none.
class SavingsPayIn extends SavingsMove {
  const SavingsPayIn(super.product, this.code);

  final String code;
}

/// Money [product] paid back.
class SavingsMoneyBack extends SavingsMove {
  const SavingsMoneyBack(super.product);
}

/// What a transaction on one of the person's day-to-day accounts is to a
/// savings product in [products], or null when it has nothing to do with
/// one.
///
/// Paying a paybill whose name a product takes is paying in, under the
/// account code the payment gives (the text after `#` in a paybill's
/// [counterpartyValue], as `PayeeIdentifier.paybill` writes it). Money
/// received from a name a product pays back under is money back. How money
/// back is worded is not confirmed yet, so only [SavingsProduct] says which
/// names count: a transaction this does not recognise is left as it is.
SavingsMove? savingsMoveOf({
  required TransactionKind? kind,
  required TransactionDirection direction,
  PayeeIdentifierKind? counterpartyKind,
  String? counterpartyValue,
  String? counterpartyName,
  List<SavingsProduct> products = savingsProducts,
}) {
  if (kind == TransactionKind.paybill &&
      direction == TransactionDirection.outflow) {
    final paybill = counterpartyKind == PayeeIdentifierKind.paybill
        ? counterpartyValue
        : null;
    final at = paybill?.indexOf('#') ?? -1;
    final business = at < 0 ? paybill : paybill!.substring(0, at);
    final code = at < 0 ? '' : paybill!.substring(at + 1);
    for (final product in products) {
      if (product.takesPayIn(counterpartyName) ||
          product.takesPayIn(business)) {
        return SavingsPayIn(product, code);
      }
    }
    return null;
  }
  if (kind == TransactionKind.received &&
      direction == TransactionDirection.inflow) {
    for (final product in products) {
      if (product.paysBack(counterpartyName)) return SavingsMoneyBack(product);
    }
  }
  return null;
}
