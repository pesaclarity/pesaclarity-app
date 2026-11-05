import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/category_seeds.dart';
import '../../../data/repositories/quick_records_repository.dart';
import '../../../data/repositories/sales_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/sales/sale_matching.dart';
import '../../../domain/sales/sales_summary.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/spaces/space_categories.dart';
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

/// Records a business's sales, purchases and payments, and matches their
/// M-Pesa and bank parts to payment messages.
class SalesController {
  SalesController(this._ref);

  final Ref _ref;

  SalesRepository get _sales => _ref.read(salesRepositoryProvider);
  QuickRecordsRepository get _records =>
      _ref.read(quickRecordsRepositoryProvider);
  AppDatabase get _db => _ref.read(appDatabaseProvider);

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
    final category = await _sales.salesCategoryId();
    final before = {...await _sales.waiting(salesCategoryId: category)};
    final saleId = await _sales.record(
      at: _now(),
      parts: parts,
      salesCategoryId: category,
      cashAccountId: await _cashAccount(),
      credit: credit,
      note: note,
    );
    final mine = {
      for (final w in await _sales.waiting(salesCategoryId: category))
        if (!before.contains(w)) w,
    };
    final matched = await matchWaiting();
    return SaleOutcome(
      saleId: saleId,
      matched: [
        for (final MapEntry(:key, :value) in matched.entries)
          if (mine.contains(key)) value,
      ],
    );
  }

  /// Stock or a cost bought now; with credit, [supplier] is owed it.
  Future<void> bought({
    required int amountMinor,
    required SalePaymentMethod method,
    required int categoryId,
    String? supplier,
    CalendarDate? dueDate,
    String? note,
  }) async {
    await _records.bought(
      at: _now(),
      amountMinor: amountMinor,
      method: method,
      categoryId: categoryId,
      cashAccountId: await _cashAccount(),
      supplier: supplier,
      dueDate: dueDate,
      note: note,
    );
    await matchWaiting();
  }

  /// [customer] paid [amountMinor] of what they owe.
  Future<void> gotPaid({
    required String customer,
    required int amountMinor,
    required SalePaymentMethod method,
  }) async {
    await _records.gotPaid(
      at: _now(),
      amountMinor: amountMinor,
      method: method,
      customer: customer,
      categoryId: await ensureCategory(_db, customerPaymentsSeed),
      cashAccountId: await _cashAccount(),
    );
    await matchWaiting();
  }

  /// The business paid [amountMinor] of what it owes [supplier] on
  /// [debtId].
  Future<void> paid({
    required int debtId,
    required String supplier,
    required int amountMinor,
    required SalePaymentMethod method,
  }) async {
    await _records.paid(
      at: _now(),
      amountMinor: amountMinor,
      method: method,
      debtId: debtId,
      supplier: supplier,
      categoryId: await ensureCategory(_db, supplierPaymentsSeed),
      cashAccountId: await _cashAccount(),
    );
    await matchWaiting();
  }

  /// Everything waiting for an M-Pesa or bank message, oldest first.
  Future<List<WaitingPayment>> waiting() async {
    final category = await _sales.salesCategoryId();
    return [
      ...await _sales.waiting(salesCategoryId: category),
      ...await _records.waiting(),
    ]..sort((a, b) => a.at.compareTo(b.at));
  }

  Future<Object?> _matching = Future.value();

  /// Matches waiting records with payment messages around their time, and
  /// returns each match. Runs one at a time, so a payment is never matched
  /// twice when messages and records arrive together.
  Future<Map<WaitingPayment, LedgerEntry>> matchWaiting() {
    final run = _matching.then((_) => _match());
    _matching = run.then<Object?>((_) => null, onError: (_) => null);
    return run;
  }

  Future<Map<WaitingPayment, LedgerEntry>> _match() async {
    final waiting = await this.waiting();
    if (waiting.isEmpty) return const {};
    final from = waiting.first.at.subtract(saleMatchWindow);
    final to = waiting.last.at.add(saleMatchWindow);
    final entries = await _ref
        .read(transactionsRepositoryProvider)
        .ledgerEntries(from: from, to: to);
    final accounts = {
      for (final a in await _ref.read(accountsRepositoryProvider).openings())
        a.id: a.type,
    };
    final matches = matchWaitingPayments(
      waiting,
      entries,
      accountTypes: accounts,
      linked: {
        ...await _sales.linkedTransactions(),
        ...await _records.linkedTransactions(),
      },
    );
    if (matches.isEmpty) return const {};
    final byId = {for (final e in entries) e.id: e};
    for (final MapEntry(key: w, value: transactionId) in matches.entries) {
      if (w.kind == WaitingKind.sale) {
        await _sales.link(w.id, transactionId, salesCategoryId: w.categoryId);
      } else {
        await _records.link(w.id, transactionId);
      }
    }
    return {
      for (final MapEntry(:key, :value) in matches.entries) key: ?byId[value],
    };
  }

  /// A waiting record was paid in cash after all.
  Future<void> paidInCash(WaitingPayment payment) async {
    final cash = await _cashAccount();
    if (payment.kind == WaitingKind.sale) {
      await _sales.paidInCash(
        payment.id,
        at: _now(),
        salesCategoryId: payment.categoryId,
        cashAccountId: cash,
      );
    } else {
      await _records.paidInCash(payment.id, at: _now(), cashAccountId: cash);
    }
  }

  /// Drops a waiting record that will not be paid.
  Future<void> removeWaiting(WaitingPayment payment) =>
      payment.kind == WaitingKind.sale
      ? _sales.removeWaiting(payment.id)
      : _records.remove(payment.id);
}

final salesControllerProvider = Provider<SalesController>(SalesController.new);

/// Sales, purchases and payments waiting for their M-Pesa or bank message.
final waitingPaymentsProvider = FutureProvider<List<WaitingPayment>>((ref) {
  ref.watch(ledgerChangesProvider);
  return ref.watch(salesControllerProvider).waiting();
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
