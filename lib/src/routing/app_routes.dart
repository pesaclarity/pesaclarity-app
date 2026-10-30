import '../domain/ledger/activity_feed.dart';

/// Route paths. Deeper screens nest under the tab they open from.
abstract final class AppRoutes {
  static const launch = '/';

  static const onboarding = '/onboarding';
  static const onboardingCurrency = '/onboarding/currency';
  static const onboardingAccounts = '/onboarding/accounts';
  static const onboardingScan = '/onboarding/accounts/scan';
  static const onboardingFirstInsight = '/onboarding/accounts/scan/insight';

  static const home = '/home';

  /// Statement import, opened from the Home + button and from Profile.
  static const importStatement = '/home/import';

  /// Messages no parser rule read, and one of them by review item id.
  static const review = '/home/review';
  static String reviewMessage(int id) => '/home/review/$id';
  static const profile = '/home/profile';
  static const myAccounts = '/home/profile/accounts';
  static const backup = '/home/profile/backup';
  static const backupSetup = '/home/profile/backup/setup';
  static const privacy = '/home/profile/privacy';
  static const signIn = '/home/profile/sign-in';
  static const devices = '/home/profile/devices';
  static const privacyPolicy = '/home/profile/privacy/policy';
  static const payees = '/home/profile/payees';
  static const baseCurrency = '/home/profile/currency';
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
}
