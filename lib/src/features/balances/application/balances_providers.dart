import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ujumbe/ujumbe.dart' show engineVersion;

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/database/space_databases.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/balance_records_repository.dart';
import '../../../data/repositories/balances_repair.dart';
import '../../../data/repositories/journal_repository.dart';
import '../../../data/repositories/ledger_history.dart';
import '../../../data/repositories/own_moves.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/accounts/mpesa_lines.dart';
import '../../../domain/ledger/balance_check.dart';
import '../../../domain/ledger/balances.dart';
import '../../../domain/ledger/cross_currency_transfers.dart';
import '../../../domain/ledger/fuliza_debt.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/ledger/on_hand.dart';
import '../../../domain/ledger/own_transfers.dart';
import '../../../domain/time/calendar.dart';
import '../../accounts/application/mpesa_lines_providers.dart';
import '../../accounts/domain/institution.dart';
import '../../currency/application/currency_controller.dart';
import '../../goals/application/goals_aside_providers.dart';
import '../../income/application/income_providers.dart';

/// How far back the balance check looks for gaps.
const balanceCheckDays = 90;

/// One account on the Balances screen.
class AccountBalance {
  const AccountBalance({
    required this.account,
    required this.opening,
    required this.heldMinor,
    required this.walletMinor,
    required this.fulizaOwedMinor,
    required this.check,
    this.lastCorrection,
  });

  final Account account;
  final AccountOpening opening;

  /// What it is really worth now: the wallet less Fuliza owed.
  final int heldMinor;
  final int walletMinor;
  final int fulizaOwedMinor;

  /// Its balance check over the last [balanceCheckDays].
  final AccountCheck check;

  /// The newest balance set by hand, which can be undone.
  final LedgerEntry? lastCorrection;

  bool get isSavings => opening.isSavings;
}

/// Every account in the space with its balance and check.
class BalancesOverview {
  const BalancesOverview({
    required this.accounts,
    required this.entries,
    required this.now,
    this.records = const [],
  });

  /// What payments switched to other spaces left on these accounts
  /// (decision 0027): balances walk them with [entries], so each reported
  /// balance still adds up, but no screen lists them.
  final List<LedgerEntry> records;

  /// Day-to-day accounts first, then savings, each by name.
  final List<AccountBalance> accounts;

  /// The entries the balances were worked out from, for the gap screens.
  final List<LedgerEntry> entries;
  final DateTime now;

  List<AccountBalance> get dayToDay => [
    for (final a in accounts)
      if (!a.isSavings) a,
  ];

  List<AccountBalance> get savings => [
    for (final a in accounts)
      if (a.isSavings) a,
  ];

  /// Accounts with a gap to look at.
  List<AccountBalance> get needALook => [
    for (final a in accounts)
      if (a.check.needsALook) a,
  ];

  /// Accounts whose latest reported balance does not add up.
  List<AccountBalance> get off => [
    for (final a in accounts)
      if (a.check.status == BalanceStatus.off) a,
  ];

  int get matchingCount =>
      accounts.where((a) => a.check.status == BalanceStatus.matches).length;

  /// Accounts no message reports a balance for, such as cash and savings,
  /// so there is nothing to check them against.
  int get noMessagesCount => accounts
      .where(
        (a) =>
            a.check.status == BalanceStatus.countAgain ||
            a.check.status == BalanceStatus.notReported,
      )
      .length;

  /// What the day-to-day accounts are worth, in the base currency: savings
  /// are left out, as On hand leaves them out.
  int totalMinor(String base) => accounts
      .where((a) => a.opening.currency == base && !a.isSavings)
      .fold(0, (sum, a) => sum + a.heldMinor);

  AccountBalance? byId(int id) =>
      accounts.where((a) => a.account.id == id).firstOrNull;
}

