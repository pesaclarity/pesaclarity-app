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

  static const onboardingGetStarted = 'onboarding-get-started';
  static const onboardingStartScan = 'onboarding-start-scan';

  static const homeProfile = 'home-profile';

  static const titleWelcome = 'title-welcome';
  static const titleMyAccounts = 'title-my-accounts';
  static const titleHome = 'title-home';
  static const titleActivity = 'title-activity';
  static const titlePlan = 'title-plan';
  static const titleGoals = 'title-goals';
  static const titleInsights = 'title-insights';
  static const titleProfile = 'title-profile';
  static const titleDebts = 'title-debts';
  static const titleBackup = 'title-backup';
  static const titlePrivacy = 'title-privacy';
}
