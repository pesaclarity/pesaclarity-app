import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/payees/payee_directory.dart';
import '../../domain/payees/payee_identifier.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Named payees and the raw identifiers that resolve to them.
///
/// A payee's display name, default category and leak type are read at query
/// time, so changing them reaches every past and future transaction linked
/// to it.
abstract interface class PayeesRepository {
  Stream<List<Payee>> watchAll();

  /// Names the party behind [identifier] as a new payee and links every
  /// transaction from that identifier to it. Returns the payee id.
  Future<int> name(
    PayeeIdentifier identifier, {
    required String displayName,
    int? defaultCategoryId,
    LeakType leakType = LeakType.none,
  });

  /// Adds [identifier] to [payeeId], moving it from any other payee, and
  /// relinks the transactions it reaches.
  Future<void> addIdentifier(int payeeId, PayeeIdentifier identifier);

  /// Changes a payee. Pass `Value(null)` as [defaultCategoryId] to clear it.
  Future<void> update(
    int payeeId, {
    String? displayName,
    Value<int?> defaultCategoryId = const Value.absent(),
    LeakType? leakType,
  });

  /// All payees with their identifiers, for resolving.
  Future<PayeeDirectory> directory();

  /// Named payees with their identifiers, category and transaction count,
  /// by name.
  Stream<List<PayeeSummary>> watchSummaries();

  /// Other parties that are not named yet, most money out first. Own
  /// transfers are left out.
  Stream<List<UnnamedParty>> watchUnnamed();
}

/// A named payee as the Payees list shows it.
class PayeeSummary {
  const PayeeSummary({
    required this.payee,
    required this.identifiers,
    required this.transactionCount,
    this.categoryName,
  });

  final Payee payee;
  final List<PayeeIdentifier> identifiers;
  final int transactionCount;

  /// The default category's name; null is Uncategorised.
  final String? categoryName;
}

/// A number, till or paybill that transactions reach but no payee names.
class UnnamedParty {
  const UnnamedParty({
    required this.identifier,
    required this.transactionCount,
    required this.outMinor,
    required this.inMinor,
    required this.lastAt,
    this.printedName,
  });

  final PayeeIdentifier identifier;

  /// The name the latest message printed, if any.
  final String? printedName;
  final int transactionCount;
  final int outMinor;
  final int inMinor;
  final DateTime lastAt;
}

class DriftPayeesRepository implements PayeesRepository {
  DriftPayeesRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Payee>> watchAll() => (_db.select(
    _db.payees,
  )..orderBy([(p) => OrderingTerm(expression: p.displayName)])).watch();

  @override
  Future<int> name(
    PayeeIdentifier identifier, {
    required String displayName,
    int? defaultCategoryId,
    LeakType leakType = LeakType.none,
  }) => _db.transaction(() async {
    final id = await _db
        .into(_db.payees)
        .insert(
          PayeesCompanion.insert(
            displayName: _cleanDisplayName(displayName),
            defaultCategoryId: Value(defaultCategoryId),
            leakType: Value(leakType),
          ),
        );
    await addIdentifier(id, identifier);
    return id;
  });

  @override
  Future<void> addIdentifier(int payeeId, PayeeIdentifier identifier) =>
      _db.transaction(() async {
        await _db
            .into(_db.payeeIdentifiers)
            .insert(
              PayeeIdentifiersCompanion.insert(
                payeeId: payeeId,
                kind: identifier.kind,
                value: identifier.value,
              ),
              onConflict: DoUpdate(
                (_) => PayeeIdentifiersCompanion(payeeId: Value(payeeId)),
                target: [_db.payeeIdentifiers.kind, _db.payeeIdentifiers.value],
              ),
            );
        await relinkTransactions(_db, identifier.kind);
      });

  @override
  Future<void> update(
    int payeeId, {
    String? displayName,
    Value<int?> defaultCategoryId = const Value.absent(),
    LeakType? leakType,
  }) => (_db.update(_db.payees)..where((p) => p.id.equals(payeeId))).write(
    PayeesCompanion(
      displayName: displayName == null
          ? const Value.absent()
          : Value(_cleanDisplayName(displayName)),
      defaultCategoryId: defaultCategoryId,
      leakType: Value.absentIfNull(leakType),
    ),
  );

  @override
  Future<PayeeDirectory> directory() => payeeDirectory(_db);

