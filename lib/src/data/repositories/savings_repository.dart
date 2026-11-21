import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/savings/savings_account.dart';
import '../../domain/savings/savings_pockets.dart';
import '../../domain/savings/savings_product.dart';
import '../../domain/savings/savings_prompt.dart';
import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';
import 'savings_links.dart';
import 'transactions_repository.dart';

/// Savings accounts the app keeps for a savings app, fund or SACCO it knows
/// (see `savingsProducts`), such as Chumz: payments into one count as money
/// moved to an account of the person's own, and its balance is whatever
/// they last typed, with interest worked out from that.
///
/// The screens use only this and the savings providers. The tables behind
/// it, and the hooks that link each new payment as it arrives, are in
/// `savings_links.dart`.
abstract interface class SavingsRepository {
  /// Every savings account kept in this space, oldest first.
  Future<List<SavingsAccountSummary>> accounts();

  /// One savings account; null when [accountId] is not one.
  Future<SavingsAccountSummary?> account(int accountId);

  /// What the records show of [product]: the account codes paid into and
  /// the payments adding it would turn into transfers.
  Future<SavingsDiscovery> discover(SavingsProduct product);

  /// The question to ask under a payment: the first known product the
  /// person has neither added nor said is not theirs that their records
  /// show a payment into. Null when there is nothing to ask.
  Future<SavingsPrompt?> prompt();

  /// Adds [product] as a savings account called [name] (the product's name
  /// when not given), opened at [at] or at its first payment, and turns
  /// every payment into it and all money back from it into transfers, in
  /// one step. Each account code becomes a pocket: named and locked as
  /// [pockets] say, else named after its code.
  ///
  /// With [promptedTransactionId], the payment the question was asked
  /// under, the line that confirms it once is kept for [addedNotice].
  /// Adding a product that was said to be not theirs forgets that answer;
  /// adding one that is already there only brings it in step.
  Future<SavingsAdded> add(
    SavingsProduct product, {
    required DateTime at,
    String? name,
    List<SavingsPocketDraft> pockets = const [],
    int? promptedTransactionId,
  });

  /// "It's not mine": never ask about [productId] again. Payments to it
  /// stay as they are.
  Future<void> decline(String productId);

  /// The products the person said are not theirs, or removed.
  Future<Set<String>> declined();

  /// Records the balances the savings app shows at [at], one for each
  /// pocket in [balanceByPocket] (by pocket id, in the account's minor
  /// units). What a balance shows above the records is interest, and below
  /// them a correction; a pocket's first balance is interest only when the
  /// gap is small (see `setupGapIsInterest`). With [gapIsInterest] false,
  /// as the person says, none of it is interest.
  ///
  /// Throws a [StateError] while money in or out from before [at] is in no
  /// pocket (see [SavingsAccountSummary.unassigned]): give each a pocket
  /// with [assignEntry] first, so no balance is set against money it does
  /// not know about. Throws an [ArgumentError] for a pocket that is not
  /// one of the account's, or a balance below zero.
  Future<void> updateBalances(
    int accountId, {
    required Map<int, int> balanceByPocket,
    required DateTime at,
    bool gapIsInterest = true,
  });

  /// Undoes the update typed at [at]: its balances go, and the interest and
  /// correction they showed with them.
  Future<void> undoUpdate(int accountId, DateTime at);

  /// Saves a pocket's [name], the start of the day it is [lockedUntil]
  /// (null when open), and whether the person said its code is not theirs
  /// ([ignored]): its payments then go back to how they were counted and it
  /// holds nothing, until it is taken back.
  Future<void> savePocket(
    int pocketId, {
    required String name,
    required DateTime? lockedUntil,
    bool ignored = false,
  });

  /// Puts the money in or out [transactionId] (an entry on a savings
  /// account) in [pocketId], or in none. Throws an [ArgumentError] for a
  /// pocket of another account, and for a payment that carries an account
  /// code, which stays in that code's pocket.
  Future<void> assignEntry(int transactionId, int? pocketId);

  /// Gives the account another name. The provider stays as the product
  /// has it.
  Future<void> rename(int accountId, String name);

