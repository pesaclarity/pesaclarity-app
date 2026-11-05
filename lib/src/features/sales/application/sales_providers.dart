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
import '../../../data/repositories/stock_repository.dart';
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
  const SaleOutcome({
    required this.saleId,
    this.matched = const [],
    this.waiting = const [],
  });

  final int saleId;

  /// Payment messages that had already come in and now pay for it.
  final List<LedgerEntry> matched;

  /// Its parts still waiting for a message.
  final List<WaitingPayment> waiting;
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
    List<SaleLine> lines = const [],
  }) async {
    final category = await _sales.salesCategoryId();
    final before = {...await _sales.waiting(salesCategoryId: category)};
    final at = _now();
    final saleId = await _sales.record(
      at: at,
      parts: parts,
      salesCategoryId: category,
      cashAccountId: await _cashAccount(),
      credit: credit,
      note: note,
    );
    if (lines.isNotEmpty) {
      await _ref.read(stockRepositoryProvider).sold(saleId, lines, at: at);
    }
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
      waiting: [
        for (final w in mine)
          if (!matched.containsKey(w)) w,
      ],
    );
  }

  /// Stock or a cost bought now; with credit, [supplier] is owed it. With
  /// [itemId], [quantityMilli] of it goes into stock at what was paid.
  Future<void> bought({
    required int amountMinor,
    required SalePaymentMethod method,
    required int categoryId,
    String? supplier,
    CalendarDate? dueDate,
    String? note,
    int? itemId,
    int? quantityMilli,
  }) async {
    final at = _now();
    final recordId = await _records.bought(
      at: at,
      amountMinor: amountMinor,
      method: method,
      categoryId: categoryId,
      cashAccountId: await _cashAccount(),
      supplier: supplier,
      dueDate: dueDate,
      note: note,
      itemId: itemId,
    );
    if (itemId != null && quantityMilli != null && quantityMilli > 0) {
      await _ref
          .read(stockRepositoryProvider)
          .restock(
            itemId,
            quantityMilli: quantityMilli,
            paidMinor: amountMinor,
            at: at,
            recordId: recordId,
          );
    }
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

  /// Payment messages that could pay for waiting sale part [w]: money in on
  /// M-Pesa or bank around its time, not paying for anything else yet,
  /// newest first.
  Future<List<LedgerEntry>> candidatesFor(WaitingPayment w) async {
    final entries = await _ref
        .read(transactionsRepositoryProvider)
        .ledgerEntries(
          from: w.at.subtract(saleMatchWindow),
          to: w.at.add(saleMatchWindow),
        );
    final types = {
      for (final a in await _ref.read(accountsRepositoryProvider).openings())
        a.id: a.type,
    };
    final linked = {
      ...await _sales.linkedTransactions(),
      ...await _records.linkedTransactions(),
    };
    final out = [
      for (final e in entries)
        if (e.isInflow &&
            e.transferPairId == null &&
            !linked.contains(e.id) &&
            (types[e.accountId] == AccountType.mpesa ||
                types[e.accountId] == AccountType.bank) &&
            (e.categoryId == null ||
                e.categoryIsAuto ||
                e.categoryId == w.categoryId))
          e,
    ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return out;
  }

  /// Pays waiting sale part [w] with [chosen] messages. Short of it, the
  /// rest goes as [short] says; over it, the extra as [over] says.
  Future<void> settle(
    WaitingPayment w,
    List<LedgerEntry> chosen, {
    ShortBy? short,
    OverBy? over,
    CreditTerms? credit,
  }) async {
    final paid = chosen.fold(0, (sum, e) => sum + e.amountMinor);
    final cash = await _cashAccount();
    await _sales.settle(
      w.id,
      [for (final e in chosen) (id: e.id, amountMinor: e.amountMinor)],
      salesCategoryId: w.categoryId,
      cashAccountId: cash,
      at: _now(),
      short: short,
      credit: credit,
      keepExtra: over == OverBy.keepWithSale,
    );
    final extra = paid - w.amountMinor;
    if (extra > 0 &&
        (over == OverBy.changeInCash || over == OverBy.changeByMpesa)) {
      final who = chosen.first.payeeName ?? chosen.first.counterpartyName;
      await _records.change(
        at: _now(),
        amountMinor: extra,
        method: over == OverBy.changeInCash
            ? SalePaymentMethod.cash
            : SalePaymentMethod.mpesa,
        salesCategoryId: w.categoryId,
        cashAccountId: cash,
        customer: who,
      );
      await matchWaiting();
    }
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
