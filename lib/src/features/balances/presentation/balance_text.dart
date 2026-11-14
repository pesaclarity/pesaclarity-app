import '../../../data/database/app_database.dart';
import '../../../domain/ledger/balance_check.dart';

/// The words of Balances, Set the balance, the balance check, Add an
/// account and own transfers, in one place.
abstract final class BalanceText {
  static const balancesTitle = 'Balances';
  static const balancesIntro =
      'What each account holds now, from its latest message.';
  static const allAccounts = 'All accounts';
  static const dayToDay = 'Day to day';
  static const savings = 'Savings';
  static const checkAll = 'Check all balances';
  static const addAccount = 'Add an account';
  static const matches = 'Matches';
  static const countAgain = 'Count again';
  static const notReported = 'Not reported';
  static String offBy(String amount) => 'Off by $amount';
  static String said(String amount, String when) => 'Said $amount · $when';
  static String counted(String when) => 'Counted $when';
  static String fulizaOwed(String amount) => '$amount Fuliza owed';
  static String onHandRule(String accounts, String fund, String total) =>
      'On hand on Home is day-to-day money less your rainy day fund: '
      '$accounts − $fund = $total.';
  static const onHandRuleNoFund =
      'On hand on Home is your day-to-day money. Savings are not counted.';
  static String summary(int matching, int needALook) => [
    '$matching ${matching == 1 ? 'matches its' : 'match their'} messages',
    if (needALook > 0) '$needALook ${needALook == 1 ? 'needs' : 'need'} a look',
  ].join(' · ');
  static String profileRow(int accounts, int needALook) => [
    '$accounts ${accounts == 1 ? 'account' : 'accounts'}',
    if (needALook > 0) '$needALook ${needALook == 1 ? 'needs' : 'need'} a look',
  ].join(' · ');

  // Set the balance.
  static const setBalance = 'Set the balance';
  static const setBalanceIntro =
      'Type what the account really holds now. The difference is recorded '
      'as a balance correction, shown in Activity, and can be undone.';
  static const appShows = 'The app shows';
  static String accountSays(String name) => '$name says';
  static const correction = 'Correction';
  static const correctionNote =
      'A correction is not income or spending, so it never changes your '
      'plan, insights or tax.';
  static const alreadyMatches = 'That is what the app shows already.';
  static const hasMoney = 'Has money';
  static const owesFuliza = 'Owes Fuliza';
  static const fulizaHelp =
      'Owe Fuliza? Choose Owes Fuliza and type what you owe. M-Pesa then '
      'shows below zero, and On hand counts it.';
  static const saveCorrection = 'Set the balance';
  static const undoCorrection = 'Undo the last correction';
  static const correctionSaved = 'Balance set.';
  static const correctionUndone = 'Correction undone.';

  // Balance check.
  static const checkTitle = 'Balance check';
  static String thingsToFix(int n) => n == 0
      ? 'Everything adds up'
      : n == 1
      ? '1 thing to fix'
      : '$n things to fix';
  static const checkIntro =
      'We went through every message with a balance and added up what '
      "happened between them. Where they don't agree, here is the likely "
      'reason.';
  static const alreadyRight = 'Already right';
  static const everyMessageAgrees = 'Every message agrees';
  static String fixAll(int n) => n == 1 ? 'Fix it' : 'Fix all $n';
  static String gapHeader(String account, String amount, bool more) =>
      '$account · $amount ${more ? 'more' : 'less'} than the app';
  static const addCorrectionInstead = 'Add a correction instead';
  static const fixed = 'Fixed.';

  static String causeTitle(GapCause cause) => switch (cause) {
    GapCause.countedTwice => 'Counted twice',
    GapCause.wrongAccount => 'Might be in the wrong account',
    GapCause.wrongDirection => 'Might be the wrong way round',
    GapCause.unpairedTransfer => 'A transfer with a side missing',
    GapCause.fuliza => 'Fuliza',
    GapCause.missed => 'Probably a message we missed',
    GapCause.doubtfulBalance => "A balance that doesn't follow",
  };

