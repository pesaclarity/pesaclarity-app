import '../../core/export/export_table.dart';
import '../../core/money/money.dart';
import '../categories/default_categories.dart';
import '../enums.dart';
import '../tags/tag_totals.dart';

/// One transaction with everything an export shows, names already looked up.
class ExportTransaction {
  ExportTransaction({
    required this.id,
    required this.occurredAt,
    required this.accountName,
    required this.amountMinor,
    required this.direction,
    required this.kind,
    required this.source,
    String? currency,
    this.feeMinor = 0,
    this.payeeName,
    this.counterpartyName,
    this.counterpartyValue,
    this.categoryName,
    this.leakType = LeakType.none,
    this.tags = const [],
    this.receiptNo,
    this.isOwnTransfer = false,
  }) : currency = currency ?? BaseCurrency.code;

  final int id;
  final DateTime occurredAt;
  final String accountName;

  /// Always positive; [direction] says which way it moved.
  final int amountMinor;
  final TransactionDirection direction;
  final TransactionKind kind;
  final TransactionSource source;
  final String currency;
  final int feeMinor;

  /// The named payee, when there is one.
  final String? payeeName;

  /// The other party as the message printed it, and its raw identifier.
  final String? counterpartyName;
  final String? counterpartyValue;

  /// The category override or the payee's default; null is Uncategorised.
  final String? categoryName;
  final LeakType leakType;

  /// Tag names, sorted.
  final List<String> tags;
  final String? receiptNo;
  final bool isOwnTransfer;

  /// The name to show for the other party.
  String get party =>
      payeeName ?? counterpartyName ?? counterpartyValue ?? kindLabel(kind);
}

/// The transactions sheet, oldest first as given.
ExportTable transactionsTable(
  Iterable<ExportTransaction> transactions, {
  String title = 'Transactions',
}) => ExportTable(
  title: title,
  columns: const [
    'Date',
    'Account',
    'Payee',
    'Category',
    'Tags',
    'Money in',
    'Money out',
    'Fee',
    'Currency',
    'Type',
    'Leak type',
    'Own transfer',
    'Receipt',
    'Source',
  ],
  rows: [
    for (final t in transactions)
      [
        t.occurredAt,
        t.accountName,
        t.party,
        t.categoryName ?? uncategorisedName,
        t.tags.map((tag) => '#$tag').join(' '),
        if (t.direction == TransactionDirection.inflow) ...[
          Money(t.amountMinor, currency: t.currency),
          null,
        ] else ...[
          null,
          Money(t.amountMinor, currency: t.currency),
        ],
        t.feeMinor == 0 ? null : Money(t.feeMinor, currency: t.currency),
        t.currency,
        kindLabel(t.kind),
        t.leakType == LeakType.none ? null : leakTypeLabel(t.leakType),
        t.isOwnTransfer ? 'Yes' : null,
        t.receiptNo,
        sourceLabel(t.source),
      ],
  ],
);

/// Spending per category, largest first, with Uncategorised included so the
/// sheet adds up to total spending.
ExportTable categorySpendingTable(
  Map<int?, int> spending,
  Map<int, String> categoryNames, {
  String? currency,
}) {
  currency ??= BaseCurrency.code;
  final sorted = spending.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final total = spending.values.fold(0, (sum, v) => sum + v);
  return ExportTable(
    title: 'Spending by category',
    columns: const ['Category', 'Spending'],
    rows: [
      for (final e in sorted)
        [
          e.key == null
              ? uncategorisedName
              : categoryNames[e.key] ?? uncategorisedName,
          Money(e.value, currency: currency),
        ],
      ['Total', Money(total, currency: currency)],
    ],
  );
}

/// One row per tag: how many transactions and what they add up to.
ExportTable tagTotalsTable(
  Map<int, TagSummary> totals,
  Map<int, String> tagNames, {
  String? currency,
}) {
  currency ??= BaseCurrency.code;
  final sorted = totals.values.toList()
    ..sort(
      (a, b) => (tagNames[a.tagId] ?? '').compareTo(tagNames[b.tagId] ?? ''),
    );
  return ExportTable(
    title: 'Tags',
    columns: const ['Tag', 'Transactions', 'Spending', 'Income', 'Fees'],
    rows: [
      for (final s in sorted)
        [
          '#${tagNames[s.tagId] ?? s.tagId}',
          s.entryCount,
          Money(s.totals.spendingMinor, currency: currency),
          Money(s.totals.incomeMinor, currency: currency),
          Money(s.totals.feesMinor, currency: currency),
        ],
    ],
  );
}

