import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/exchange_rates.dart';
import '../../domain/categories/default_categories.dart';
import '../../domain/ledger/balances.dart';
import '../../domain/ledger/cross_currency_transfers.dart';
import '../../domain/ledger/ledger_entry.dart';
import '../../domain/ledger/own_transfers.dart';
import '../../domain/payees/payee_directory.dart';
import '../../domain/payees/payee_identifier.dart';
import '../../features/currency/application/currency_controller.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';
import 'message_links.dart';
import 'message_twins_store.dart';
import 'payees_repository.dart';
import 'savings_links.dart';

/// The ledger of transactions from SMS, statements and manual entry.
abstract interface class TransactionsRepository {
  /// Most recent first; only those tagged [tagId] when given.
  Stream<List<TransactionRecord>> watchRecent({int limit = 50, int? tagId});

  /// Stores [transaction]. Without a payee id, a counterparty (normalised
  /// with `PayeeIdentifier`) is resolved to its named payee, if any. One on
  /// a savings account the app keeps, or said to have moved to or from one,
  /// joins that account's entries (see `linkSavingsPayments`).
  Future<int> add(TransactionsCompanion transaction);

  /// Stores each of [transactions] whose account has no transaction with the
  /// same dedupe key yet, resolving payees like [add]. Returns how many were
  /// stored.
  ///
  /// A message about money already stored on the same account (see
  /// `twinMatch`: a bank's plain alert and its own confirmation of the same
  /// transfer, or two messages with the same reference) is merged into that
  /// transaction instead of stored again. A new transaction whose message
  /// names one of the person's other accounts as where it went counts as an
  /// own transfer, and a loan repayment is recorded against its debt. A
  /// payment into a savings account the app keeps, or money back from it,
  /// gets its entry there and counts as an own transfer (see
  /// `linkSavingsPayments`).
  Future<int> addNew(Iterable<TransactionsCompanion> transactions);

  /// Finds an existing transaction with the same receipt, for dedupe between
  /// SMS and later statement imports.
  Future<TransactionRecord?> findByReceipt(int accountId, String receiptNo);

  /// Transactions with time in `[from, to)` as ledger entries, oldest first,
  /// with their payee applied (see `applyPayee`) and their tags. Only those
  /// tagged [tagId] when given.
  ///
  /// Money out of a day-to-day account that the person, or its message,
  /// says went to one of their savings accounts (SACCO or money market) is
  /// filed under the seeded Savings category, unless they chose a category
  /// for it or its payee has one.
  Future<List<LedgerEntry>> ledgerEntries({
    required DateTime from,
    required DateTime to,
    int? tagId,
  });

  /// Stores own-transfer pairs so both halves point at each other.
  Future<void> saveTransferPairs(Iterable<TransferPair> pairs);

  /// Finds and stores own transfers (see `findOwnTransfers`, then
  /// `findCrossCurrencyTransfers` between currencies, at the rates kept
  /// with the space) among the transactions from [from] to [to], every one
  /// when not given, widened by the time a named transfer waits for its
  /// other side. A pair across currencies whose side the bank reversed is
  /// unmatched first. Returns how many pairs were made. [addNew] runs it after every new transaction, so
  /// message scans, new messages, statements and checked messages all pair.
  Future<int> pairOwnTransfers({DateTime? from, DateTime? to});

  /// Pairs [outflowId] and [inflowId] as one own transfer, as the person
  /// chose.
  Future<void> match(int outflowId, int inflowId);

  /// Undoes the own transfer [id] is half of, so both count as they were
  /// and pairing never matches them again. A payment into or out of a
  /// savings account the app keeps stays matched with its entry there.
  Future<void> unmatch(int id);

  /// Marks [id] as money moved to or from the person's own [accountId], or
  /// clears that with null, then pairs it if its other side is here. Naming
  /// a savings account the app keeps writes the other side there at once,
  /// since no message will bring it; an entry on such an account names no
  /// other account.
  Future<void> setTransferAccount(int id, int? accountId);

  /// Pairs the person unmatched.
  Future<Set<TransferPair>> declinedTransfers();

  /// Saves the rate the person got for transaction [id]: one [currency]
  /// bought [rate] of the transaction's currency. A null [rate] goes back to
  /// the rates of its day.
  Future<void> setRateGot(int id, {required String currency, double? rate});

