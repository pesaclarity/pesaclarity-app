import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';
import '../database/space_databases.dart';

/// Which institutions the person has switched on in My accounts.
abstract interface class InstitutionsRepository {
  /// Ids of the selected institutions, updated on every change.
  Stream<Set<String>> watchSelectedIds();

  Future<Set<String>> selectedIds();

  Future<void> setSelected(String institutionId, {required bool selected});
}

class DriftInstitutionsRepository implements InstitutionsRepository {
  DriftInstitutionsRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Stream<Set<String>> watchSelectedIds() => _db
      .select(_db.selectedInstitutions)
      .watch()
      .map((rows) => {for (final row in rows) row.institutionId});

  @override
  Future<Set<String>> selectedIds() async {
    final rows = await _db.select(_db.selectedInstitutions).get();
    return {for (final row in rows) row.institutionId};
  }

  @override
  Future<void> setSelected(
    String institutionId, {
    required bool selected,
  }) async {
    if (selected) {
      await _db
          .into(_db.selectedInstitutions)
          .insert(
            SelectedInstitutionsCompanion.insert(
              institutionId: institutionId,
              selectedAt: _clock(),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    } else {
      await (_db.delete(
        _db.selectedInstitutions,
      )..where((t) => t.institutionId.equals(institutionId))).go();
    }
  }
}

/// The open space's accounts, each read in one space only: switching on
/// an account another space reads leaves it off here, so no message is
/// ever read into two spaces. The screens ask first ([SpaceDatabases.readerOf])
/// and lead to Business or personal, where an account is shared properly.
class OneReaderInstitutionsRepository implements InstitutionsRepository {
  OneReaderInstitutionsRepository(this._here, this._readerOf);

  final InstitutionsRepository _here;

  /// The other space that reads an account, if any.
  final Future<Object?> Function(String institutionId) _readerOf;

  @override
  Stream<Set<String>> watchSelectedIds() => _here.watchSelectedIds();

  @override
  Future<Set<String>> selectedIds() => _here.selectedIds();

  @override
  Future<void> setSelected(
    String institutionId, {
    required bool selected,
  }) async {
    if (selected && await _readerOf(institutionId) != null) return;
    await _here.setSelected(institutionId, selected: selected);
  }
}

final institutionsRepositoryProvider = Provider<InstitutionsRepository>(
  (ref) => OneReaderInstitutionsRepository(
    DriftInstitutionsRepository(ref.watch(appDatabaseProvider)),
    ref.watch(spaceDatabasesProvider).readerOf,
  ),
);
