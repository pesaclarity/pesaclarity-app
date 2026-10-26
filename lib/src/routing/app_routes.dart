/// Route paths. Deeper screens nest under the tab they open from.
abstract final class AppRoutes {
  static const launch = '/';

  static const onboarding = '/onboarding';
  static const onboardingAccounts = '/onboarding/accounts';

  static const home = '/home';
  static const profile = '/home/profile';
  static const myAccounts = '/home/profile/accounts';
  static const backup = '/home/profile/backup';
  static const privacy = '/home/profile/privacy';

  static const activity = '/activity';
  static const plan = '/plan';
  static const goals = '/goals';
  static const debts = '/goals/debts';
  static const insights = '/insights';
}