  /// Emits whenever something behind the ledger changes: transactions, their
  /// tags, payees, categories, accounts or the plan.
  Stream<void> watchChanges();

  /// One transaction with its account, payee and category, updating as any
  /// of them change. Emits null once the transaction is gone.
  Stream<TransactionDetail?> watchDetail(int id);
}

/// A transaction as its detail sheet shows it.
class TransactionDetail {
  const TransactionDetail({
    required this.record,
    required this.account,
    this.payee,
    this.category,
    this.payeeCategory,
    this.isCategoryAuto = false,
    this.needsPurpose = false,
  });

  final TransactionRecord record;
  final Account account;
  final Payee? payee;

  /// The override, or else the payee's default, or auto-category; null is Uncategorised.
  final Category? category;

  /// The payee's default category, which applies without an override.
  final Category? payeeCategory;

  final bool isCategoryAuto;

  /// Money in from a payee whose money has meant different things, waiting
  /// for the person to say what it was.
  final bool needsPurpose;

  bool get isCategoryOverridden => record.categoryOverrideId != null;

  /// The other party's raw identifier, for naming the payee.
  PayeeIdentifier? get counterparty {
    final kind = record.counterpartyKind;
    final value = record.counterpartyValue;
    return kind == null || value == null
        ? null
        : PayeeIdentifier.stored(kind, value);
  }
}

class DriftTransactionsRepository implements TransactionsRepository {
  DriftTransactionsRepository(this._db, {this._converter});

  final AppDatabase _db;

  /// Converts ledger entries into the base currency; none leaves them as
  /// stored.
  final CurrencyConverter? _converter;

