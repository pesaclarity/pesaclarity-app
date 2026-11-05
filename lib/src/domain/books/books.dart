import '../enums.dart';
import '../ledger/balances.dart';
import '../ledger/fuliza.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import '../spaces/space_categories.dart';
import 'book_account.dart';

/// What a journal entry was made from.
enum JournalSource {
  /// A transaction: [JournalEntry.sourceId] is its id.
  transaction,

  /// An account's opening balance: [JournalEntry.sourceId] is the account id.
  opening,

  /// A balance the bank or M-Pesa reported that the records did not reach:
  /// [JournalEntry.sourceId] is the transaction that carried the balance, or
  /// the account id for the start of the account.
  balanceDifference,

  /// The part of a sale a customer pays later: [JournalEntry.sourceId] is
  /// the sale payment's id.
  creditSale,

  /// Stock or a cost bought to pay later: [JournalEntry.sourceId] is the
  /// record's id.
  creditPurchase,

  /// What a customer owed, or the business owed a supplier, before its
  /// records: [JournalEntry.sourceId] is the loan's or debt's id.
  owedBefore,
}

/// One line of a journal entry. Positive is a debit, negative a credit.
class JournalLine {
  const JournalLine(this.account, this.amountMinor);

  final BookAccount account;
  final int amountMinor;

  @override
  String toString() => 'JournalLine($account, $amountMinor)';
}

/// A balanced set of lines: debits equal credits.
class JournalEntry {
  JournalEntry({
    required this.source,
    required this.sourceId,
    required this.at,
    required this.currency,
    required Iterable<JournalLine> lines,
  }) : lines = List.unmodifiable(lines.where((l) => l.amountMinor != 0));

  final JournalSource source;
  final int sourceId;
  final DateTime at;
  final String currency;
  final List<JournalLine> lines;

  bool get isBalanced => lines.fold(0, (sum, l) => sum + l.amountMinor) == 0;

  @override
  String toString() => 'JournalEntry(${source.name} $sourceId, $lines)';
}

/// Category facts the posting needs, by category id.
typedef BookCategory = ({String? key, CategoryType type});

/// The part of a sale a customer pays later, as the books need it.
class CreditSale {
  const CreditSale({
    required this.paymentId,
    required this.at,
    required this.amountMinor,
    required this.currency,
    required this.salesCategoryId,
  });

  final int paymentId;
  final DateTime at;
  final int amountMinor;
  final String currency;

  /// The income category the sale counts under.
  final int salesCategoryId;
}

/// Stock or a cost bought to pay later, as the books need it.
class CreditPurchase {
  const CreditPurchase({
    required this.recordId,
    required this.at,
    required this.amountMinor,
    required this.currency,
    required this.categoryId,
  });

  final int recordId;
  final DateTime at;
  final int amountMinor;
  final String currency;

  /// The cost category it counts under.
  final int categoryId;
}

/// Money owed from before the records: by a customer to the business
/// ([toYou]), or by the business to a supplier.
class OwedBefore {
  const OwedBefore({
    required this.sourceId,
    required this.at,
    required this.amountMinor,
    required this.currency,
    required this.toYou,
  });

  final int sourceId;
  final DateTime at;
  final int amountMinor;
  final String currency;
  final bool toYou;
}

/// Category key whose outflows are the owner taking money out.
const ownerPayCategoryKey = 'owner_pay';

/// A space's double-entry books, worked out from its transactions and
/// accounts. Nothing here is stored: the books always follow the records.
///
/// Every transaction posts by its [LedgerRole], so the books agree with the
/// totals the rest of the app shows. Where a reported balance differs from
/// what the records add up to, a balance difference entry keeps each money
/// account equal to [balanceAt]. A sale on credit counts as a sale when it
/// is made, against what the customer owes, and their payment later clears
/// it; stock or a cost bought on credit works the same way with suppliers.
class Books {
  Books._(this.entries);

