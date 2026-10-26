import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Messages from selected senders that no parser rule understood.
abstract interface class ReviewInboxRepository {
  /// Items still waiting for review, oldest first.
  Stream<List<ReviewItem>> watchPending();

  /// Stores a message for review unless one with the same [messageHash] was
  /// stored before, even if since resolved. Returns whether it was added.
  Future<bool> addIfNew({
    required String institutionId,
    required String sender,
    required DateTime receivedAt,
    required String messageHash,
    required String body,
    required String reason,
  });

  /// Marks item [id] as dealt with and deletes its message text.
  Future<void> resolve(int id);
}

class DriftReviewInboxRepository implements ReviewInboxRepository {
  DriftReviewInboxRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Stream<List<ReviewItem>> watchPending() =>
      (_db.select(_db.reviewItems)
            ..where((r) => r.resolvedAt.isNull())
            ..orderBy([(r) => OrderingTerm.asc(r.receivedAt)]))
          .watch();

  @override
  Future<bool> addIfNew({
    required String institutionId,
    required String sender,
    required DateTime receivedAt,
    required String messageHash,
    required String body,
    required String reason,
  }) async {
    final row = await _db
        .into(_db.reviewItems)
        .insertReturningOrNull(
          ReviewItemsCompanion.insert(
            institutionId: institutionId,
            sender: sender,
            receivedAt: receivedAt,
            messageHash: messageHash,
            body: Value(body),
            reason: reason,
          ),
          onConflict: DoNothing(target: [_db.reviewItems.messageHash]),
        );
    return row != null;
  }

  @override
  Future<void> resolve(int id) =>
      (_db.update(_db.reviewItems)..where((r) => r.id.equals(id))).write(
        ReviewItemsCompanion(
          body: const Value(null),
          resolvedAt: Value(_clock()),
        ),
      );
}

final reviewInboxRepositoryProvider = Provider<ReviewInboxRepository>(
  (ref) => DriftReviewInboxRepository(ref.watch(appDatabaseProvider)),
);