  static String fixLabel(GapFix fix, {required String accountName}) =>
      switch (fix) {
        RemoveCopy() => 'Remove the copy',
        MoveHere() => 'Move it to $accountName',
      };

  static const fromMessage = 'from message';
  static const fromStatement = 'from statement';
  static const typedIn = 'typed in';
  static String saidAt(String account, String when) => '$account said, $when';
  static const inAndOut = 'In and out since, in the app';
  static const soItShouldBe = 'So it should be';
  static const notExplained = 'Not explained';
  static const inThisGap = 'In this gap';

  // Add an account.
  static const addAccountIntro =
      'For cash, or an account whose messages the app does not read.';
  static const accountName = 'Name';
  static const accountType = 'Type';
  static const currency = 'Currency';
  static const currentBalance = 'Holds now';
  static const addAccountSave = 'Add account';
  static String accountAdded(String name) => '$name added.';
  static String typeLabel(AccountType type) => switch (type) {
    AccountType.cash => 'Cash',
    AccountType.bank => 'Bank',
    AccountType.mpesa => 'Mobile money',
    AccountType.sacco => 'SACCO',
    AccountType.moneyMarket => 'Money market',
    AccountType.other => 'Other',
  };

  // On hand.
  static String onHandTitle(String amount) => 'On hand: $amount';
  static const startOfToday = 'At the start of today';
  static const lessRainyDay = 'Less rainy day fund';
  static const onHand = 'On hand';
  static const savingsNotCounted = 'Savings accounts are not counted.';
  static const seeAllBalances = 'See all balances';
  static String fulizaTakenOff(String amount) => 'Includes $amount Fuliza owed';

  // Home and Messages to check.
  static String doesNotAddUp(String account) => "$account doesn't add up";
  static String unaccounted(String amount, String since) =>
      '$amount unaccounted for since $since';
  static String unaccountedBetween(String amount, String from, String to) =>
      '$amount is unaccounted for between $from and $to. Probably a payment '
      'counted twice or a message we missed.';
  static const check = 'Check';
  static const seeTheGap = 'See the gap';
  static const belowZeroFuliza = "You're below zero once Fuliza is counted";
  static const belowZero = "You're below zero across your accounts";
  static const billsTakeIt = 'Bills due take what is on hand';

  // Own transfers.
  static const myAccounts = 'My accounts';
  static const from = 'From';
  static const to = 'To';
  static const amount = 'Amount';
  static const fee = 'Fee';
  static const date = 'Date';
  static const saveTransfer = 'Save as a transfer';
  static String matchedWith(String account) => 'Matched with $account';
  static String matchedDetail(String what, String time) =>
      '"$what" at $time. Both become one transfer, not spending or income.';
  static String waitingTitle(String account) =>
      "$account's side isn't here yet";
  static String waitingDetail(String account, String from) =>
      "We'll match it when that message comes, up to 3 days. Until then "
      '$from shows it as a transfer, not spending.';
  static const ownMoney = 'Was this your own money?';
  static const match = 'Match';
  static const fromAnother = 'From another of my accounts';
  static const toAnother = 'To another of my accounts';
  static const itsSideLater = 'Choose it; its side can come later';
  static String plusFee(String amount, String fee) => '$amount plus a $fee fee';
  static const ownTransfer = 'Own transfer';
  static const notSpending = 'not spending';
  static String feeOf(String fee) => 'fee $fee';
  static const unmatch = 'Unmatch';
  static const unmatchNote =
      "Both go back to counting as they were, and won't be matched again.";
  static const unmatched = 'Unmatched.';
  static const matched = 'Matched as your own transfer.';
  static String waitingFor(String account) =>
      'Own transfer · waiting for $account';
  static const transferSaved = 'Saved as a transfer.';
  static const noOtherAccount =
      'Add your other account first: Balances › Add an account.';
}
