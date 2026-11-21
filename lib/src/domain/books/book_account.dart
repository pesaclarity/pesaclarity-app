/// What kind of thing a book account is, for the sign of its balance and for
/// reports.
enum BookAccountClass {
  /// Something the space has: cash, M-Pesa, a bank account, savings.
  asset,

  /// Something the space owes: Fuliza, loans, money waiting to be named.
  liability,

  /// What is left for the owner: opening balances, differences with
  /// reported balances, and money the owner took out.
  equity,

  /// Money earned.
  income,

  /// Money spent: costs, fees and tax.
  expense,
}

/// The fixed accounts every space's books have, besides one per money
/// account and one per category.
enum BookAccountKind {
  /// One of the space's accounts (M-Pesa, cash, a bank): [BookAccount.id] is
  /// the account's id.
  money(BookAccountClass.asset),

  /// A category of income: [BookAccount.id] is the category id.
  incomeCategory(BookAccountClass.income),

  /// A category of spending: [BookAccount.id] is the category id.
  spendingCategory(BookAccountClass.expense),

  /// Income with no category yet.
  uncategorisedIncome(BookAccountClass.income),

  /// Spending with no category yet.
  uncategorisedSpending(BookAccountClass.expense),

  /// Bank and wallet charges, transaction costs and the Fuliza fee share.
  fees(BookAccountClass.expense),

  /// Tax paid.
  tax(BookAccountClass.expense),

  /// Money put into savings held elsewhere.
  savings(BookAccountClass.asset),

  /// Borrowed money still owed, such as Fuliza or a family loan.
  borrowed(BookAccountClass.liability),

  /// Money received from someone not named yet; neutral until it is.
  awaitingPayee(BookAccountClass.liability),

  /// Money on its way between the space's own accounts. Both halves of a
  /// transfer meet here, so it nets to zero once both are recorded.
  ownTransfers(BookAccountClass.asset),

  /// What customers owe for sales on credit.
  owedToYou(BookAccountClass.asset),

  /// What the business owes suppliers for stock or costs bought on credit.
  owedToSuppliers(BookAccountClass.liability),

  /// Stock on hand, at what it cost: owned until it sells.
  stock(BookAccountClass.asset),

  /// What sold stock cost, at the average cost.
  costOfSales(BookAccountClass.expense),

  /// Stock spoiled, used or lost, at the average cost.
  stockLosses(BookAccountClass.expense),

  /// Money the owner took out of a business ("Paid yourself").
  ownerPay(BookAccountClass.equity),

  /// What the accounts held when the books start.
  openingBalances(BookAccountClass.equity),

  /// Differences between the records and a balance the bank or M-Pesa
  /// reported, such as from a missing message.
  balanceDifferences(BookAccountClass.equity),

  /// The journal's suspense account: money whose meaning is not known yet,
  /// such as money in from someone not named, or the part of a reported
  /// balance the records do not explain.
  notYetSorted(BookAccountClass.liability),

  /// Fuliza owed on one M-Pesa account: [BookAccount.id] is the M-Pesa
  /// account's id. Draws and their fees credit it; repayments debit it.
  fulizaOwed(BookAccountClass.liability),

  /// Balance corrections the person recorded, such as setting a balance
  /// or saying Fuliza is paid.
  balanceCorrections(BookAccountClass.equity),

  /// What Fuliza charged: access fees, daily charges and what repayments
  /// took beyond what was owed, whether a message said so or the balances
  /// show it.
  fulizaCharges(BookAccountClass.expense),

  /// The trading account of own transfers across currencies: what was
  /// sold in one currency and bought in another, so every entry sums to
  /// zero in its own currency. Zero in the base at the day's rates; what
  /// is left is a move in value between the days of a transfer's two
  /// sides, when the base is a third currency.
  currencyExchange(BookAccountClass.asset),

  /// What own transfers across currencies cost against the day's rate: the
  /// money out less what the money in was worth that day. Counted with
  /// fees; negative when more came in than the day's rate gives.
  exchangeCost(BookAccountClass.expense);

  const BookAccountKind(this.accountClass);

  final BookAccountClass accountClass;

  /// Whether accounts of this kind carry an id.
  bool get hasId =>
      this == money ||
      this == incomeCategory ||
      this == spendingCategory ||
      this == fulizaOwed;
}