/// Each tag's spending split by category, Uncategorised included.
ExportTable tagCategoryTable(
  Map<int, TagSummary> totals,
  Map<int, String> tagNames,
  Map<int, String> categoryNames, {
  String? currency,
}) {
  currency ??= BaseCurrency.code;
  final rows = <List<Object?>>[];
  final tags = totals.values.toList()
    ..sort(
      (a, b) => (tagNames[a.tagId] ?? '').compareTo(tagNames[b.tagId] ?? ''),
    );
  for (final s in tags) {
    final byCategory = s.spendingByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in byCategory) {
      rows.add([
        '#${tagNames[s.tagId] ?? s.tagId}',
        e.key == null
            ? uncategorisedName
            : categoryNames[e.key] ?? uncategorisedName,
        Money(e.value, currency: currency),
      ]);
    }
  }
  return ExportTable(
    title: 'Tag spending by category',
    columns: const ['Tag', 'Category', 'Spending'],
    rows: rows,
  );
}

/// A named payee as the payees sheet shows it.
typedef ExportPayee = ({
  String name,
  List<String> identifiers,
  String? categoryName,
  LeakType leakType,
  int transactionCount,
});

ExportTable payeesTable(Iterable<ExportPayee> payees) => ExportTable(
  title: 'Payees',
  columns: const [
    'Payee',
    'Numbers and tills',
    'Category',
    'Leak type',
    'Transactions',
  ],
  rows: [
    for (final p in payees)
      [
        p.name,
        p.identifiers.join(', '),
        p.categoryName ?? uncategorisedName,
        leakTypeLabel(p.leakType),
        p.transactionCount,
      ],
  ],
);

/// A category as the categories sheet shows it.
typedef ExportCategory = ({
  String name,
  CategoryType type,
  bool isDailySpending,
  bool isOwn,
});

ExportTable categoriesTable(Iterable<ExportCategory> categories) => ExportTable(
  title: 'Categories',
  columns: const ['Category', 'Type', 'Day-to-day spending', 'Added by you'],
  rows: [
    for (final c in categories)
      [
        c.name,
        categoryTypeLabel(c.type),
        c.isDailySpending ? 'Yes' : 'No',
        c.isOwn ? 'Yes' : 'No',
      ],
  ],
);

/// Tag names with how many transactions carry each.
ExportTable tagsListTable(Iterable<({String name, int count})> tags) =>
    ExportTable(
      title: 'Tag list',
      columns: const ['Tag', 'Transactions'],
      rows: [
        for (final t in tags) ['#${t.name}', t.count],
      ],
    );

/// An account as the accounts sheet shows it.
typedef ExportAccount = ({
  String name,
  AccountType type,
  String currency,
  int openingBalanceMinor,
  DateTime openingDate,
});

ExportTable accountsTable(Iterable<ExportAccount> accounts) => ExportTable(
  title: 'Accounts',
  columns: const ['Account', 'Type', 'Currency', 'Opening balance', 'Since'],
  rows: [
    for (final a in accounts)
      [
        a.name,
        accountTypeLabel(a.type),
        a.currency,
        Money(a.openingBalanceMinor, currency: a.currency),
        a.openingDate,
      ],
  ],
);

String kindLabel(TransactionKind kind) => switch (kind) {
  TransactionKind.sent => 'Sent',
  TransactionKind.received => 'Received',
  TransactionKind.paybill => 'Paybill',
  TransactionKind.till => 'Buy Goods',
  TransactionKind.withdrawal => 'Withdrawal',
  TransactionKind.deposit => 'Deposit',
  TransactionKind.airtime => 'Airtime',
  TransactionKind.fulizaDraw => 'Fuliza',
  TransactionKind.fulizaRepayment => 'Fuliza repayment',
  TransactionKind.roundUp => 'Round-up',
  TransactionKind.charge => 'Charge',
  TransactionKind.reversal => 'Reversal',
  TransactionKind.bank => 'Bank',
};

String leakTypeLabel(LeakType type) => switch (type) {
  LeakType.none => 'Not a leak',
  LeakType.lifestyle => 'Lifestyle',
  LeakType.friends => 'Friends',
  LeakType.family => 'Family',
  LeakType.fees => 'Fees',
};

String sourceLabel(TransactionSource source) => switch (source) {
  TransactionSource.sms => 'SMS',
  TransactionSource.statement => 'Statement',
  TransactionSource.manual => 'Added by hand',
};

String categoryTypeLabel(CategoryType type) => switch (type) {
  CategoryType.income => 'Income',
  CategoryType.expense => 'Spending',
  CategoryType.debt => 'Debt',
  CategoryType.savings => 'Savings',
  CategoryType.tax => 'Tax',
  CategoryType.transfer => 'Transfer',
};

String accountTypeLabel(AccountType type) => switch (type) {
  AccountType.bank => 'Bank',
  AccountType.mpesa => 'M-Pesa',
  AccountType.sacco => 'SACCO',
  AccountType.moneyMarket => 'Money market',
  AccountType.cash => 'Cash',
};
