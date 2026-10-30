import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/reader/reading_template.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Message layouts the person asked to be read the same way next time.
abstract interface class ReaderTemplatesRepository {
  Future<List<ReadingTemplate>> forInstitution(String institutionId);

  Future<void> add(String institutionId, ReadingTemplate template);
}

class DriftReaderTemplatesRepository implements ReaderTemplatesRepository {
  DriftReaderTemplatesRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Future<List<ReadingTemplate>> forInstitution(String institutionId) async {
    final rows = await (_db.select(
      _db.readerTemplates,
    )..where((t) => t.institutionId.equals(institutionId))).get();
    return [for (final r in rows) ReadingTemplate.fromJson(r.template)];
  }

  @override
  Future<void> add(String institutionId, ReadingTemplate template) => _db
      .into(_db.readerTemplates)
      .insert(
        ReaderTemplatesCompanion.insert(
          institutionId: institutionId,
          template: template.toJson(),
          createdAt: _clock(),
        ),
      );
}

final readerTemplatesRepositoryProvider = Provider<ReaderTemplatesRepository>(
  (ref) => DriftReaderTemplatesRepository(ref.watch(appDatabaseProvider)),
);
