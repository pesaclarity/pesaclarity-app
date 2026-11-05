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

  /// Money the owner took out of a business ("Paid yourself").
  ownerPay(BookAccountClass.equity),

  /// What the accounts held when the books start.
  openingBalances(BookAccountClass.equity),

  /// Differences between the records and a balance the bank or M-Pesa
  /// reported, such as from a missing message.
  balanceDifferences(BookAccountClass.equity);

  const BookAccountKind(this.accountClass);

  final BookAccountClass accountClass;

  /// Whether accounts of this kind carry an id.
  bool get hasId =>
      this == money || this == incomeCategory || this == spendingCategory;
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
  static const ownerPay = BookAccount.fixed(BookAccountKind.ownerPay);
  static const openingBalances = BookAccount.fixed(
    BookAccountKind.openingBalances,
  );
  static const balanceDifferences = BookAccount.fixed(
    BookAccountKind.balanceDifferences,
  );

  final BookAccountKind kind;

  /// The money account or category id, for kinds that have one.
  final int? id;

  BookAccountClass get accountClass => kind.accountClass;

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
