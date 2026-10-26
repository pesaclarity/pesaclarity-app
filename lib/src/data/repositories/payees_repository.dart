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