/// Every account with its balance, Fuliza owed and balance check.
final balancesOverviewProvider = FutureProvider<BalancesOverview>((ref) async {
  ref.watch(ledgerChangesProvider);
  final now = ref.watch(clockProvider)();
  final repository = ref.watch(accountsRepositoryProvider);
  final rows = await repository.all();
  final openings = {for (final o in await repository.openings()) o.id: o};
  var from = now;
  for (final o in openings.values) {
    if (o.openingDate.isBefore(from)) from = o.openingDate;
  }
  final entries = await readLedgerHistory(
    ref,
    from: from,
    to: now.add(const Duration(seconds: 1)),
  );
  final records = await BalanceRecordsReader(ref.watch(appDatabaseProvider))
      .ledgerEntries();
  final walked = records.isEmpty ? entries : [...entries, ...records];
  final checkFrom = now.subtract(const Duration(days: balanceCheckDays));
  final journal = await readJournal(ref);
  final at = now.add(const Duration(seconds: 1));

  final list = <AccountBalance>[];
  for (final row in rows) {
    final opening = openings[row.id];
    if (opening == null) continue;
    final check = checkAccount(opening, walked);
    final gaps = [
      for (final g in check.gaps)
        if (g.to.occurredAt.isAfter(checkFrom)) g,
    ];
    // Any gap still open in the window is worth a look, not only the
    // newest balance's: a payment counted twice skews spending too.
    final recent = AccountCheck(
      account: check.account,
      status: gaps.isNotEmpty
          ? BalanceStatus.off
          : check.status == BalanceStatus.off
          ? BalanceStatus.matches
          : check.status,
      gaps: gaps,
      lastReported: check.lastReported,
      lastCounted: check.lastCounted,
    );
    final wallet = journal.walletAt(opening, at: at);
    final owed = journal.fulizaOwedAt(opening, at: at);
    list.add(
      AccountBalance(
        account: row,
        opening: opening,
        heldMinor: wallet - owed,
        walletMinor: wallet,
        fulizaOwedMinor: owed,
        check: recent,
        lastCorrection: entries
            .where(
              (e) =>
                  e.accountId == row.id &&
                  e.isCorrection &&
                  e.balanceAfterMinor != null,
            )
            .lastOrNull,
      ),
    );
  }
  // The main M-Pesa line's balance shows first among the lines, then the
  // second's.
  final lines = ref.watch(mpesaLinesProvider).value ?? MpesaLines.empty;
  list.sort((a, b) {
    final bySavings = (a.isSavings ? 1 : 0).compareTo(b.isSavings ? 1 : 0);
    if (bySavings != 0) return bySavings;
    final byName = a.account.name.toLowerCase().compareTo(
      b.account.name.toLowerCase(),
    );
    return byName != 0
        ? byName
        : lines
              .rankOf(a.account.reference)
              .compareTo(lines.rankOf(b.account.reference));
  });
  return BalancesOverview(
    accounts: list,
    entries: entries,
    now: now,
    records: records,
  );
});

/// What M-Pesa's balances show Fuliza did with no message of its own, by
/// the entry whose balance shows it, for Activity.
/// Empty while the space does not show Fuliza.
final fulizaAutoProvider = FutureProvider<Map<int, FulizaAuto>>((ref) async {
  final overview = await ref.watch(balancesOverviewProvider.future);
  if (!(await readJournal(ref)).fulizaShown) return const {};
  return {
    for (final a in overview.accounts)
      if (a.opening.canOweFuliza)
        for (final auto in WalletWalk.of(a.opening, [
          ...overview.entries,
          ...overview.records,
        ]).fuliza.auto)
          auto.entry.id: auto,
  };
});

/// Day-to-day money at the start of today, for Home's On hand and its
/// breakdown. Null without day-to-day accounts.
final onHandProvider = FutureProvider<OnHand?>((ref) async {
  ref.watch(ledgerChangesProvider);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final accounts = [
    for (final a in await ref.watch(accountsRepositoryProvider).openings())
      if (!a.isSavings) a,
  ];
  if (accounts.isEmpty) return null;
  var from = today.startInstant;
  for (final a in accounts) {
    if (a.openingDate.isBefore(from)) from = a.openingDate;
  }
  final entries = await readLedgerHistory(
    ref,
    from: from,
    to: today.addDays(1).startInstant,
  );
  final fund = await ref.watch(rainyDayFundProvider.future);
  final goals = await ref.watch(goalsAsideProvider.future);
  return OnHand.at(
    accounts,
    entries,
    balances: await readJournal(ref),
    today: today,
    rainyDayMinor: fund.balanceMinor,
    goalsKeptMinor: goals.totalMinor,
  );
});

/// Pairs own transfers over the whole history once after each update that
/// changed how they pair: version 1 started pairing them, version 2 pairs
/// them across currencies. Safe to run again: only unpaired entries pair.
///
/// First, once per space and again whenever the message readers change,
/// puts right what earlier versions counted twice, within the space and
/// with the other spaces, and matches own transfers over the whole history
/// (see [repairBalancesOnce]; decision 0030).
final pairHistoryOnceProvider = FutureProvider<void>((ref) async {
  const key = 'ledger.ownTransfersPaired';
  const version = 2;
  final spaces = ref.watch(spaceDatabasesProvider);
  await repairBalancesOnce(
    ref.watch(appDatabaseProvider),
    readers: ref.watch(readersVersionProvider),
    spaces: (
      here: ref.watch(activeSpaceIdProvider),
      ids: [for (final space in await spaces.listed()) space.id],
      open: spaces.open,
    ),
  );
  final settings = ref.watch(appSettingsRepositoryProvider);
  final done = (await settings.readJson(key))?['version'];
  if (done is int && done >= version) return;
  await ref.watch(transactionsRepositoryProvider).pairOwnTransfers();
  await settings.writeJson(key, {'version': version});
});

