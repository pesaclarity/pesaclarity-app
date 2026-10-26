import '../domain/ledger/activity_feed.dart';

/// Route paths. Deeper screens nest under the tab they open from.
abstract final class AppRoutes {
  static const launch = '/';

  static const onboarding = '/onboarding';
  static const onboardingAccounts = '/onboarding/accounts';
  static const onboardingScan = '/onboarding/accounts/scan';
  static const onboardingFirstInsight = '/onboarding/accounts/scan/insight';

  static const home = '/home';

  /// Statement import, opened from the Home + button and from Profile.
  static const importStatement = '/home/import';
  static const profile = '/home/profile';
  static const myAccounts = '/home/profile/accounts';
  static const backup = '/home/profile/backup';
  static const privacy = '/home/profile/privacy';
  static const privacyPolicy = '/home/profile/privacy/policy';
  static const payees = '/home/profile/payees';

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