  @override
  Stream<List<PayeeSummary>> watchSummaries() {
    final p = _db.payees;
    final c = _db.categories;
    final t = _db.transactions;
    final count = t.id.count();
    final query =
        _db.select(p).join([
            leftOuterJoin(c, c.id.equalsExp(p.defaultCategoryId)),
            leftOuterJoin(t, t.payeeId.equalsExp(p.id)),
          ])
          ..addColumns([count])
          ..groupBy([p.id])
          ..orderBy([OrderingTerm.asc(p.displayName.collate(Collate.noCase))]);
    return query.watch().asyncMap((rows) async {
      final byPayee = <int, List<PayeeIdentifier>>{};
      for (final row in await _db.select(_db.payeeIdentifiers).get()) {
        (byPayee[row.payeeId] ??= []).add(
          PayeeIdentifier.stored(row.kind, row.value),
        );
      }
      return [
        for (final row in rows)
          PayeeSummary(
            payee: row.readTable(p),
            identifiers: byPayee[row.readTable(p).id] ?? const [],
            transactionCount: row.read(count)!,
            categoryName: row.readTableOrNull(c)?.name,
          ),
      ];
    });
  }

  @override
  Stream<List<UnnamedParty>> watchUnnamed() {
    final t = _db.transactions;
    final count = t.id.count();
    final out = t.amountMinor.sum(
      filter: t.direction.equalsValue(TransactionDirection.outflow),
    );
    final into = t.amountMinor.sum(
      filter: t.direction.equalsValue(TransactionDirection.inflow),
    );
    final last = t.occurredAt.max();
    final query = _db.selectOnly(t)
      ..addColumns([t.counterpartyKind, t.counterpartyValue, count, out, into])
      ..addColumns([last])
      ..where(
        t.payeeId.isNull() &
            t.transferPairId.isNull() &
            t.counterpartyKind.isNotNull() &
            t.counterpartyValue.isNotNull(),
      )
      ..groupBy([t.counterpartyKind, t.counterpartyValue]);
    return query.watch().asyncMap((rows) async {
      final parties = <UnnamedParty>[];
      for (final row in rows) {
        final kind = row.readWithConverter(t.counterpartyKind)!;
        final value = row.read(t.counterpartyValue)!;
        final latest =
            await (_db.select(t)
                  ..where(
                    (r) =>
                        r.counterpartyKind.equalsValue(kind) &
                        r.counterpartyValue.equals(value) &
                        r.counterpartyName.isNotNull(),
                  )
                  ..orderBy([(r) => OrderingTerm.desc(r.occurredAt)])
                  ..limit(1))
                .getSingleOrNull();
        parties.add(
          UnnamedParty(
            identifier: PayeeIdentifier.stored(kind, value),
            printedName: latest?.counterpartyName,
            transactionCount: row.read(count)!,
            outMinor: row.read(out) ?? 0,
            inMinor: row.read(into) ?? 0,
            lastAt: row.read(last)!,
          ),
        );
      }
      parties.sort((a, b) {
        final byOut = b.outMinor.compareTo(a.outMinor);
        return byOut != 0 ? byOut : b.lastAt.compareTo(a.lastAt);
      });
      return parties;
    });
  }
}

/// Loads every payee with its identifiers.
Future<PayeeDirectory> payeeDirectory(AppDatabase db) async {
  final identifiers = <int, List<PayeeIdentifier>>{};
  for (final row in await db.select(db.payeeIdentifiers).get()) {
    (identifiers[row.payeeId] ??= []).add(
      PayeeIdentifier.stored(row.kind, row.value),
    );
  }
  return PayeeDirectory([
    for (final p in await db.select(db.payees).get())
      PayeeRule(
        id: p.id,
        displayName: p.displayName,
        identifiers: identifiers[p.id] ?? const [],
        defaultCategoryId: p.defaultCategoryId,
        leakType: p.leakType,
      ),
  ]);
}

/// Points every transaction with a [kind] counterparty at the payee its
/// identifier resolves to now. Transactions without a counterparty keep the
/// payee they were given by hand.
Future<void> relinkTransactions(AppDatabase db, PayeeIdentifierKind kind) =>
    db.transaction(() async {
      final directory = await payeeDirectory(db);
      final t = db.transactions;
      final values =
          await (db.selectOnly(t, distinct: true)
                ..addColumns([t.counterpartyValue])
                ..where(
                  t.counterpartyKind.equalsValue(kind) &
                      t.counterpartyValue.isNotNull(),
                ))
              .map((row) => row.read(t.counterpartyValue)!)
              .get();
      for (final value in values) {
        final payee = directory.resolve(PayeeIdentifier.stored(kind, value));
        await (db.update(t)..where(
              (r) =>
                  r.counterpartyKind.equalsValue(kind) &
                  r.counterpartyValue.equals(value),
            ))
            .write(TransactionsCompanion(payeeId: Value(payee?.id)));
      }
    });

String _cleanDisplayName(String raw) {
  final name = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (name.isEmpty || name.length > 80) {
    throw ArgumentError.value(raw, 'displayName', 'must be 1 to 80 characters');
  }
  return name;
}

final payeesRepositoryProvider = Provider<PayeesRepository>(
  (ref) => DriftPayeesRepository(ref.watch(appDatabaseProvider)),
);
