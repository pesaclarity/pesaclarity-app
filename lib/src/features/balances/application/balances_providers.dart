import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/ledger/balance_check.dart';
import '../../../domain/ledger/balances.dart';
import '../../../domain/ledger/fuliza_debt.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/ledger/on_hand.dart';
import '../../../domain/ledger/own_transfers.dart';
import '../../../domain/time/calendar.dart';
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
  });

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

  /// Every account's worth, in the base currency.
  int totalMinor(String base) => accounts
      .where((a) => a.opening.currency == base)
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
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(from: from, to: now.add(const Duration(seconds: 1)));
  final checkFrom = now.subtract(const Duration(days: balanceCheckDays));
  final at = now.add(const Duration(seconds: 1));

  final list = <AccountBalance>[];
  for (final row in rows) {
    final opening = openings[row.id];
    if (opening == null) continue;
    final check = checkAccount(opening, entries);
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
    final wallet = balanceAt(opening, entries, at: at);
    final owed = fulizaOwedAt(opening, entries, at: at);
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
  list.sort((a, b) {
    final bySavings = (a.isSavings ? 1 : 0).compareTo(b.isSavings ? 1 : 0);
    return bySavings != 0
        ? bySavings
        : a.account.name.toLowerCase().compareTo(b.account.name.toLowerCase());
  });
  return BalancesOverview(accounts: list, entries: entries, now: now);
});

/// What M-Pesa's balances show Fuliza did with no message of its own, by
/// the entry whose balance shows it, for Activity.
final fulizaAutoProvider = FutureProvider<Map<int, FulizaAuto>>((ref) async {
  final overview = await ref.watch(balancesOverviewProvider.future);
  return {
    for (final a in overview.accounts)
      if (a.opening.canOweFuliza)
        for (final auto in WalletWalk.of(
          a.opening,
          overview.entries,
        ).fuliza.auto)
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
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(from: from, to: today.addDays(1).startInstant);
  final fund = await ref.watch(rainyDayFundProvider.future);
  return OnHand.at(
    accounts,
    entries,
    today: today,
    rainyDayMinor: fund.balanceMinor,
  );
});

/// Pairs own transfers over the whole history once, after the update that
/// started pairing them. Safe to run again: only unpaired entries pair.
final pairHistoryOnceProvider = FutureProvider<void>((ref) async {
  const key = 'ledger.ownTransfersPaired';
  final settings = ref.watch(appSettingsRepositoryProvider);
  if (await settings.readJson(key) != null) return;
  await ref.watch(transactionsRepositoryProvider).pairOwnTransfers();
  await settings.writeJson(key, {'version': 1});
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