/// One account in a space's books.
class BookAccount {
  const BookAccount._(this.kind, this.id);

  /// One of the space's money accounts.
  const BookAccount.money(int accountId)
    : this._(BookAccountKind.money, accountId);

  /// A category, as income or spending.
  const BookAccount.category(int categoryId, {required bool income})
    : this._(
        income
            ? BookAccountKind.incomeCategory
            : BookAccountKind.spendingCategory,
        categoryId,
      );

  /// One of the fixed accounts.
  const BookAccount.fixed(BookAccountKind kind) : this._(kind, null);

  /// Fuliza owed on M-Pesa account [accountId].
  const BookAccount.fulizaOwed(int accountId)
    : this._(BookAccountKind.fulizaOwed, accountId);

  /// Kinds by name, built once: reading the journal parses every posting's
  /// account.
  static final _kinds = BookAccountKind.values.asNameMap();

  /// The account a stored [key] names (see [key]); null when it names none.
  static BookAccount? parse(String key) {
    final colon = key.indexOf(':');
    final kind = _kinds[colon < 0 ? key : key.substring(0, colon)];
    if (kind == null) return null;
    if (!kind.hasId) return colon < 0 ? BookAccount.fixed(kind) : null;
    final id = colon < 0 ? null : int.tryParse(key.substring(colon + 1));
    return id == null ? null : BookAccount._(kind, id);
  }

  static const uncategorisedIncome = BookAccount.fixed(
    BookAccountKind.uncategorisedIncome,
  );
  static const uncategorisedSpending = BookAccount.fixed(
    BookAccountKind.uncategorisedSpending,
  );
  static const fees = BookAccount.fixed(BookAccountKind.fees);
  static const tax = BookAccount.fixed(BookAccountKind.tax);
  static const savings = BookAccount.fixed(BookAccountKind.savings);
  static const borrowed = BookAccount.fixed(BookAccountKind.borrowed);
  static const awaitingPayee = BookAccount.fixed(BookAccountKind.awaitingPayee);
  static const ownTransfers = BookAccount.fixed(BookAccountKind.ownTransfers);
  static const owedToYou = BookAccount.fixed(BookAccountKind.owedToYou);
  static const owedToSuppliers = BookAccount.fixed(
    BookAccountKind.owedToSuppliers,
  );
  static const stock = BookAccount.fixed(BookAccountKind.stock);
  static const costOfSales = BookAccount.fixed(BookAccountKind.costOfSales);
  static const stockLosses = BookAccount.fixed(BookAccountKind.stockLosses);
  static const ownerPay = BookAccount.fixed(BookAccountKind.ownerPay);
  static const openingBalances = BookAccount.fixed(
    BookAccountKind.openingBalances,
  );
  static const balanceDifferences = BookAccount.fixed(
    BookAccountKind.balanceDifferences,
  );
  static const notYetSorted = BookAccount.fixed(BookAccountKind.notYetSorted);
  static const fulizaCharges = BookAccount.fixed(BookAccountKind.fulizaCharges);
  static const currencyExchange = BookAccount.fixed(
    BookAccountKind.currencyExchange,
  );
  static const exchangeCost = BookAccount.fixed(BookAccountKind.exchangeCost);

  /// Money on its way between accounts: the journal's clearing account.
  static const moneyInTransit = ownTransfers;
  static const balanceCorrections = BookAccount.fixed(
    BookAccountKind.balanceCorrections,
  );

  final BookAccountKind kind;

  /// The money account or category id, for kinds that have one.
  final int? id;

  BookAccountClass get accountClass => kind.accountClass;

  /// How the journal stores this account: the kind's name, then `:` and the
  /// id for kinds that have one, such as `money:3`. Kind names are stored,
  /// so they are never renamed.
  String get key => id == null ? kind.name : '${kind.name}:$id';

  /// Whether a debit raises this account's balance (assets and expenses).
  bool get debitNormal =>
      accountClass == BookAccountClass.asset ||
      accountClass == BookAccountClass.expense;

  @override
  bool operator ==(Object other) =>
      other is BookAccount && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => id == null
      ? 'BookAccount(${kind.name})'
      : 'BookAccount(${kind.name} $id)';
}
