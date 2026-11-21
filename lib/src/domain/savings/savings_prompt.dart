import 'savings_product.dart';

/// One account code found in the payments to a savings product, which
/// becomes a pocket to name.
class SavingsCodeFound {
  const SavingsCodeFound({
    required this.code,
    required this.payments,
    required this.paidInMinor,
    required this.firstAt,
    required this.lastAt,
  });

  /// The code as payments carry it, such as `CH12345`; empty for payments
  /// that name none.
  final String code;

  /// How many payments carried it, and what they add up to.
  final int payments;
  final int paidInMinor;
  final DateTime firstAt;
  final DateTime lastAt;
}

/// What the person's records show of a savings product: the payments that
/// adding it would turn into transfers to an account of their own.
class SavingsDiscovery {
  const SavingsDiscovery({
    required this.product,
    this.codes = const [],
    this.payments = 0,
    this.moneyBack = 0,
    this.paidInMinor = 0,
    this.takenOutMinor = 0,
    this.skipped = 0,
    this.firstAt,
    this.latestPayIn,
  });

  final SavingsProduct product;

  /// The codes paid into, in the order they were first paid.
  final List<SavingsCodeFound> codes;

  /// Payments in, and money that came back, that adding it would link.
  final int payments;
  final int moneyBack;
  final int paidInMinor;
  final int takenOutMinor;

  /// Payments left as they are: in another currency than the product's, or
  /// matched by hand to another of the person's accounts.
  final int skipped;

  /// The earliest of them; null when there are none.
  final DateTime? firstAt;

  /// The newest payment in, which the question is asked under.
  final SavingsPrompt? latestPayIn;

  /// Whether the records show any money paid in or back.
  bool get found => payments + moneyBack > 0;
}

/// The question "Is this your savings?", asked once under a payment to a
/// savings product the person has not added.
class SavingsPrompt {
  const SavingsPrompt({
    required this.product,
    required this.transactionId,
    required this.accountId,
    required this.at,
    required this.amountMinor,
    required this.currency,
    required this.paidTo,
    required this.code,
  });

  final SavingsProduct product;

  /// The payment it is asked under, and the account it was paid from.
  final int transactionId;
  final int accountId;
  final DateTime at;
  final int amountMinor;
  final String currency;

  /// Who the payment names, as printed but without the channel M-Pesa adds,
  /// such as `NABO CAPITAL LTD`.
  final String paidTo;

  /// The account code it was paid under; empty when it names none.
  final String code;
}

/// A pocket as the person names it when adding a savings product.
class SavingsPocketDraft {
  const SavingsPocketDraft({
    required this.code,
    required this.name,
    this.lockedUntil,
  });

  final String code;
  final String name;

  /// The start of the day it unlocks; null when it is open.
  final DateTime? lockedUntil;
}

/// What adding a savings product did.
class SavingsAdded {
  const SavingsAdded({
    required this.accountId,
    required this.linked,
    required this.skipped,
  });

  /// The new account.
  final int accountId;

  /// Payments and money back now counted as transfers.
  final int linked;

  /// Payments left as they were (see [SavingsDiscovery.skipped]).
  final int skipped;
}

/// The line shown once after a savings product is added: under which
/// payment, and how many older ones changed with it.
class SavingsAddedNotice {
  const SavingsAddedNotice({
    required this.accountId,
    required this.transactionId,
    required this.updated,
    required this.at,
    this.seen = false,
  });

  static SavingsAddedNotice? fromJson(Map<String, Object?>? json) {
    final accountId = json?['accountId'];
    final transactionId = json?['transactionId'];
    final updated = json?['updated'];
    final at = switch (json?['at']) {
      final String s => DateTime.tryParse(s),
      _ => null,
    };
    if (accountId is! int ||
        transactionId is! int ||
        updated is! int ||
        at == null) {
      return null;
    }
    return SavingsAddedNotice(
      accountId: accountId,
      transactionId: transactionId,
      updated: updated,
      at: at,
      seen: json?['seen'] == true,
    );
  }

  /// The setting it is kept under.
  static const settingsKey = 'savings.added';

  /// The savings account that was added.
  final int accountId;

  /// The payment the question was asked under, where the line shows.
  final int transactionId;

  /// How many other payments now count as transfers too.
  final int updated;

  /// When the account was added.
  final DateTime at;
  final bool seen;

  SavingsAddedNotice asSeen() => SavingsAddedNotice(
    accountId: accountId,
    transactionId: transactionId,
    updated: updated,
    at: at,
    seen: true,
  );

  Map<String, Object?> toJson() => {
    'accountId': accountId,
    'transactionId': transactionId,
    'updated': updated,
    'at': at.toUtc().toIso8601String(),
    'seen': seen,
  };
}

/// The setting that keeps the products the person said are not theirs, or
/// removed. Kept when a space's records are cleared.
const savingsDeclinedKey = 'savings.declined';

/// The product ids in a [savingsDeclinedKey] setting.
Set<String> declinedProductsFromJson(Map<String, Object?>? json) => {
  for (final id in json?['products'] as List<Object?>? ?? const [])
    if (id is String) id,
};

Map<String, Object?> declinedProductsToJson(Set<String> ids) => {
  'products': ids.toList()..sort(),
};