  factory Books.of(
    Iterable<LedgerEntry> history, {
    required Iterable<AccountOpening> accounts,
    required Map<int, BookCategory> categories,
    Iterable<CreditSale> credits = const [],
    Iterable<CreditPurchase> purchases = const [],
    Iterable<OwedBefore> owedBefore = const [],
  }) {
    final all = history.toList();
    final fuliza = FulizaLedger.of(all);
    final out = <JournalEntry>[];
    for (final e in all) {
      out.add(postEntry(e, categories: categories, fulizaFee: fuliza.feeOf(e)));
    }
    for (final account in accounts) {
      out.addAll(_openingAndDifferences(account, all));
    }
    for (final c in credits) {
      out.add(
        JournalEntry(
          source: JournalSource.creditSale,
          sourceId: c.paymentId,
          at: c.at,
          currency: c.currency,
          lines: [
            JournalLine(BookAccount.owedToYou, c.amountMinor),
            JournalLine(
              BookAccount.category(c.salesCategoryId, income: true),
              -c.amountMinor,
            ),
          ],
        ),
      );
    }
    // By time; at the same instant an opening comes first and a balance
    // difference last, after the transaction that reported the balance.
    int rank(JournalSource s) => switch (s) {
      JournalSource.opening || JournalSource.owedBefore => 0,
      JournalSource.transaction ||
      JournalSource.creditSale ||
      JournalSource.creditPurchase => 1,
      JournalSource.balanceDifference => 2,
    };
    for (final p in purchases) {
      out.add(
        JournalEntry(
          source: JournalSource.creditPurchase,
          sourceId: p.recordId,
          at: p.at,
          currency: p.currency,
          lines: [
            JournalLine(
              BookAccount.category(p.categoryId, income: false),
              p.amountMinor,
            ),
            JournalLine(BookAccount.owedToSuppliers, -p.amountMinor),
          ],
        ),
      );
    }
    for (final o in owedBefore) {
      final owed = o.toYou
          ? BookAccount.owedToYou
          : BookAccount.owedToSuppliers;
      final sign = o.toYou ? 1 : -1;
      out.add(
        JournalEntry(
          source: JournalSource.owedBefore,
          sourceId: o.sourceId,
          at: o.at,
          currency: o.currency,
          lines: [
            JournalLine(owed, sign * o.amountMinor),
            JournalLine(BookAccount.openingBalances, -sign * o.amountMinor),
          ],
        ),
      );
    }
    out.sort((a, b) {
      final byTime = a.at.compareTo(b.at);
      return byTime != 0 ? byTime : rank(a.source).compareTo(rank(b.source));
    });
    return Books._(List.unmodifiable(out));
  }

  final List<JournalEntry> entries;

  /// Entries that do not balance. Empty unless something is wrong.
  List<JournalEntry> get unbalanced => [
    for (final e in entries)
      if (!e.isBalanced) e,
  ];

  /// The balance of [account] in [currency] from entries before [to] (and
  /// from [from], when given), positive in the account's normal direction:
  /// what an asset holds, what is owed, what was earned or spent.
  int balanceOf(
    BookAccount account, {
    required String currency,
    DateTime? from,
    DateTime? to,
  }) {
    var sum = 0;
    for (final e in entries) {
      if (e.currency != currency) continue;
      if (from != null && e.at.isBefore(from)) continue;
      if (to != null && !e.at.isBefore(to)) continue;
      for (final l in e.lines) {
        if (l.account == account) sum += l.amountMinor;
      }
    }
    return account.debitNormal ? sum : -sum;
  }

  /// Every account's debit-positive total in [currency] before [to]. Sums to
  /// zero when the books balance.
  Map<BookAccount, int> trialBalance({required String currency, DateTime? to}) {
    final out = <BookAccount, int>{};
    for (final e in entries) {
      if (e.currency != currency) continue;
      if (to != null && !e.at.isBefore(to)) continue;
      for (final l in e.lines) {
        out[l.account] = (out[l.account] ?? 0) + l.amountMinor;
      }
    }
    return out;
  }

  /// Total of [classOf] accounts in [currency] for entries in `[from, to)`.
  int totalOf(
    BookAccountClass classOf, {
    required String currency,
    required DateTime from,
    required DateTime to,
  }) {
    var sum = 0;
    for (final e in entries) {
      if (e.currency != currency || e.at.isBefore(from) || !e.at.isBefore(to)) {
        continue;
      }
      for (final l in e.lines) {
        if (l.account.accountClass == classOf) sum += l.amountMinor;
      }
    }
    final debitNormal =
        classOf == BookAccountClass.asset ||
        classOf == BookAccountClass.expense;
    return debitNormal ? sum : -sum;
  }

  /// Income less costs (spending, fees and tax) for `[from, to)`.
  int profit({
    required String currency,
    required DateTime from,
    required DateTime to,
  }) =>
      totalOf(BookAccountClass.income, currency: currency, from: from, to: to) -
      totalOf(BookAccountClass.expense, currency: currency, from: from, to: to);
}

