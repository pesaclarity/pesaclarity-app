/// Semantics identifiers for UI automation.
///
/// On Android these become the view's resource-id, which the Maestro flows in
/// `.maestro/` select with `id:`. Renaming one breaks those flows.
abstract final class SemanticIds {
  static const navHome = 'nav-home';
  static const navActivity = 'nav-activity';
  static const navPlan = 'nav-plan';
  static const navGoals = 'nav-goals';
  static const navInsights = 'nav-insights';
  static const navMoney = 'nav-money';
  static const navPeople = 'nav-people';
  static const navStock = 'nav-stock';

  static const onboardingGetStarted = 'onboarding-get-started';
  static const onboardingCurrencyContinue = 'onboarding-currency-continue';
  static const onboardingIncomeContinue = 'onboarding-income-continue';
  static const onboardingScanMessages = 'onboarding-scan-messages';
  static const smsScanNotNow = 'sms-scan-not-now';

  /// A row in the institution list, such as `institution-mpesa`.
  static String institution(String institutionId) =>
      'institution-${institutionId.replaceAll('_', '-')}';

  /// A row in the currency picker, such as `currency-KES`.
  static String currency(String code) => 'currency-$code';

  /// A row in the income sources list, such as `income-salary`.
  static String incomeSource(String name) => 'income-$name';

  static const homeProfile = 'home-profile';
  static const profileMyAccounts = 'profile-my-accounts';
  static const myAccountsChoose = 'my-accounts-choose';
  static const profileBackup = 'profile-backup';
  static const profilePrivacy = 'profile-privacy';
  static const goalsSeeDebts = 'goals-see-debts';

  static const titleWelcome = 'title-welcome';
  static const titleCurrency = 'title-currency';
  static const titleIncomeSources = 'title-income-sources';
  static const titleMyAccounts = 'title-my-accounts';
  static const titleSmsScan = 'title-sms-scan';
  static const titleConnectMessages = 'title-connect-messages';
  static const titleHome = 'title-home';
  static const titleActivity = 'title-activity';
  static const titlePlan = 'title-plan';
  static const titleGoals = 'title-goals';
  static const titleInsights = 'title-insights';
  static const titleMoney = 'title-money';
  static const titleProfile = 'title-profile';
  static const titleProfileMyAccounts = 'title-profile-my-accounts';
  static const titleChooseAccounts = 'title-choose-accounts';
  static const titleDebts = 'title-debts';
  static const titleBackup = 'title-backup';
  static const titlePrivacy = 'title-privacy';
}
