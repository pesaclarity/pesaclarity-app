import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/enums.dart';
import '../../../domain/ledger/balances.dart';
import '../../../domain/spaces/business_setup.dart';
import '../../../domain/time/calendar.dart';

/// Name of the drawer account a business gets for cash.
const cashAccountName = 'Cash';

/// The open business's setup: what it sells and whether its records have
/// started. Kept with the space.
class BusinessSetupController extends AsyncNotifier<BusinessSetup> {
  static const settingsKey = 'business.setup';

  AppSettingsRepository get _settings =>
      ref.read(appSettingsRepositoryProvider);

  @override
  Future<BusinessSetup> build() async => BusinessSetup.fromJson(
    await ref.watch(appSettingsRepositoryProvider).readJson(settingsKey),
  );

  Future<BusinessSetup> _current() async => state.value ?? await future;

  Future<void> _save(BusinessSetup next) async {
    await _settings.writeJson(settingsKey, next.toJson());
    state = AsyncData(next);
  }

  Future<void> chooseSells(BusinessSells sells) async =>
      _save((await _current()).copyWith(sells: sells));

  /// Starts the books today: the drawer holds [cashMinor], and each account
  /// in [accounts] (by id) holds its amount. Earlier records stay, and the
  /// balances count from today.
  Future<void> startRecords({
    required int cashMinor,
    required Map<int, int> accounts,
  }) async {
    final now = ref.read(clockProvider)();
    final today = CalendarDate.local(now).startInstant;
    final repo = ref.read(accountsRepositoryProvider);
    final cash = await repo.cashAccount(
      name: cashAccountName,
      openingDate: today,
    );
    await repo.setOpening(cash, cashMinor, today);
    for (final MapEntry(:key, :value) in accounts.entries) {
      await repo.setOpening(key, value, today);
    }
    await _save((await _current()).copyWith(recordsStartedAt: now.toUtc()));
  }
}

final businessSetupProvider =
    AsyncNotifierProvider<BusinessSetupController, BusinessSetup>(
      BusinessSetupController.new,
    );

/// A money account to give an opening balance, with what the app suggests.
class OpeningLine {
  const OpeningLine({
    required this.accountId,
    required this.name,
    required this.type,
    required this.suggestedMinor,
    required this.fromMessage,
  });

  final int accountId;
  final String name;
  final AccountType type;
  final int suggestedMinor;

  /// Whether [suggestedMinor] comes from a balance a message reported.
  final bool fromMessage;
}

/// The business's M-Pesa, till and bank accounts (not cash or savings),
/// each with today's balance as far as the records know.
final openingLinesProvider = FutureProvider<List<OpeningLine>>((ref) async {
  final now = ref.watch(clockProvider)();
  final accounts = await ref.watch(accountsRepositoryProvider).openings();
  final names = {
    for (final a
        in await ref.watch(accountsRepositoryProvider).watchAll().first)
      a.id: a.name,
  };
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(from: DateTime.utc(1970), to: now);
  return [
    for (final a in accounts)
      if (a.type != AccountType.cash && !a.isSavings)
        OpeningLine(
          accountId: a.id,
          name: names[a.id] ?? 'Account',
          type: a.type,
          suggestedMinor: balanceAt(a, entries, at: now),
          fromMessage: entries.any(
            (e) => e.accountId == a.id && e.balanceAfterMinor != null,
          ),
        ),
  ];
});