/// Posts one transaction. [fulizaFee] is the fee share of a Fuliza
/// repayment, from [FulizaLedger].
JournalEntry postEntry(
  LedgerEntry e, {
  required Map<int, BookCategory> categories,
  int fulizaFee = 0,
}) {
  final money = BookAccount.money(e.accountId);
  final amount = e.amountMinor;
  final category = e.categoryId == null ? null : categories[e.categoryId];
  final lines = <JournalLine>[];

  // Money moving: debit what it went to, credit the money account (out), or
  // the other way round (in).
  void outTo(BookAccount account, int minor) {
    lines
      ..add(JournalLine(account, minor))
      ..add(JournalLine(money, -minor));
  }

  void inFrom(BookAccount account, int minor) {
    lines
      ..add(JournalLine(money, minor))
      ..add(JournalLine(account, -minor));
  }

  BookAccount incomeAccount() => e.categoryId != null && category != null
      ? BookAccount.category(e.categoryId!, income: true)
      : BookAccount.uncategorisedIncome;
  BookAccount spendingAccount() => e.categoryId != null && category != null
      ? BookAccount.category(e.categoryId!, income: false)
      : BookAccount.uncategorisedSpending;

  final ownerPay = category?.key == ownerPayCategoryKey;
  final fromCustomer = category?.key == customerPaymentsKey;
  final toSupplier = category?.key == supplierPaymentsKey;
  switch (roleOf(e)) {
    case LedgerRole.income when fromCustomer:
      e.isInflow
          ? inFrom(BookAccount.owedToYou, amount)
          : outTo(BookAccount.owedToYou, amount);
    case LedgerRole.income:
      e.isInflow
          ? inFrom(incomeAccount(), amount)
          : outTo(incomeAccount(), amount);
    case LedgerRole.spending:
      e.isOutflow
          ? outTo(spendingAccount(), amount)
          : inFrom(spendingAccount(), amount);
    case LedgerRole.fee:
      outTo(BookAccount.fees, amount);
    case LedgerRole.tax:
      outTo(BookAccount.tax, amount);
    case LedgerRole.saving:
      outTo(BookAccount.savings, amount);
    case LedgerRole.borrowing:
      e.isInflow
          ? inFrom(BookAccount.borrowed, amount)
          : outTo(BookAccount.borrowed, amount);
    case LedgerRole.debtRepayment when toSupplier:
      e.isOutflow
          ? outTo(BookAccount.owedToSuppliers, amount)
          : inFrom(BookAccount.owedToSuppliers, amount);
    case LedgerRole.debtRepayment:
      if (e.isInflow) {
        // Not seen in real messages, but kept balanced: money back from a
        // lender adds to what is owed.
        inFrom(BookAccount.borrowed, amount);
      } else {
        outTo(BookAccount.borrowed, amount - fulizaFee);
        if (fulizaFee > 0) outTo(BookAccount.fees, fulizaFee);
      }
    case LedgerRole.awaitingPayee:
      inFrom(BookAccount.awaitingPayee, amount);
    case LedgerRole.ownTransfer:
      final other = ownerPay && e.isOutflow
          ? BookAccount.ownerPay
          : BookAccount.ownTransfers;
      e.isInflow ? inFrom(other, amount) : outTo(other, amount);
    case LedgerRole.reversal:
      // A refund in takes spending back; money sent back takes income back.
      e.isInflow
          ? inFrom(spendingAccount(), amount)
          : outTo(incomeAccount(), amount);
  }
  if (e.feeMinor > 0) outTo(BookAccount.fees, e.feeMinor);

  return JournalEntry(
    source: JournalSource.transaction,
    sourceId: e.id,
    at: e.occurredAt,
    currency: e.currency,
    lines: lines,
  );
}

/// The opening entry for [account], and balance difference entries that keep
/// its book balance equal to [balanceAt] wherever a message reported one.
List<JournalEntry> _openingAndDifferences(
  AccountOpening account,
  List<LedgerEntry> all,
) {
  final money = BookAccount.money(account.id);
  int change(LedgerEntry e) => e.signedMinor - e.feeMinor;
  final mine = [
    for (final e in all)
      if (e.accountId == account.id && e.currency == account.currency) e,
  ];
  final own =
      [
        for (final e in mine)
          if (!e.occurredAt.isBefore(account.openingDate)) e,
      ]..sort((a, b) {
        final byTime = a.occurredAt.compareTo(b.occurredAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });

  JournalEntry adjust(
    JournalSource source,
    int sourceId,
    DateTime at,
    int minor,
    BookAccount against,
  ) => JournalEntry(
    source: source,
    sourceId: sourceId,
    at: at,
    currency: account.currency,
    lines: [JournalLine(money, minor), JournalLine(against, -minor)],
  );

  final out = <JournalEntry>[
    adjust(
      JournalSource.opening,
      account.id,
      account.openingDate,
      account.openingBalanceMinor,
      BookAccount.openingBalances,
    ),
  ];

  // [balanceAt] ignores entries before the opening date, and with a reported
  // balance it walks back from the first one, so the books start the account
  // from the same figure.
  final before = mine
      .where((e) => e.occurredAt.isBefore(account.openingDate))
      .fold(0, (s, e) => s + change(e));
  var running = account.openingBalanceMinor + before;
  var start = account.openingBalanceMinor;
  final first = own.indexWhere((e) => e.balanceAfterMinor != null);
  if (first >= 0) {
    final upToFirst = own.take(first + 1).fold(0, (s, e) => s + change(e));
    start = own[first].balanceAfterMinor! - upToFirst;
  }
  if (start != running) {
    out.add(
      adjust(
        JournalSource.balanceDifference,
        account.id,
        account.openingDate,
        start - running,
        BookAccount.balanceDifferences,
      ),
    );
    running = start;
  }
  for (final e in own) {
    running += change(e);
    final reported = e.balanceAfterMinor;
    if (reported != null && reported != running) {
      out.add(
        adjust(
          JournalSource.balanceDifference,
          e.id,
          e.occurredAt,
          reported - running,
          BookAccount.balanceDifferences,
        ),
      );
      running = reported;
    }
  }
  return out;
}