  @override
  Stream<List<TransactionRecord>> watchRecent({int limit = 50, int? tagId}) {
    final query = _db.select(_db.transactions)
      ..where((t) => tagId == null ? const Constant(true) : _hasTag(t, tagId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return query.watch();
  }

  @override
  Future<int> add(TransactionsCompanion transaction) async {
    final id = await _db
        .into(_db.transactions)
        .insert(_withPayee(transaction, await payeeDirectory(_db)));
    await linkSavingsPayments(_db, [id]);
    return id;
  }

  @override
  Future<int> addNew(Iterable<TransactionsCompanion> transactions) =>
      _db.transaction(() async {
        final directory = await payeeDirectory(_db);
        var added = 0;
        var merged = 0;
        DateTime? earliest;
        DateTime? latest;
        void touched(DateTime at) {
          if (earliest == null || at.isBefore(earliest!)) earliest = at;
          if (latest == null || at.isAfter(latest!)) latest = at;
        }

        final inserted = <int>[];
        // Stored transactions a second message changed.
        final changed = <int>[];
        for (final transaction in transactions) {
          final key = transaction.dedupeKey.present
              ? transaction.dedupeKey.value
              : null;
          if (key != null && await _hasDedupeKey(transaction, key)) {
            // The same receipt and minute from another message, such as
            // M-Pesa's own and KCB's confirmation of one payment: keep what
            // only the new one says, such as M-Pesa's balance and fee.
            final same = await _storedTwinByKey(transaction, key);
            if (same != null) {
              await mergeTwin(_db, same, transaction);
              changed.add(same.id);
            }
            continue;
          }
          final row = _withPayee(transaction, directory);
          // A second message about money already stored: one transaction.
          final twin = await findTwin(_db, row);
          if (twin != null) {
            await mergeTwin(_db, twin.record, row, match: twin.match);
            changed.add(twin.record.id);
            merged++;
            touched(twin.record.occurredAt);
            touched(row.occurredAt.value);
            continue;
          }
          // A card payment in another currency and the account's own debit.
          final card = await findCardTwin(_db, row, _converter);
          if (card != null) {
            await mergeCardTwin(_db, card, row);
            changed.add(card.id);
            merged++;
            touched(card.occurredAt);
            continue;
          }
          inserted.add(await _db.into(_db.transactions).insert(row));
          added++;
          touched(row.occurredAt.value);
        }
        if (inserted.isNotEmpty) {
          final accounts = await _db.select(_db.accounts).get();
          for (final id in inserted) {
            await markTransferToOwnAccount(_db, id, accounts: accounts);
            await linkLoanRepayment(_db, id);
          }
        }
        // Before pairing, so a payment into savings is never paired with
        // something unrelated first.
        if (inserted.isNotEmpty || changed.isNotEmpty) {
          await linkSavingsPayments(_db, [...inserted, ...changed]);
        }
        if (added > 0 || merged > 0) {
          await pairOwnTransfers(from: earliest, to: latest);
        }
        return added;
      });

  /// The stored message on [transaction]'s account with [key], when it is
  /// another message than [transaction]'s.
  Future<TransactionRecord?> _storedTwinByKey(
    TransactionsCompanion transaction,
    String key,
  ) async {
    final hash = transaction.messageHash.present
        ? transaction.messageHash.value
        : null;
    if (hash == null) return null;
    final row =
        await (_db.select(_db.transactions)
              ..where(
                (t) =>
                    t.accountId.equals(transaction.accountId.value) &
                    t.dedupeKey.equals(key) &
                    t.source.equalsValue(TransactionSource.sms),
              )
              ..limit(1))
            .getSingleOrNull();
    if (row == null || row.messageHash == null || row.messageHash == hash) {
      return null;
    }
    return row;
  }

  Future<bool> _hasDedupeKey(
    TransactionsCompanion transaction,
    String key,
  ) async =>
      await _wasMoved(transaction.accountId.value, key) ||
      await _isStored(transaction, key);

  /// Moved to another space: it lives there now.
  Future<bool> _wasMoved(int accountId, String key) async =>
      await (_db.select(_db.movedTransactions)..where(
            (m) => m.accountId.equals(accountId) & m.dedupeKey.equals(key),
          ))
          .getSingleOrNull() !=
      null;

  Future<bool> _isStored(TransactionsCompanion transaction, String key) =>
      (_db.selectOnly(_db.transactions)
            ..addColumns([_db.transactions.id])
            ..where(
              _db.transactions.accountId.equals(transaction.accountId.value) &
                  _db.transactions.dedupeKey.equals(key),
            )
            ..limit(1))
          .getSingleOrNull()
          .then((row) => row != null);

  TransactionsCompanion _withPayee(
    TransactionsCompanion transaction,
    PayeeDirectory directory,
  ) {
    final kind = transaction.counterpartyKind.present
        ? transaction.counterpartyKind.value
        : null;
    final value = transaction.counterpartyValue.present
        ? transaction.counterpartyValue.value
        : null;
    if (transaction.payeeId.present || kind == null || value == null) {
      return transaction;
    }
    final payee = directory.resolve(PayeeIdentifier.stored(kind, value));
    return transaction.copyWith(payeeId: Value(payee?.id));
  }

  Expression<bool> _hasTag($TransactionsTable t, int tagId) => existsQuery(
    _db.select(_db.transactionTags)
      ..where((l) => l.transactionId.equalsExp(t.id) & l.tagId.equals(tagId)),
  );

  @override
  Future<TransactionRecord?> findByReceipt(int accountId, String receiptNo) {
    final query = _db.select(_db.transactions)
      ..where(
        (t) => t.accountId.equals(accountId) & t.receiptNo.equals(receiptNo),
      )
      ..limit(1);
    return query.getSingleOrNull();
  }

  /// See [TransactionsRepository.ledgerEntries]; with [accountIds], only
  /// those accounts' transactions, and with [ids], only those transactions.
  ///
  /// Read column by column from one query rather than through drift's typed
  /// join, which maps every column of both tables through a map per row:
  /// with years of messages that mapping was most of the time Home, Insights
  /// and the journal spent reading the ledger, all of it on the UI isolate.
  @override
  Future<List<LedgerEntry>> ledgerEntries({
    required DateTime from,
    required DateTime to,
    int? tagId,
    Set<int>? accountIds,
    Set<int>? ids,
  }) async {
    final categories = {
      for (final c in await _db.select(_db.categories).get()) c.id: c,
    };
    final savings = await _intoSavings(categories.values);
    final accounts = accountIds?.toList();
    final only = ids?.toList();
    String any(List<int> list) => List.filled(list.length, '?').join(', ');
    final inRange = [
      't.occurred_at >= ? AND t.occurred_at < ?',
      if (accounts != null) 't.account_id IN (${any(accounts)})',
      if (only != null) 't.id IN (${any(only)})',
    ].join(' AND ');
    final rangeVariables = <Variable<Object>>[
      Variable<DateTime>(from),
      Variable<DateTime>(to),
      for (final id in accounts ?? const <int>[]) Variable<int>(id),
      for (final id in only ?? const <int>[]) Variable<int>(id),
    ];

    final tags = <int, Set<int>>{};
    for (final row
        in await _db
            .customSelect(
              'SELECT l.transaction_id, l.tag_id FROM transaction_tags l '
              'INNER JOIN transactions t ON t.id = l.transaction_id '
              'WHERE $inRange',
              variables: rangeVariables,
              readsFrom: {_db.transactionTags, _db.transactions},
            )
            .get()) {
      (tags[row.data['transaction_id']! as int] ??= {}).add(
        row.data['tag_id']! as int,
      );
    }

    final rows = await _db
        .customSelect(
          'SELECT t.*, p.id AS payee_row_id, p.display_name AS payee_name, '
          'p.default_category_id AS payee_category_id, '
          'p.leak_type AS payee_leak_type, p.ask_purpose AS payee_ask_purpose '
          'FROM transactions t LEFT OUTER JOIN payees p ON p.id = t.payee_id '
          'WHERE $inRange'
          '${tagId == null ? '' : ' AND EXISTS (SELECT 1 FROM transaction_tags l '
                    'WHERE l.transaction_id = t.id AND l.tag_id = ?)'} '
          'ORDER BY t.occurred_at ASC, t.id ASC',
          variables: [...rangeVariables, if (tagId != null) Variable(tagId)],
          readsFrom: {_db.transactions, _db.payees, _db.transactionTags},
        )
        .get();
    final read = _RowReader(_db);
    final records = <int, TransactionRecord>{};
    final entries = [
      for (final row in rows)
        _toLedgerEntry(
          records[row.data['id']! as int] = read.transaction(row.data),
          read.payee(row.data),
          categories,
          tags,
          _converter,
          savings: savings,
        ),
    ];
    return _withExchangeCosts(entries, records, categories);
  }

  /// [entries] with what each own transfer across currencies cost to
  /// exchange on its money in (see [exchangeCostOf]), when both sides are
  /// read in the base currency at real rates of their days. [records] are
  /// the entries' rows, by id.
  Future<List<LedgerEntry>> _withExchangeCosts(
    List<LedgerEntry> entries,
    Map<int, TransactionRecord> records,
    Map<int, Category> categories,
  ) async {
    final converter = _converter;
    if (converter == null) return entries;
    final byId = {for (final e in entries) e.id: e};
    final ins = [
      for (final e in entries)
        if (e.isInflow &&
            e.transferPairId != null &&
            e.currency == converter.base)
          e,
    ];
    if (ins.isEmpty) return entries;
    // Money out on another day or account than was read.
    final away = [
      for (final e in ins)
        if (!byId.containsKey(e.transferPairId)) e.transferPairId!,
    ];
    final partners = <int, (LedgerEntry, TransactionRecord)>{};
    for (var i = 0; i < away.length; i += 500) {
      final ids = away.sublist(i, min(i + 500, away.length));
      for (final r in await (_db.select(
        _db.transactions,
      )..where((t) => t.id.isIn(ids))).get()) {
        partners[r.id] = (
          _toLedgerEntry(r, null, categories, const {}, converter),
          r,
        );
      }
    }
    bool real(TransactionRecord record) {
      if (record.currency == converter.base) return true;
      final kind = convertRecord(record, converter)?.kind;
      return kind != null &&
          kind != RateKind.approximate &&
          kind != RateKind.latest;
    }

    final costs = <int, int>{};
    for (final into in ins) {
      final id = into.transferPairId!;
      final (out, outRecord) = switch (byId[id]) {
        final e? => (e, records[id]!),
        null => partners[id] ?? (null, null),
      };
      if (out == null || outRecord == null) continue;
      final cost = exchangeCostOf(out, into);
      if (cost == null || !real(outRecord) || !real(records[into.id]!)) {
        continue;
      }
      costs[into.id] = cost;
    }
    if (costs.isEmpty) return entries;
    return [
      for (final e in entries)
        if (costs[e.id] case final cost?)
          e.copyWith(exchangeCostMinor: cost)
        else
          e,
    ];
  }

  /// The person's savings accounts and the seeded Savings category, which
  /// money moved into them is filed under. Null when that category is gone
  /// or there is no savings account.
  Future<_IntoSavings?> _intoSavings(Iterable<Category> categories) async {
    final category = categories
        .where((c) => c.key == savingsCategoryKey)
        .firstOrNull;
    if (category == null) return null;
    final a = _db.accounts;
    final accounts =
        await (_db.selectOnly(a)
              ..addColumns([a.id])
              ..where(a.type.isInValues(savingsAccountTypes)))
            .map((row) => row.read(a.id)!)
            .get();
    return accounts.isEmpty
        ? null
        : _IntoSavings(accounts.toSet(), category.id);
  }

  @override
  Future<void> setRateGot(int id, {required String currency, double? rate}) =>
      (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          fxRateCurrency: Value(rate == null || rate <= 0 ? null : currency),
          fxRateMicros: Value(
            rate == null || rate <= 0 ? null : (rate * 1e6).round(),
          ),
        ),
      );

  @override
  Future<void> saveTransferPairs(Iterable<TransferPair> pairs) =>
      _db.transaction(() async {
        for (final pair in pairs) {
          await _setPair(pair.outflowId, pair.inflowId);
          await _setPair(pair.inflowId, pair.outflowId);
        }
      });

  @override
  Future<int> pairOwnTransfers({DateTime? from, DateTime? to}) =>
      _db.transaction(() async {
        final t = _db.transactions;
        final query = _db.select(t);
        if (from != null) {
          query.where(
            (t) => t.occurredAt.isBiggerOrEqualValue(
              from.subtract(waitingTransferWindow),
            ),
          );
        }
        if (to != null) {
          query.where(
            (t) => t.occurredAt.isSmallerOrEqualValue(
              to.add(waitingTransferWindow),
            ),
          );
        }
        final categories = {
          for (final c in await _db.select(_db.categories).get()) c.id: c,
        };
        final payees = {
          for (final p in await _db.select(_db.payees).get()) p.id: p,
        };
        // Amounts as stored, each in the currency it moved in.
        Future<List<LedgerEntry>> read() async => [
          for (final r in await query.get())
            _toLedgerEntry(r, payees[r.payeeId], categories, const {}, null),
        ];
        var entries = await read();
        if (await _unmatchReversed(entries)) entries = await read();
        final accounts = await _db.select(_db.accounts).get();
        final declined = await declinedTransfers();
        final pairs = findOwnTransfers(
          entries,
          declined: declined,
          references: {for (final a in accounts) a.id: a.reference},
        );
        // Then between currencies, among what one currency left unpaired, at
        // the rates the app converts with.
        final across = findCrossCurrencyTransfers(
          applyTransferPairs(entries, pairs),
          accounts: {
            for (final a in accounts)
              a.id: TransferAccount(
                currency: a.currency,
                reference: a.reference,
                institutionId: a.institutionId,
              ),
          },
          // The rates kept with the space, not [_converter]: pairing then
          // does not depend on whether the app had read them yet.
          rateOn: dayRatesOf(await CurrencyController.storedConverter(_db)),
          declined: declined,
        );
        final all = [...pairs, for (final t in across) t.pair];
        await saveTransferPairs(all);
        return all.length;
      });

  /// Unmatches each own transfer across currencies in [entries] whose side
  /// the bank undid (see [reversedEntries]): nothing is left to arrive in
  /// the other currency, so both count as they were and the reversal
  /// cancels its side. The pair is never matched again. Returns whether
  /// any was unmatched.
  Future<bool> _unmatchReversed(List<LedgerEntry> entries) async {
    final reversed = reversedEntries(entries);
    if (reversed.isEmpty) return false;
    final byId = {for (final e in entries) e.id: e};
    final undone = <int>{};
    for (final id in reversed) {
      final entry = byId[id]!;
      final partner = byId[entry.transferPairId];
      if (partner == null || undone.contains(partner.id)) continue;
      final (out, into) = entry.isOutflow ? (entry, partner) : (partner, entry);
      if (!isCrossCurrencyPair(out, into)) continue;
      await unmatch(entry.id);
      undone.addAll([entry.id, partner.id]);
    }
    return undone.isNotEmpty;
  }

  @override
  Future<void> match(int outflowId, int inflowId) => _db.transaction(() async {
    await (_db.delete(_db.declinedTransfers)..where(
          (d) => d.outflowId.equals(outflowId) & d.inflowId.equals(inflowId),
        ))
        .go();
    await saveTransferPairs([TransferPair(outflowId, inflowId)]);
  });

  @override
  Future<void> unmatch(int id) => _db.transaction(() async {
    if (await isSavingsLinked(_db, id)) return;
    final row = await (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    final partnerId = row?.transferPairId;
    if (row == null || partnerId == null) return;
    final out = row.direction == TransactionDirection.outflow;
    await _db
        .into(_db.declinedTransfers)
        .insertOnConflictUpdate(
          DeclinedTransfersCompanion.insert(
            outflowId: out ? id : partnerId,
            inflowId: out ? partnerId : id,
          ),
        );
    await (_db.update(
      _db.transactions,
    )..where((t) => t.id.isIn([id, partnerId]))).write(
      const TransactionsCompanion(
        transferPairId: Value(null),
        transferAccountId: Value(null),
      ),
    );
  });

  @override
  Future<void> setTransferAccount(int id, int? accountId) async {
    if (await isSavingsEntry(_db, id)) return;
    final row =
        await (_db.update(
          _db.transactions,
        )..where((t) => t.id.equals(id))).writeReturning(
          TransactionsCompanion(transferAccountId: Value(accountId)),
        );
    if (row.isEmpty) return;
    // A savings account the app keeps gets, or loses, its side at once.
    await linkSavingsPayments(_db, [id]);
    if (accountId == null) return;
    final at = row.single.occurredAt;
    await pairOwnTransfers(from: at, to: at);
  }

  @override
  Future<Set<TransferPair>> declinedTransfers() async => {
    for (final d in await _db.select(_db.declinedTransfers).get())
      TransferPair(d.outflowId, d.inflowId),
  };

  @override
  Stream<TransactionDetail?> watchDetail(int id) {
    final t = _db.transactions;
    final query = _db.select(t).join([
      innerJoin(_db.accounts, _db.accounts.id.equalsExp(t.accountId)),
      leftOuterJoin(_db.payees, _db.payees.id.equalsExp(t.payeeId)),
    ])..where(t.id.equals(id));
    return query.watchSingleOrNull().asyncMap((row) async {
      if (row == null) return null;
      final record = row.readTable(t);
      final payee = row.readTableOrNull(_db.payees);
      Future<Category?> category(int? id) => id == null
          ? Future.value()
          : (_db.select(
              _db.categories,
            )..where((c) => c.id.equals(id))).getSingleOrNull();
      final payeeCategory = await category(payee?.defaultCategoryId);
      final isOverridden = record.categoryOverrideId != null;
      final needsPurpose =
          !isOverridden &&
          (payee?.askPurpose ?? false) &&
          record.direction == TransactionDirection.inflow;
      final autoCategory =
          (!isOverridden && !needsPurpose && payeeCategory == null)
          ? await category(record.autoCategoryId)
          : null;
      return TransactionDetail(
        record: record,
        account: row.readTable(_db.accounts),
        payee: payee,
        payeeCategory: payeeCategory,
        category: isOverridden
            ? await category(record.categoryOverrideId)
            : needsPurpose
            ? null
            : (payeeCategory ?? autoCategory),
        isCategoryAuto:
            !isOverridden && payeeCategory == null && autoCategory != null,
        needsPurpose: needsPurpose,
      );
    });
  }

  @override
  Stream<void> watchChanges() => ledgerTableUpdates(_db);

  Future<void> _setPair(int id, int partnerId) =>
      (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(transferPairId: Value(partnerId)),
      );
}

/// Builds rows read with plain SQL into drift's data classes, as drift's own
/// mapping would, without its per-column map lookups.
class _RowReader {
  _RowReader(AppDatabase db) : _types = db.typeMapping;

  final SqlTypes _types;
  final _directions = <String, TransactionDirection>{};
  final _kinds = <String, TransactionKind>{};
  final _counterparties = <String, PayeeIdentifierKind>{};
  final _sources = <String, TransactionSource>{};
  final _suggestions = <String, SuggestionSource>{};
  final _leaks = <String, LeakType>{};

  DateTime? _date(Object? value) => _types.read(DriftSqlType.dateTime, value);

  static T? _enum<T extends Enum>(
    Map<String, T> seen,
    Object? name,
    T Function(String) parse,
  ) => name == null ? null : seen[name as String] ??= parse(name);

  TransactionRecord transaction(Map<String, Object?> d) {
    return TransactionRecord(
      id: d['id']! as int,
      accountId: d['account_id']! as int,
      occurredAt: _date(d['occurred_at'])!,
      amountMinor: d['amount_minor']! as int,
      direction: _enum(
        _directions,
        d['direction'],
        $TransactionsTable.$converterdirection.fromSql,
      )!,
      kind: _enum(_kinds, d['kind'], $TransactionsTable.$converterkind.fromSql),
      feeMinor: d['fee_minor']! as int,
      currency: d['currency']! as String,
      fxRateMicros: d['fx_rate_micros'] as int?,
      fxRateCurrency: d['fx_rate_currency'] as String?,
      payeeId: d['payee_id'] as int?,
      counterpartyKind: _enum(
        _counterparties,
        d['counterparty_kind'],
        $TransactionsTable.$convertercounterpartyKind.fromSql,
      ),
      counterpartyValue: d['counterparty_value'] as String?,
      counterpartyName: d['counterparty_name'] as String?,
      item: d['item'] as String?,
      categoryOverrideId: d['category_override_id'] as int?,
      goalId: d['goal_id'] as int?,
      debtId: d['debt_id'] as int?,
      receiptNo: d['receipt_no'] as String?,
      source: _enum(
        _sources,
        d['source'],
        $TransactionsTable.$convertersource.fromSql,
      )!,
      messageHash: d['message_hash'] as String?,
      dedupeKey: d['dedupe_key'] as String?,
      balanceAfterMinor: d['balance_after_minor'] as int?,
      claimedBalanceMinor: d['claimed_balance_minor'] as int?,
      owedAfterMinor: d['owed_after_minor'] as int?,
      owedDueAt: _date(d['owed_due_at']),
      transferPairId: d['transfer_pair_id'] as int?,
      transferAccountId: d['transfer_account_id'] as int?,
      autoCategoryId: d['auto_category_id'] as int?,
      autoCategorySource: _enum(
        _suggestions,
        d['auto_category_source'],
        $TransactionsTable.$converterautoCategorySource.fromSql,
      ),
      autoCategoryConfidence: _types.read(
        DriftSqlType.double,
        d['auto_category_confidence'],
      ),
      readBy: d['read_by'] as String?,
    );
  }

  /// The payee joined in as `payee_*` columns, or null without one.
  Payee? payee(Map<String, Object?> d) {
    final id = d['payee_row_id'] as int?;
    if (id == null) return null;
    return Payee(
      id: id,
      displayName: d['payee_name']! as String,
      defaultCategoryId: d['payee_category_id'] as int?,
      leakType: _enum(
        _leaks,
        d['payee_leak_type'],
        $PayeesTable.$converterleakType.fromSql,
      )!,
      askPurpose: _types.read(DriftSqlType.bool, d['payee_ask_purpose'])!,
    );
  }
}

/// [record] in the base currency: at the rate the person got for it, when
/// they set one, else at the rates of its day. Null with no rate.
Converted? convertRecord(
  TransactionRecord record,
  CurrencyConverter converter,
) => converter.convert(
  record.amountMinor,
  record.currency,
  record.occurredAt,
  gotCurrency: record.fxRateCurrency,
  gotRate: record.fxRateMicros == null ? null : record.fxRateMicros! / 1e6,
);

/// The person's savings accounts, and the category money moved into them is
/// filed under.
class _IntoSavings {
  const _IntoSavings(this.accountIds, this.categoryId);

  final Set<int> accountIds;
  final int categoryId;

  /// Whether [record] moved money from a day-to-day account into savings.
  bool takes(TransactionRecord record) =>
      record.direction == TransactionDirection.outflow &&
      accountIds.contains(record.transferAccountId) &&
      !accountIds.contains(record.accountId);
}

LedgerEntry _toLedgerEntry(
  TransactionRecord record,
  Payee? payee,
  Map<int, Category> categories,
  Map<int, Set<int>> tags,
  CurrencyConverter? converter, {
  _IntoSavings? savings,
}) {
  // Amounts in another currency are converted into the base one, at the
  // rate the person got or else the rates of their day; with no rate they
  // keep their own currency, so totals in the base leave them out.
  final conversion = converter == null || record.currency == converter.base
      ? null
      : convertRecord(record, converter);
  final converted = conversion != null;
  int? inBase(int? minor) => minor == null || !converted
      ? minor
      : convertMinor(
          minor,
          from: record.currency,
          to: converter!.base,
          rate: 1 / conversion.baseBuys,
        );
  final applied = applyPayee(
    payee == null
        ? null
        : PayeeRule(
            id: payee.id,
            displayName: payee.displayName,
            defaultCategoryId: payee.defaultCategoryId,
            leakType: payee.leakType,
            askPurpose: payee.askPurpose,
          ),
    categoryOverrideId: record.categoryOverrideId,
    autoCategoryId: record.autoCategoryId,
    isInflow: record.direction == TransactionDirection.inflow,
  );
  // Money moved into savings is saved, whatever was suggested for it: only
  // the person's own choice or the payee's category says otherwise.
  final saved =
      savings != null &&
      savings.takes(record) &&
      (applied.categoryId == null || applied.isCategoryAuto);
  final categoryId = saved ? savings.categoryId : applied.categoryId;
  final category = categoryId == null ? null : categories[categoryId];
  return LedgerEntry(
    id: record.id,
    accountId: record.accountId,
    occurredAt: record.occurredAt,
    amountMinor: converted ? conversion.baseMinor : record.amountMinor,
    direction: record.direction,
    kind: record.kind ?? TransactionKind.bank,
    currency: converted ? converter!.base : record.currency,
    feeMinor: inBase(record.feeMinor)!,
    payeeId: record.payeeId,
    categoryId: categoryId,
    categoryType: category?.type,
    isDailySpending: category?.isDailySpending ?? false,
    categoryIsAuto: !saved && applied.isCategoryAuto,
    needsPurpose: applied.needsPurpose,
    transferPairId: record.transferPairId,
    transferAccountId: record.transferAccountId,
    source: record.source,
    payeeName: applied.displayName,
    leakType: applied.leakType,
    tagIds: tags[record.id] ?? const {},
    counterpartyName: record.counterpartyName,
    counterpartyKind: record.counterpartyKind,
    counterpartyValue: record.counterpartyValue,
    note: record.item,
    balanceAfterMinor: inBase(record.balanceAfterMinor),
    claimedBalanceMinor: inBase(record.claimedBalanceMinor),
    owedAfterMinor: inBase(record.owedAfterMinor),
    owedDueAt: record.owedDueAt,
    originalAmountMinor: converted ? record.amountMinor : null,
    originalCurrency: converted ? record.currency : null,
  );
}

final transactionsRepositoryProvider = Provider<TransactionsRepository>(
  (ref) => DriftTransactionsRepository(
    ref.watch(appDatabaseProvider),
    converter: ref.watch(currencyConverterProvider),
  ),
);

/// Every change to the ledger's tables in [db], as `watchChanges` reports
/// them.
Stream<void> ledgerTableUpdates(AppDatabase db) => db.tableUpdates(
  TableUpdateQuery.onAllTables([
    db.transactions,
    db.transactionTags,
    db.declinedTransfers,
    db.payees,
    db.payeeIdentifiers,
    db.categories,
    db.accounts,
    db.recurring,
    db.budgetItems,
    db.sales,
    db.salePayments,
    db.lentLoans,
    db.loanPayments,
    db.quickRecords,
    db.debts,
    db.debtInstalments,
    db.items,
    db.stockMoves,
    db.itemMeasures,
    db.saleLines,
    db.tabs,
    db.tabLines,
    db.withheldTaxes,
    db.hourEntries,
    db.invoices,
    db.invoiceLines,
    db.etimsCosts,
    db.savingsPockets,
    db.savingsEntries,
    db.savingsReadings,
  ]),
);

/// Counts changes to the ledger, so providers that read it with one-off
/// queries can watch this and recompute.
final ledgerChangesProvider = StreamProvider<int>((ref) async* {
  var count = 0;
  await for (final _
      in ref.watch(transactionsRepositoryProvider).watchChanges()) {
    yield ++count;
  }
});
