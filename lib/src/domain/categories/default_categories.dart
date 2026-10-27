import '../enums.dart';

/// A category the app ships with.
class CategorySeed {
  const CategorySeed(
    this.key,
    this.name,
    this.type, {
    this.isDailySpending = false,
  });

  /// Stable id shared with the on-device categoriser's labels.
  final String key;
  final String name;
  final CategoryType type;
  final bool isDailySpending;
}

/// The categoriser's fallback label. It maps to no category: the app shows
/// such transactions as Uncategorised and still counts them in totals.
const uncategorisedKey = 'uncategorised';

/// Shown wherever a transaction has no category.
const uncategorisedName = 'Uncategorised';

/// The default Kenyan category set, seeded on first run.
///
/// Keys mirror `src/akili/resources/categories.yaml`
/// (version 2) in pesaclarity/pesaclarity-ml so the categoriser's outputs map
/// one to one.
/// Change both together.
const defaultCategories = <CategorySeed>[
  CategorySeed('salary', 'Salary', CategoryType.income),
  CategorySeed(
    'business_income',
    'Business and freelance income',
    CategoryType.income,
  ),
  CategorySeed(
    'money_received',
    'Money received from people',
    CategoryType.income,
  ),
  CategorySeed(
    'groceries',
    'Groceries and household',
    CategoryType.expense,
    isDailySpending: true,
  ),
  CategorySeed(
    'eating_out',
    'Eating out',
    CategoryType.expense,
    isDailySpending: true,
  ),
  CategorySeed('snacks', 'Snacks', CategoryType.expense, isDailySpending: true),
  CategorySeed(
    'transport',
    'Transport',
    CategoryType.expense,
    isDailySpending: true,
  ),
  CategorySeed('fuel', 'Fuel', CategoryType.expense),
  CategorySeed(
    'airtime_data',
    'Airtime and data',
    CategoryType.expense,
    isDailySpending: true,
  ),
  CategorySeed('rent', 'Rent and housing', CategoryType.expense),
  CategorySeed(
    'utilities',
    'Electricity, water and internet',
    CategoryType.expense,
  ),
  CategorySeed(
    'school_fees',
    'School fees and education',
    CategoryType.expense,
  ),
  CategorySeed('health', 'Health and insurance', CategoryType.expense),
  CategorySeed('family_support', 'Family support', CategoryType.expense),
  CategorySeed(
    'friends_social',
    'Friends and social',
    CategoryType.expense,
    isDailySpending: true,
  ),
  CategorySeed(
    'lifestyle',
    'Lifestyle and entertainment',
    CategoryType.expense,
    isDailySpending: true,
  ),
  CategorySeed(
    'betting',
    'Betting and gaming',
    CategoryType.expense,
    isDailySpending: true,
  ),
  CategorySeed('shopping', 'Shopping and clothing', CategoryType.expense),
  CategorySeed('giving', 'Church, giving and harambee', CategoryType.expense),
  CategorySeed('fees_charges', 'Fees and charges', CategoryType.expense),
  CategorySeed('loan_repayment', 'Loan repayment', CategoryType.debt),
  CategorySeed('fuliza_repayment', 'Fuliza repayment', CategoryType.debt),
  CategorySeed(
    'savings',
    'Savings, SACCO and money market',
    CategoryType.savings,
  ),
  CategorySeed('tax', 'Tax', CategoryType.tax),
  CategorySeed('own_transfer', 'Own transfer', CategoryType.transfer),
];

/// An existing category as seeding sees it.
typedef ExistingCategory = ({String? key, String name});

/// The seeds not yet present in [existing], by key or by name (ignoring
/// case), so seeding twice adds nothing and never clashes with a category
/// the user made.
List<CategorySeed> missingSeeds(Iterable<ExistingCategory> existing) {
  final keys = <String>{};
  final names = <String>{};
  for (final c in existing) {
    if (c.key != null) keys.add(c.key!);
    names.add(categoryNameKey(c.name));
  }
  return [
    for (final seed in defaultCategories)
      if (!keys.contains(seed.key) &&
          !names.contains(categoryNameKey(seed.name)))
        seed,
  ];
}

/// A category name tidied for storing: trimmed with single spaces. Null when
/// empty or longer than 60 characters.
String? cleanCategoryName(String raw) {
  final name = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (name.isEmpty || name.length > 60) return null;
  return name;
}

/// Compares category names regardless of case and spacing.
String categoryNameKey(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