  /// Removes the account: its payments go back to how they were counted,
  /// and its pockets, typed balances, interest and corrections go. The
  /// account itself goes too unless the person typed entries of their own
  /// on it; then it stays as an ordinary account. The product counts as
  /// declined, so it is not asked about again.
  Future<void> remove(int accountId);

  /// The line to show once after a product was added; null when there is
  /// none or it was seen.
  Future<SavingsAddedNotice?> addedNotice();

  /// Marks [addedNotice] as seen.
  Future<void> markAddedNoticeSeen();

  /// What transaction [transactionId] is to a savings account: an entry on
  /// one, or the payment an entry mirrors. Null for any other transaction.
  Future<SavingsEntryLink?> entryOf(int transactionId);

  /// Emits whenever something the savings screens show may have changed.
  Stream<void> watchChanges();
}

class DriftSavingsRepository implements SavingsRepository {
  DriftSavingsRepository(this._db, {this.products = savingsProducts});

  final AppDatabase _db;

  /// The products this app knows.
  final List<SavingsProduct> products;

  /// Answers kept in settings, which no table update reports.
  final _answers = StreamController<void>.broadcast();

  /// Stops reporting changes.
  Future<void> dispose() => _answers.close();

  Future<Map<String, Object?>?> _setting(String key) async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    if (row == null) return null;
    try {
      final decoded = jsonDecode(row.value);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _saveSetting(String key, Map<String, Object?> value) async {
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: jsonEncode(value)),
        );
    if (!_answers.isClosed) _answers.add(null);
  }

  Future<Account?> _kept(int accountId) async {
    final account = await (_db.select(
      _db.accounts,
    )..where((a) => a.id.equals(accountId))).getSingleOrNull();
    return account?.product == null ? null : account;
  }

  Future<Account> _mustBeKept(int accountId) async =>
      await _kept(accountId) ??
      (throw ArgumentError.value(
        accountId,
        'accountId',
        'not a savings account',
      ));

  @override
  Future<List<SavingsAccountSummary>> accounts() async => [
    for (final a
        in await (_db.select(_db.accounts)
              ..where((a) => a.product.isNotNull())
              ..orderBy([(a) => OrderingTerm.asc(a.id)]))
            .get())
      await _summary(a),
  ];

  @override
  Future<SavingsAccountSummary?> account(int accountId) async {
    final account = await _kept(accountId);
    return account == null ? null : _summary(account);
  }

  Future<SavingsAccountSummary> _summary(Account account) async {
    final pockets = await savingsPocketsOf(_db, account.id);
    final ids = [for (final p in pockets) p.id];
    // A goal in another currency than the account cannot read its pocket.
    final goals = {
      if (ids.isNotEmpty)
        for (final g in await (_db.select(
          _db.goals,
        )..where((g) => g.savedInPocketId.isIn(ids))).get())
          if (g.currency == account.currency) g.savedInPocketId!: g,
    };
    final readings = <int, List<PocketReading>>{};
    if (ids.isNotEmpty) {
      for (final r in await (_db.select(
        _db.savingsReadings,
      )..where((r) => r.pocketId.isIn(ids))).get()) {
        (readings[r.pocketId] ??= []).add(
          PocketReading(
            at: r.at,
            balanceMinor: r.balanceMinor,
            gapIsInterest: r.gapIsInterest,
          ),
        );
      }
    }
    return SavingsAccountSummary.of(
      accountId: account.id,
      name: account.name,
      productId: account.product!,
      product: savingsProductById(account.product, products: products),
      currency: account.currency,
      pockets: [
        for (final p in pockets)
          PocketFacts(
            id: p.id,
            code: p.code,
            name: p.name,
            lockedUntil: p.lockedUntil == null
                ? null
                : CalendarDate.local(p.lockedUntil!),
            ignored: p.ignored,
            goalId: goals[p.id]?.id,
            goalTargetMinor: goals[p.id]?.targetMinor,
          ),
      ],
      entries: [
        for (final e in await savingsEntriesOf(_db, account.id))
          SavingsEntry(
            transactionId: e.row.id,
            kind: e.entry.kind,
            at: e.row.occurredAt,
            amountMinor: e.row.amountMinor,
            pocketId: e.entry.pocketId,
            otherAccountId: e.row.transferAccountId,
            otherTransactionId: e.row.transferPairId,
          ),
      ],
      readings: readings,
    );
  }

  @override
  Future<SavingsDiscovery> discover(SavingsProduct product) async {
    final found = await findSavingsPayments(_db, product);
    final codes = <String, List<TransactionRecord>>{};
    var payments = 0;
    var moneyBack = 0;
    var paidIn = 0;
    var takenOut = 0;
    var skipped = 0;
    DateTime? first;
    TransactionRecord? latest;
    String latestCode = '';
    for (final p in found) {
      if (p.skipped) {
        skipped++;
        continue;
      }
      final r = p.record;
      if (first == null || r.occurredAt.isBefore(first)) first = r.occurredAt;
      switch (p.move) {
        case SavingsPayIn(:final code):
          payments++;
          paidIn += r.amountMinor;
          (codes[code] ??= []).add(r);
          latest = r;
          latestCode = code;
        case SavingsMoneyBack():
          moneyBack++;
          takenOut += r.amountMinor;
      }
    }
    return SavingsDiscovery(
      product: product,
      codes: [
        for (final MapEntry(key: code, value: rows) in codes.entries)
          SavingsCodeFound(
            code: code,
            payments: rows.length,
            paidInMinor: rows.fold(0, (sum, r) => sum + r.amountMinor),
            firstAt: rows.first.occurredAt,
            lastAt: rows.last.occurredAt,
          ),
      ],
      payments: payments,
      moneyBack: moneyBack,
      paidInMinor: paidIn,
      takenOutMinor: takenOut,
      skipped: skipped,
      firstAt: first,
      latestPayIn: latest == null
          ? null
          : SavingsPrompt(
              product: product,
              transactionId: latest.id,
              accountId: latest.accountId,
              at: latest.occurredAt,
              amountMinor: latest.amountMinor,
              currency: latest.currency,
              paidTo: savingsPayeeKey(
                latest.counterpartyName ??
                    latest.counterpartyValue?.split('#').first ??
                    product.name,
              ),
              code: latestCode,
            ),
    );
  }

  @override
  Future<SavingsPrompt?> prompt() async {
    final no = await declined();
    final added = {
      for (final a in await (_db.select(
        _db.accounts,
      )..where((a) => a.product.isNotNull())).get())
        a.product,
    };
    for (final product in products) {
      if (no.contains(product.id) || added.contains(product.id)) continue;
      final ask = (await discover(product)).latestPayIn;
      if (ask != null) return ask;
    }
    return null;
  }

  @override
  Future<SavingsAdded> add(
    SavingsProduct product, {
    required DateTime at,
    String? name,
    List<SavingsPocketDraft> pockets = const [],
    int? promptedTransactionId,
  }) async {
    final added = await _db.transaction(() async {
      final existing =
          await (_db.select(_db.accounts)
                ..where((a) => a.product.equals(product.id))
                ..orderBy([(a) => OrderingTerm.asc(a.id)])
                ..limit(1))
              .getSingleOrNull();
      final accountId =
          existing?.id ??
          await _db
              .into(_db.accounts)
              .insert(
                AccountsCompanion.insert(
                  name: _name(name) ?? product.name,
                  type: product.type,
                  currency: Value(product.currency),
                  openingDate: at,
                  product: Value(product.id),
                ),
              );
      for (final draft in pockets) {
        final pocketName = _name(draft.name) ?? draft.code;
        if (pocketName.isEmpty) continue;
        await _db
            .into(_db.savingsPockets)
            .insert(
              SavingsPocketsCompanion.insert(
                accountId: accountId,
                code: draft.code,
                name: pocketName,
                lockedUntil: Value(draft.lockedUntil),
              ),
              onConflict: DoUpdate(
                (_) => SavingsPocketsCompanion(
                  name: Value(pocketName),
                  lockedUntil: Value(draft.lockedUntil),
                ),
                target: [_db.savingsPockets.accountId, _db.savingsPockets.code],
              ),
            );
      }
      final no = await declined();
      if (no.remove(product.id)) {
        await _saveSetting(savingsDeclinedKey, declinedProductsToJson(no));
      }
      final sync = await syncSavingsAccounts(
        _db,
        accountId: accountId,
        products: products,
      );
      if (promptedTransactionId != null) {
        final others = sync.linked.difference({promptedTransactionId});
        await _saveSetting(
          SavingsAddedNotice.settingsKey,
          SavingsAddedNotice(
            accountId: accountId,
            transactionId: promptedTransactionId,
            updated: others.length,
            at: at,
          ).toJson(),
        );
      }
      return SavingsAdded(
        accountId: accountId,
        linked: sync.linked.length,
        skipped: sync.skipped,
      );
    });
    if (!_answers.isClosed) _answers.add(null);
    return added;
  }

  /// [raw] trimmed to a name of 1 to 80 characters; null when empty.
  static String? _name(String? raw) {
    final name = raw?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
    if (name.isEmpty) return null;
    return name.length > 80 ? name.substring(0, 80) : name;
  }

  @override
  Future<void> decline(String productId) async {
    final no = await declined();
    if (no.add(productId)) {
      await _saveSetting(savingsDeclinedKey, declinedProductsToJson(no));
    }
  }

  @override
  Future<Set<String>> declined() async =>
      declinedProductsFromJson(await _setting(savingsDeclinedKey));

  @override
  Future<void> updateBalances(
    int accountId, {
    required Map<int, int> balanceByPocket,
    required DateTime at,
    bool gapIsInterest = true,
  }) => _db.transaction(() async {
    await _mustBeKept(accountId);
    // Every payment in first, so the balances are set against all of them.
    await syncSavingsAccounts(_db, accountId: accountId, products: products);
    final live = {
      for (final p in await savingsPocketsOf(_db, accountId))
        if (!p.ignored) p.id,
    };
    for (final MapEntry(key: pocketId, value: balance)
        in balanceByPocket.entries) {
      if (!live.contains(pocketId)) {
        throw ArgumentError.value(pocketId, 'balanceByPocket', 'not a pocket');
      }
      if (balance < 0) {
        throw ArgumentError.value(balance, 'balanceByPocket', 'below zero');
      }
    }
    final second = wholeSecond(at);
    final loose = [
      for (final e in await savingsEntriesOf(_db, accountId))
        if ((e.entry.kind == SavingsEntryKind.paidIn ||
                e.entry.kind == SavingsEntryKind.takenOut) &&
            !live.contains(e.entry.pocketId) &&
            !e.row.occurredAt.isAfter(second))
          e.row.id,
    ];
    if (loose.isNotEmpty) {
      throw StateError(
        'Money in or out is in no pocket yet (transactions $loose): give '
        'each a pocket before typing balances.',
      );
    }
    for (final MapEntry(key: pocketId, value: balance)
        in balanceByPocket.entries) {
      await _db
          .into(_db.savingsReadings)
          .insert(
            SavingsReadingsCompanion.insert(
              pocketId: pocketId,
              at: second,
              balanceMinor: balance,
              gapIsInterest: Value(gapIsInterest),
            ),
            onConflict: DoUpdate(
              (_) => SavingsReadingsCompanion(
                balanceMinor: Value(balance),
                gapIsInterest: Value(gapIsInterest),
              ),
              target: [_db.savingsReadings.pocketId, _db.savingsReadings.at],
            ),
          );
    }
    await settleSavingsReadings(_db, accountId, products: products);
  });

  @override
  Future<void> undoUpdate(int accountId, DateTime at) =>
      _db.transaction(() async {
        await _mustBeKept(accountId);
        await undoSavingsUpdate(_db, accountId, at);
      });

  @override
  Future<void> savePocket(
    int pocketId, {
    required String name,
    required DateTime? lockedUntil,
    bool ignored = false,
  }) => _db.transaction(() async {
    final pocket = await (_db.select(
      _db.savingsPockets,
    )..where((p) => p.id.equals(pocketId))).getSingleOrNull();
    final clean = _name(name);
    if (pocket == null) {
      throw ArgumentError.value(pocketId, 'pocketId', 'not found');
    }
    if (clean == null) throw ArgumentError.value(name, 'name', 'is empty');
    await (_db.update(
      _db.savingsPockets,
    )..where((p) => p.id.equals(pocketId))).write(
      SavingsPocketsCompanion(
        name: Value(clean),
        lockedUntil: Value(lockedUntil),
        ignored: Value(ignored),
      ),
    );
    if (ignored) {
      // A goal cannot be saved in a pocket that holds nothing.
      await (_db.update(_db.goals)
            ..where((g) => g.savedInPocketId.equals(pocketId)))
          .write(const GoalsCompanion(savedInPocketId: Value(null)));
    }
    await syncSavingsAccounts(
      _db,
      accountId: pocket.accountId,
      products: products,
    );
  });

  @override
  Future<void> assignEntry(
    int transactionId,
    int? pocketId,
  ) => _db.transaction(() async {
    final entry = await (_db.select(
      _db.savingsEntries,
    )..where((e) => e.transactionId.equals(transactionId))).getSingleOrNull();
    if (entry == null ||
        (entry.kind != SavingsEntryKind.paidIn &&
            entry.kind != SavingsEntryKind.takenOut)) {
      throw ArgumentError.value(
        transactionId,
        'transactionId',
        'not money in or out of a savings account',
      );
    }
    final row = await (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(transactionId))).getSingle();
    final account = await _mustBeKept(row.accountId);
    if (pocketId != null) {
      final pocket = await (_db.select(
        _db.savingsPockets,
      )..where((p) => p.id.equals(pocketId))).getSingleOrNull();
      if (pocket == null || pocket.accountId != account.id || pocket.ignored) {
        throw ArgumentError.value(pocketId, 'pocketId', 'not a pocket');
      }
    }
    final product = savingsProductById(account.product, products: products);
    final pairId = row.transferPairId;
    final paid = pairId == null
        ? null
        : await (_db.select(
            _db.transactions,
          )..where((t) => t.id.equals(pairId))).getSingleOrNull();
    final move = paid == null || product == null
        ? null
        : savingsMoveOf(
            kind: paid.kind,
            direction: paid.direction,
            counterpartyKind: paid.counterpartyKind,
            counterpartyValue: paid.counterpartyValue,
            counterpartyName: paid.counterpartyName,
            products: [product],
          );
    if (move is SavingsPayIn && move.code.isNotEmpty) {
      throw ArgumentError.value(
        transactionId,
        'transactionId',
        'stays in the pocket of its account code',
      );
    }
    await (_db.update(_db.savingsEntries)
          ..where((e) => e.transactionId.equals(transactionId)))
        .write(SavingsEntriesCompanion(pocketId: Value(pocketId)));
    await settleSavingsReadings(_db, account.id, products: products);
  });

  @override
  Future<void> rename(int accountId, String name) => _db.transaction(() async {
    final account = await _mustBeKept(accountId);
    final clean = _name(name);
    if (clean == null) throw ArgumentError.value(name, 'name', 'is empty');
    await (_db.update(_db.accounts)..where((a) => a.id.equals(accountId)))
        .write(AccountsCompanion(name: Value(clean)));
    // A pocket with no code is the account itself, under its name.
    await (_db.update(_db.savingsPockets)..where(
          (p) =>
              p.accountId.equals(accountId) &
              p.code.equals('') &
              p.name.equals(account.name),
        ))
        .write(SavingsPocketsCompanion(name: Value(clean)));
  });

  @override
  Future<void> remove(int accountId) async {
    await _db.transaction(() async {
      final account = await _mustBeKept(accountId);
      final t = _db.transactions;
      final entries = await savingsEntriesOf(_db, accountId);
      // Everything the app wrote goes; what the person typed stays.
      final written = [
        for (final e in entries)
          if (isSavingsMirror(e) ||
              e.entry.kind == SavingsEntryKind.interest ||
              e.entry.kind == SavingsEntryKind.correction)
            e.row.id,
      ];
      // The payments go back to how they were counted.
      await (_db.update(t)..where((t) => t.transferAccountId.equals(accountId)))
          .write(const TransactionsCompanion(transferAccountId: Value(null)));
      // SQLite caps the number of values in one query.
      for (var i = 0; i < written.length; i += 500) {
        final chunk = written.sublist(
          i,
          i + 500 > written.length ? written.length : i + 500,
        );
        await (_db.update(t)..where((t) => t.transferPairId.isIn(chunk))).write(
          const TransactionsCompanion(transferPairId: Value(null)),
        );
        await (_db.delete(t)..where((t) => t.id.isIn(chunk))).go();
      }
      await (_db.delete(_db.savingsEntries)..where(
            (e) => e.transactionId.isInQuery(
              _db.selectOnly(t)
                ..addColumns([t.id])
                ..where(t.accountId.equals(accountId)),
            ),
          ))
          .go();
      await (_db.delete(
        _db.savingsPockets,
      )..where((p) => p.accountId.equals(accountId))).go();

      Future<bool> any(String sql) async =>
          (await _db
                  .customSelect(sql, variables: [Variable.withInt(accountId)])
                  .get())
              .isNotEmpty;
      final inUse =
          await any(
            'SELECT 1 FROM transactions WHERE account_id = ? LIMIT 1',
          ) ||
          await any('SELECT 1 FROM recurring WHERE account_id = ? LIMIT 1') ||
          await any('SELECT 1 FROM imports WHERE account_id = ? LIMIT 1');
      if (inUse) {
        await (_db.update(_db.accounts)..where((a) => a.id.equals(accountId)))
            .write(const AccountsCompanion(product: Value(null)));
      } else {
        await (_db.delete(
          _db.accounts,
        )..where((a) => a.id.equals(accountId))).go();
      }
      final no = await declined();
      no.add(account.product!);
      await _saveSetting(savingsDeclinedKey, declinedProductsToJson(no));
      final notice = SavingsAddedNotice.fromJson(
        await _setting(SavingsAddedNotice.settingsKey),
      );
      if (notice?.accountId == accountId) {
        await _saveSetting(SavingsAddedNotice.settingsKey, const {});
      }
    });
    if (!_answers.isClosed) _answers.add(null);
  }

  @override
  Future<SavingsAddedNotice?> addedNotice() async {
    final notice = SavingsAddedNotice.fromJson(
      await _setting(SavingsAddedNotice.settingsKey),
    );
    return notice == null || notice.seen ? null : notice;
  }

  @override
  Future<void> markAddedNoticeSeen() async {
    final notice = SavingsAddedNotice.fromJson(
      await _setting(SavingsAddedNotice.settingsKey),
    );
    if (notice == null || notice.seen) return;
    await _saveSetting(
      SavingsAddedNotice.settingsKey,
      notice.asSeen().toJson(),
    );
  }

  @override
  Future<SavingsEntryLink?> entryOf(int transactionId) async {
    final row = await (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(transactionId))).getSingleOrNull();
    if (row == null) return null;
    Future<SavingsEntryRow?> entry(int? id) async => id == null
        ? null
        : (_db.select(
            _db.savingsEntries,
          )..where((e) => e.transactionId.equals(id))).getSingleOrNull();
    final own = await entry(row.id);
    final found = own ?? await entry(row.transferPairId);
    if (found == null) return null;
    final onAccount = own != null
        ? row
        : await (_db.select(
            _db.transactions,
          )..where((t) => t.id.equals(found.transactionId))).getSingle();
    final link = SavingsEntryLink(
      accountId: onAccount.accountId,
      entryTransactionId: found.transactionId,
      kind: found.kind,
      pocketId: found.pocketId,
    );
    return link.isDerived
        ? SavingsEntryLink(
            accountId: link.accountId,
            entryTransactionId: link.entryTransactionId,
            kind: link.kind,
            readingAt: onAccount.occurredAt,
          )
        : link;
  }

  @override
  Stream<void> watchChanges() => Stream<void>.multi((listener) {
    final ledger = ledgerTableUpdates(_db).listen(listener.addSync);
    // A pocket shows the goal saved in it.
    final goals = _db
        .tableUpdates(TableUpdateQuery.onTable(_db.goals))
        .listen(listener.addSync);
    final answers = _answers.stream.listen(listener.addSync);
    listener.onCancel = () async {
      await ledger.cancel();
      await goals.cancel();
      await answers.cancel();
    };
  });
}

final savingsRepositoryProvider = Provider<SavingsRepository>((ref) {
  final repository = DriftSavingsRepository(ref.watch(appDatabaseProvider));
  ref.onDispose(repository.dispose);
  return repository;
});
