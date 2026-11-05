import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/sales_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/sales/sale_matching.dart';
import '../../../domain/sales/sales_summary.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/calendar.dart';
import '../../books/application/books_providers.dart';
import '../../spaces/application/business_setup_providers.dart';
import '../../spaces/application/spaces_providers.dart';

/// What happened to a sale just recorded.
class SaleOutcome {
  const SaleOutcome({required this.saleId, this.matched = const []});

  final int saleId;

  /// Payment messages that had already come in and now pay for it.
  final List<LedgerEntry> matched;
}

/// Records sales and matches their M-Pesa and bank parts to payment
/// messages.
class SalesController {
  SalesController(this._ref);

  final Ref _ref;

  SalesRepository get _sales => _ref.read(salesRepositoryProvider);

  Future<int> _cashAccount() => _ref
      .read(accountsRepositoryProvider)
      .cashAccount(
        name: cashAccountName,
        openingDate: CalendarDate.local(_now()).startInstant,
      );

  DateTime _now() => _ref.read(clockProvider)();

  /// Records a sale paid by [parts] now, and matches any part whose payment
  /// message has already come in.
  Future<SaleOutcome> sell(
    List<SalePart> parts, {
    String? note,
    CreditTerms? credit,
  }) async {
    final now = _now();
    final category = await _sales.salesCategoryId();
    final saleId = await _sales.record(
      at: now,
      parts: parts,
      salesCategoryId: category,
      cashAccountId: await _cashAccount(),
      credit: credit,
      note: note,
    );
    final matched = await matchWaiting();
    return SaleOutcome(
      saleId: saleId,
      matched: [
        for (final e in matched.entries)
          if (e.key.saleId == saleId) e.value,
      ],
    );
  }

  Future<Object?> _matching = Future.value();

  /// Matches waiting parts with payment messages around their time, and
  /// returns each match. Runs one at a time, so a payment is never matched
  /// twice when messages and sales arrive together.
  Future<Map<WaitingPayment, LedgerEntry>> matchWaiting() {
    final run = _matching.then((_) => _match());
    _matching = run.then<Object?>((_) => null, onError: (_) => null);
    return run;
  }

  Future<Map<WaitingPayment, LedgerEntry>> _match() async {
    final waiting = await _sales.waiting();
    if (waiting.isEmpty) return const {};
    final from = waiting.first.soldAt.subtract(saleMatchWindow);
    final to = waiting
        .map((w) => w.soldAt)
        .reduce((a, b) => a.isAfter(b) ? a : b)
        .add(saleMatchWindow);
    final entries = await _ref
        .read(transactionsRepositoryProvider)
        .ledgerEntries(from: from, to: to);
    final category = await _sales.salesCategoryId();
    final byPayment = {for (final w in waiting) w.paymentId: w};
    final byId = {for (final e in entries) e.id: e};
    final matches = await _sales.matchWaiting(
      entries,
      salesCategoryId: category,
    );
    return {
      for (final MapEntry(:key, :value) in matches.entries)
        byPayment[key]!: ?byId[value],
    };
  }

  /// A waiting part was paid in cash after all.
  Future<void> paidInCash(WaitingPayment payment) async => _sales.paidInCash(
    payment.paymentId,
    at: _now(),
    salesCategoryId: await _sales.salesCategoryId(),
    cashAccountId: await _cashAccount(),
  );

  /// Drops a waiting part that will not be paid.
  Future<void> removeWaiting(WaitingPayment payment) =>
      _sales.removeWaiting(payment.paymentId);
}

final salesControllerProvider = Provider<SalesController>(SalesController.new);

/// M-Pesa and bank parts of sales still waiting for their message.
final waitingPaymentsProvider = FutureProvider<List<WaitingPayment>>((ref) {
  ref.watch(ledgerChangesProvider);
  return ref.watch(salesRepositoryProvider).waiting();
});

/// Keeps matching waiting sales to payment messages as they come in, while
/// a business is open.
final saleMatcherProvider = Provider<void>((ref) {
  if (ref.watch(activeSpaceProvider).kind != SpaceKind.business) return;
  ref.listen(ledgerChangesProvider, (_, _) async {
    try {
      await ref.read(salesControllerProvider).matchWaiting();
    } on Object catch (error) {
      if (kDebugMode) debugPrint('Matching sales failed: $error');
    }
  }, fireImmediately: true);
});

/// Today's sales by how people paid, and what a usual day like it sells.
class SalesToday {
  const SalesToday({required this.day, this.usualMinor});

  final SalesDay day;
  final int? usualMinor;
}

final salesTodayProvider = FutureProvider<SalesToday>((ref) async {
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final books = await ref.watch(booksProvider.future);
  final accounts = {
    for (final a in await ref.watch(accountsRepositoryProvider).openings())
      a.id: a.type,
  };
  final category = await ref.watch(salesRepositoryProvider).salesCategoryId();
  return SalesToday(
    day: salesOn(
      books,
      today,
      salesCategoryId: category,
      accountTypes: accounts,
      currency: BaseCurrency.code,
    ),
    usualMinor: usualSalesFor(
      books,
      today,
      salesCategoryId: category,
      accountTypes: accounts,
      currency: BaseCurrency.code,
    ),
  );
});
