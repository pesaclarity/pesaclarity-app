import '../domain/ledger/activity_feed.dart';

/// Route paths. Deeper screens nest under the tab they open from.
abstract final class AppRoutes {
  static const launch = '/';

  static const onboarding = '/onboarding';
  static const onboardingCurrency = '/onboarding/currency';
  static const onboardingIncome = '/onboarding/income';
  static const onboardingAccounts = '/onboarding/accounts';
  static const onboardingScan = '/onboarding/accounts/scan';
  static const onboardingFirstInsight = '/onboarding/accounts/scan/insight';

  static const home = '/home';

  /// "Which space?" after unlocking, when the app is set to ask.
  static const chooseSpace = '/choose-space';

  /// Statement import, opened from the Home + button and from Profile.
  static const importStatement = '/home/import';

  /// Messages no parser rule read, and one of them by review item id.
  static const review = '/home/review';

  /// Adding a space, such as a business.
  static const addSpace = '/home/spaces/add';

  /// A business: products, services or both.
  static const whatYouSell = '/home/spaces/sells';

  /// A business: opening balances.
  static const startRecords = '/home/spaces/start';

  /// A business: which accounts are business, personal or both.
  static const businessOrPersonal = '/home/spaces/routing';

  /// Business and gigs: this week against a usual one, and the fund.
  static const weekByWeek = '/home/week';
  static String reviewMessage(int id) => '/home/review/$id';
  static const profile = '/home/profile';
  static const myAccounts = '/home/profile/accounts';
  static const backup = '/home/profile/backup';
  static const backupSetup = '/home/profile/backup/setup';
  static const privacy = '/home/profile/privacy';
  static const signIn = '/home/profile/sign-in';
  static const devices = '/home/profile/devices';
  static const privacyPolicy = '/home/profile/privacy/policy';
  static const terms = '/home/profile/privacy/terms';
  static const payees = '/home/profile/payees';
  static const baseCurrency = '/home/profile/currency';
  static const incomeSources = '/home/profile/income';
  static const subscriptions = '/home/profile/subscriptions';

  /// iPhone: the Shortcuts automation that passes messages.
  static const connectMessages = '/home/profile/connect';

  static const activity = '/activity';

  /// Activity opened with [filter] applied.
  static String activityWith(ActivityFilter filter) {
    final query = filter.toQuery();
    if (query.isEmpty) return activity;
    return Uri(path: activity, queryParameters: query).toString();
  }

  static const plan = '/plan';
  static const payday = '/plan/payday';
  static const goals = '/goals';
  static const debts = '/goals/debts';
  static const lending = '/goals/lending';
  static const insights = '/insights';

  /// A business's profit and loss, cash book, customers and suppliers.
  static const fullRecords = '/insights/records';

  /// A business report to share as a PDF or CSV.
  static const makeReport = '/insights/report';

  /// What the business may owe in tax, as an estimate.
  static const tax = '/insights/tax';

  /// A business's cash book.
  static const money = '/money';

  /// A business's customers and suppliers.
  static const people = '/people';

  /// What one customer owes and has paid.
  static String customerStatement(String name) =>
      Uri(path: '/people/customer', queryParameters: {'name': name}).toString();

  /// The business's reminder messages, app, till and daily nudge.
  static const reminderMessages = '/people/messages';

  /// What the business owes one supplier, and has paid.
  static String supplierStatement(int debtId) => '/people/supplier/$debtId';

  /// What a business sells, and its stock.
  static const stock = '/stock';

  /// One item: stock, price, cost and history.
  static String item(int id) => '/stock/item/$id';

  /// Count stock against the records.
  static const countStock = '/stock/count';

  /// A business: count the drawer and match the day's payments.
  static const closeDay = '/close-day';

  /// A business: sell, then pay. Full screen, over the tabs.
  static const sell = '/sell';

  /// A services business: work done, billed to pay later.
  static const billed = '/sell?for=billed';
}
