import '../categories/default_categories.dart';
import '../enums.dart';
import 'space.dart';

/// Categories every kind of space keeps: they are filled in from messages
/// (fees, Fuliza, airtime) or keep the numbers honest (own transfers).
const _common = {
  'fees_charges',
  'fuliza_repayment',
  'loan_repayment',
  'tax',
  'own_transfer',
  'airtime_data',
  'transport',
};

/// Keys from the personal set each kind keeps, besides [_common].
const _kept = <SpaceKind, Set<String>>{
  SpaceKind.business: {'utilities', 'money_received', 'savings'},
  SpaceKind.household: {
    'groceries',
    'rent',
    'utilities',
    'school_fees',
    'health',
    'shopping',
    'giving',
    'savings',
    'money_received',
  },
  SpaceKind.savingsGroup: {'savings'},
  SpaceKind.rentalProperty: {'utilities', 'money_received'},
  SpaceKind.farm: {'fuel', 'money_received', 'savings'},
};

/// Category key sales are filed under in a business.
const salesCategoryKey = 'sales';

/// The Sales category's name as seeded.
const salesCategoryName = 'Sales';

/// A business's sales.
const salesSeed = CategorySeed(
  salesCategoryKey,
  salesCategoryName,
  CategoryType.income,
);

/// Stock bought to sell, the default for Bought.
const stockSeed = CategorySeed(
  'stock',
  'Stock and supplies',
  CategoryType.expense,
);

/// Personal's income from the owner's own business, as Pay yourself files
/// it: as pay, or as other business income.
const payFromBusinessSeed = CategorySeed(
  'pay_from_business',
  'Salary from my business',
  CategoryType.income,
);

/// Customers paying what they owe for sales on credit: not a new sale.
const customerPaymentsKey = 'customer_payments';

const customerPaymentsSeed = CategorySeed(
  customerPaymentsKey,
  'Payments from customers',
  CategoryType.income,
);

/// Paying suppliers what the business owes them: not a new cost.
const supplierPaymentsKey = 'supplier_payments';

const supplierPaymentsSeed = CategorySeed(
  supplierPaymentsKey,
  'Payments to suppliers',
  CategoryType.debt,
);

/// Paying yourself from a business, rental or farm: money moved to
/// Personal, not a cost.
const ownerPayKey = 'owner_pay';

const ownerPaySeed = CategorySeed(
  ownerPayKey,
  'Paid yourself',
  CategoryType.transfer,
);

/// Categories added for each kind.
const _added = <SpaceKind, List<CategorySeed>>{
  SpaceKind.business: [
    salesSeed,
    CategorySeed('other_business_income', 'Other income', CategoryType.income),
    stockSeed,
    customerPaymentsSeed,
    supplierPaymentsSeed,
    CategorySeed('wages', 'Wages', CategoryType.expense),
    CategorySeed('premises', 'Rent and premises', CategoryType.expense),
    CategorySeed('equipment', 'Tools and equipment', CategoryType.expense),
    ownerPaySeed,
  ],
  SpaceKind.household: [
    CategorySeed(
      'member_contribution',
      'Money from household members',
      CategoryType.income,
    ),
  ],
  SpaceKind.savingsGroup: [
    CategorySeed('contributions', 'Contributions', CategoryType.income),
    CategorySeed(
      'member_loan_repayments',
      'Loan repayments from members',
      CategoryType.income,
    ),
    CategorySeed('fines_interest', 'Fines and interest', CategoryType.income),
    CategorySeed('payouts', 'Payouts to members', CategoryType.expense),
    CategorySeed('member_loans', 'Loans to members', CategoryType.expense),
    CategorySeed(
      'group_costs',
      'Meetings and group costs',
      CategoryType.expense,
    ),
  ],
  SpaceKind.rentalProperty: [
    CategorySeed('rent_collected', 'Rent collected', CategoryType.income),
    CategorySeed('deposits', 'Deposits', CategoryType.income),
    CategorySeed('repairs', 'Repairs and maintenance', CategoryType.expense),
    CategorySeed('caretaker', 'Caretaker and security', CategoryType.expense),
    CategorySeed(
      'rates',
      'Land rates and service charge',
      CategoryType.expense,
    ),
    ownerPaySeed,
  ],
  SpaceKind.farm: [
    CategorySeed('harvest_sales', 'Harvest sales', CategoryType.income),
    CategorySeed('seed', 'Seed and seedlings', CategoryType.expense),
    CategorySeed('fertiliser', 'Fertiliser and sprays', CategoryType.expense),
    CategorySeed('farm_labour', 'Labour', CategoryType.expense),
    CategorySeed('feed_vet', 'Animal feed and vet', CategoryType.expense),
    CategorySeed('farm_equipment', 'Tools and equipment', CategoryType.expense),
    ownerPaySeed,
  ],
};

/// The categories a space of [kind] starts with. Personal and Something
/// else use the full personal set.
List<CategorySeed> categorySeedsFor(SpaceKind kind) {
  final kept = _kept[kind];
  if (kept == null) return defaultCategories;
  return [
    for (final seed in defaultCategories)
      if (_common.contains(seed.key) || kept.contains(seed.key)) seed,
    ...?_added[kind],
  ];
}
