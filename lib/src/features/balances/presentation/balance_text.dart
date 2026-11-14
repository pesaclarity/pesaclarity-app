import '../../../data/database/app_database.dart';
import '../../../domain/ledger/balance_check.dart';
import '../../../domain/ledger/fuliza_debt.dart';
import 'add_missing_sheet.dart';

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
  static const inTheWallet = 'In the wallet';
  static const fulizaOwedLabel = 'Fuliza owed';
  static const worth = 'Worth';
  static const fulizaIsPaid = 'Fuliza is paid';
  static const fulizaMarkedPaid =
      'Fuliza marked as paid. It shows in Activity as a balance correction.';
  static const undo = 'Undo';
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
  static const justACorrection = "It's just a correction";
  static const addWhatsMissing = "Add what's missing";
  static String addMissingIntro(String account) =>
      'It goes in $account as a normal transaction, so your plan and '
      'insights count it.';
  static const moneyOut = 'Money out';
  static const moneyIn = 'Money in';
  static const whatWasIt = 'What was it?';
  static const paidTo = 'Paid to';
  static const receivedFrom = 'Received from';
  static const optional = 'Optional';
  static String placedBetween(String from, String to) =>
      'Placed between the two messages, $from and $to.';
  static const addIt = 'Add it';
  static const missingAdded = 'Added. The balances add up again.';
  static const missingFees = 'Fees and charges';
  static String missingKind(MissingKind kind) => switch (kind) {
    MissingKind.sentToSomeone => 'Sent to someone',
    MissingKind.airtime => 'Airtime or bundles',
    MissingKind.fulizaRepayment => 'Fuliza repayment',
    MissingKind.fees => 'Fees or charges',
    MissingKind.loanRepayment => 'Loan repayment',
    MissingKind.otherOut => 'Something else',
    MissingKind.receivedFromSomeone => 'Received from someone',
    MissingKind.refund => 'A refund or reversal',
    MissingKind.otherIn => 'Something else',
  };

  // The gap sheet.
  static const likelyTheMissingOne = 'LIKELY THE MISSING ONE';
  static const otherLeads = 'COULD ALSO BE';
  static const waitingToCheck = 'WAITING IN MESSAGES TO CHECK';
  static String everythingOn(String account) => 'EVERYTHING ON $account';
  static const fulizaWorkedOut = 'FULIZA, FROM THE BALANCES';
  static const checkThisMessage = 'Check this message';
  static const moveItHere = 'Move it here';
  static const itWentToFuliza = 'It went to Fuliza';
  static const removeTheCopy = 'Remove the copy';
  static String unreadExact(String amount, String direction, String when) =>
      'A message from $when is still waiting to be checked. It reads as '
      '$amount $direction, exactly the gap.';
  static String unreadOther(String amount, String direction, String when) =>
      'A message from $when is still waiting to be checked: $amount '
      '$direction.';
  static const unreadNoAmount = 'No amount found yet';
  static String otherAccount(String what, String amount, String account) =>
      '"$what" $amount is under $account. Its amount is exactly the gap.';
  static String wentToFuliza(String amount, String from) =>
      'M-Pesa repays Fuliza from money coming in before the wallet gets it. '
      'If Fuliza was owed, $amount of the money from $from went to it.';
  static String copyOf(String what, String amount) =>
      '$what $amount is in twice.';
  static const outWord = 'out';
  static const inWord = 'in';
  static const outsideTheGap = 'Same day, outside the gap';
  static String fulizaAutoLine(FulizaAuto auto, String amount, String fee) =>
      switch (auto.kind) {
        FulizaAutoKind.repaid =>
          'Fuliza repaid automatically: $amount kept from this money'
              '${fee.isEmpty ? '' : ', $fee of it daily charges'}',
        FulizaAutoKind.drawn =>
          'Fuliza covered $amount of this, plus a $fee access fee',
        FulizaAutoKind.cleared =>
          'Fuliza cleared: M-Pesa shows money in the wallet, so the $amount '
              'owed was repaid',
      };
  static const fulizaAutoNote =
      'A debt repayment, not spending. Worked out from the balance M-Pesa '
      'reported; no Fuliza message was read for it.';

  // Where it went.
  static String whereItWent(
    String period,
    String fees,
    String fuliza,
    String notExplained,
  ) => [
    '$period: fees $fees',
    'Fuliza charges $fuliza',
    'not explained $notExplained',
  ].join(' · ');
  static const thisMonth = 'This month';
  static const whereItWentTitle = 'Where it went';
  static const seeLeakage = 'See leakage in Insights';
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
