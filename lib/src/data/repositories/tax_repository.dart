import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../domain/books/books.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';
import 'quick_records_repository.dart';

/// Tax a client kept back from a payment.
class Withheld {
  const Withheld({
    required this.id,
    required this.person,
    required this.amountMinor,
    required this.currency,
    required this.at,
    this.certificate,
  });

  final int id;
  final String person;
  final int amountMinor;
  final String currency;
  final DateTime at;
  final String? certificate;
}

/// Withholding tax kept back by clients, with its certificates.
abstract interface class TaxRepository {
  /// [person] kept back [amountMinor] of what they owed and paid it to KRA;
  /// it comes off what they owe, oldest credit first.
  Future<int> withhold({
    required String person,
    required int amountMinor,
    required DateTime at,
    String? certificate,
  });

  /// Everything withheld, oldest first.
  Future<List<Withheld>> withheld();

  /// Saves the certificate number for withheld record [id].
  Future<void> setCertificate(int id, String? number);

  /// What the books post: tax paid, less what clients owe.
  Future<List<WithheldTax>> bookEntries();

  /// Marks cost [transactionId] as having an eTIMS invoice, or not.
  Future<void> setEtims(int transactionId, {required bool has});

  /// The costs with an eTIMS invoice.
  Future<Set<int>> etimsCosts();
}

class DriftTaxRepository implements TaxRepository {
  DriftTaxRepository(this._db);

  final AppDatabase _db;

  @override
  Future<int> withhold({
    required String person,
    required int amountMinor,
    required DateTime at,
    String? certificate,
  }) => _db.transaction(() async {
    final id = await _db
        .into(_db.withheldTaxes)
        .insert(
          WithheldTaxesCompanion.insert(
            person: person.trim(),
            amountMinor: amountMinor,
            currency: Value(BaseCurrency.code),
            at: at,
            certificate: Value(certificate),
          ),
        );
    await takeOffOwed(_db, person, amountMinor, at);
    return id;
  });

  @override
  Future<List<Withheld>> withheld() async => [
    for (final r in await (_db.select(
      _db.withheldTaxes,
    )..orderBy([(w) => OrderingTerm.asc(w.at)])).get())
      Withheld(
        id: r.id,
        person: r.person,
        amountMinor: r.amountMinor,
        currency: r.currency,
        at: r.at,
        certificate: r.certificate,
      ),
  ];

  @override
  Future<void> setCertificate(int id, String? number) async {
    final n = number?.trim();
    await (_db.update(_db.withheldTaxes)..where((w) => w.id.equals(id))).write(
      WithheldTaxesCompanion(
        certificate: Value(n == null || n.isEmpty ? null : n),
      ),
    );
  }

  @override
  Future<void> setEtims(int transactionId, {required bool has}) async {
    if (has) {
      await _db
          .into(_db.etimsCosts)
          .insertOnConflictUpdate(
            EtimsCostsCompanion.insert(transactionId: Value(transactionId)),
          );
    } else {
      await (_db.delete(
        _db.etimsCosts,
      )..where((e) => e.transactionId.equals(transactionId))).go();
    }
  }

  @override
  Future<Set<int>> etimsCosts() async => {
    for (final r in await _db.select(_db.etimsCosts).get()) r.transactionId,
  };

  @override
  Future<List<WithheldTax>> bookEntries() async => [
    for (final w in await withheld())
      WithheldTax(
        sourceId: w.id,
        at: w.at,
        amountMinor: w.amountMinor,
        currency: w.currency,
      ),
  ];
}

final taxRepositoryProvider = Provider<TaxRepository>(
  (ref) => DriftTaxRepository(ref.watch(appDatabaseProvider)),
);