/// The bundled readers' versions (see [readersVersion]): when they change,
/// own transfers are matched again over the whole history.
final readersVersionProvider = Provider<String>(
  (ref) => readersVersion(engineVersion, {
    for (final i in ref.watch(institutionCatalogueProvider))
      i.pack.id: i.pack.version,
  }),
);

/// Own transfers paired by amount and time alone that the person has not
/// answered for, by each side's id: their line asks "Was this a move
/// between your accounts?" (decision 0030, rule 5).
final ownMoveQuestionsProvider = StreamProvider<Map<int, OwnMoveQuestion>>((
  ref,
) async* {
  final db = ref.watch(appDatabaseProvider);
  yield await ownMoveQuestions(db);
  // Answers are kept in the settings.
  await for (final _ in db.tableUpdates(
    TableUpdateQuery.onAllTables([
      db.transactions,
      db.accounts,
      db.appSettings,
    ]),
  )) {
    yield await ownMoveQuestions(db);
  }
});

/// Entries that may be the other side of transaction `id`, which happened
/// `at`, best first, for "Was this your own money?".
final transferSuggestionsProvider =
    FutureProvider.family<List<TransferSuggestion>, ({int id, DateTime at})>((
      ref,
      key,
    ) async {
      ref.watch(ledgerChangesProvider);
      final transactions = ref.watch(transactionsRepositoryProvider);
      final (:id, :at) = key;
      final entries = await transactions.ledgerEntries(
        from: at.subtract(waitingTransferWindow),
        to: at.add(waitingTransferWindow),
      );
      final entry = entries.where((e) => e.id == id).firstOrNull;
      if (entry == null) return const [];
      return suggestTransferPartners(
        entry,
        entries,
        declined: await transactions.declinedTransfers(),
      );
    });

/// Entries in another currency that may be the other side of transaction
/// `id`, which happened `at`, best first, for "Was this your own money?":
/// each with the rate the two give (see [suggestCrossCurrencyPartners]).
final crossCurrencySuggestionsProvider =
    FutureProvider.family<List<CrossCurrencyTransfer>, ({int id, DateTime at})>(
      (ref, key) async {
        ref.watch(ledgerChangesProvider);
        final transactions = ref.watch(transactionsRepositoryProvider);
        final converter = ref.watch(currencyConverterProvider);
        final (:id, :at) = key;
        final entries = await transactions.ledgerEntries(
          from: at.subtract(waitingTransferWindow),
          to: at.add(waitingTransferWindow),
        );
        final entry = entries.where((e) => e.id == id).firstOrNull;
        if (entry == null) return const [];
        final accounts = await ref.watch(accountsRepositoryProvider).all();
        return suggestCrossCurrencyPartners(
          entry,
          entries,
          accounts: {
            for (final a in accounts)
              a.id: TransferAccount(
                currency: a.currency,
                reference: a.reference,
                institutionId: a.institutionId,
              ),
          },
          rateOn: dayRatesOf(converter),
          declined: await transactions.declinedTransfers(),
        );
      },
    );

/// What an own transfer typed while checking a message would pair with.
typedef TransferQuery = ({
  int otherAccountId,
  bool otherIsInflow,
  int amountMinor,
  int feeMinor,
  DateTime at,
});

/// The other side already in the ledger for [TransferQuery], if any: the
/// best unpaired entry on the other account, the opposite way, within
/// [waitingTransferWindow].
final transferPartnerProvider =
    FutureProvider.family<LedgerEntry?, TransferQuery>((ref, query) async {
      ref.watch(ledgerChangesProvider);
      final transactions = ref.watch(transactionsRepositoryProvider);
      final entries = await transactions.ledgerEntries(
        from: query.at.subtract(waitingTransferWindow),
        to: query.at.add(waitingTransferWindow),
      );
      final other = entries.where((e) => e.accountId == query.otherAccountId);
      if (other.isEmpty) return null;
      final probe = LedgerEntry(
        id: -1,
        accountId: -1,
        occurredAt: query.at,
        amountMinor: query.amountMinor,
        direction: query.otherIsInflow
            ? TransactionDirection.outflow
            : TransactionDirection.inflow,
        kind: TransactionKind.bank,
        currency: other.first.currency,
        feeMinor: query.otherIsInflow ? query.feeMinor : 0,
      );
      final found = suggestTransferPartners(
        probe,
        other,
        declined: await transactions.declinedTransfers(),
        limit: 1,
      );
      return found.isEmpty ? null : found.first.partner;
    });
