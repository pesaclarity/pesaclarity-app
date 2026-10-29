import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../domain/reminders/recurring_charges.dart';
import '../../domain/subscriptions/subscriptions.dart';
import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Subscriptions the person tracks, and suggestions they marked as one-offs.
abstract interface class SubscriptionsRepository {
  /// Every saved subscription, tracked or dismissed, updating as they change.
  Stream<List<Subscription>> watchAll();

  /// Tracks a suggested [charge] as a monthly subscription.
  Future<int> track(RecurringCharge charge);

  /// Marks a suggested [charge] as a one-off, so it is not suggested again.
  Future<void> dismiss(RecurringCharge charge);

  Future<int> add({
    required String name,
    required int amountMinor,
    required RecurrenceFrequency frequency,
    required CalendarDate nextDate,
  });

  Future<void> update(Subscription subscription);

  /// Stops tracking. A suggested one comes back as a suggestion.
  Future<void> remove(int id);
}

class DriftSubscriptionsRepository implements SubscriptionsRepository {
  DriftSubscriptionsRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Subscription>> watchAll() =>
      (_db.select(_db.subscriptions)
            ..orderBy([(s) => OrderingTerm(expression: s.name)]))
          .watch()
          .map((rows) => [for (final r in rows) _fromRow(r)]);

  static Subscription _fromRow(SubscriptionRow r) => Subscription(
    id: r.id,
    name: r.name,
    payeeId: r.payeeId,
    amountMinor: r.amountMinor,
    currency: r.currency,
    frequency: r.frequency,
    nextDate: CalendarDate.local(r.nextDate),
    status: r.status,
  );

  Future<int> _fromCharge(RecurringCharge charge, SubscriptionStatus status) =>
      _db
          .into(_db.subscriptions)
          .insert(
            SubscriptionsCompanion.insert(
              name: charge.name,
              payeeId: Value(charge.payeeId),
              amountMinor: charge.amountMinor,
              currency: Value(charge.currency),
              frequency: RecurrenceFrequency.monthly,
              nextDate: charge.nextDate.startInstant,
              status: status,
            ),
          );

  @override
  Future<int> track(RecurringCharge charge) =>
      _fromCharge(charge, SubscriptionStatus.tracking);

  @override
  Future<void> dismiss(RecurringCharge charge) =>
      _fromCharge(charge, SubscriptionStatus.dismissed);

  @override
  Future<int> add({
    required String name,
    required int amountMinor,
    required RecurrenceFrequency frequency,
    required CalendarDate nextDate,
  }) => _db
      .into(_db.subscriptions)
      .insert(
        SubscriptionsCompanion.insert(
          name: name.trim(),
          amountMinor: amountMinor,
          currency: Value(BaseCurrency.code),
          frequency: frequency,
          nextDate: nextDate.startInstant,
          status: SubscriptionStatus.tracking,
        ),
      );

  @override
  Future<void> update(Subscription s) =>
      (_db.update(_db.subscriptions)..where((t) => t.id.equals(s.id))).write(
        SubscriptionsCompanion(
          name: Value(s.name.trim()),
          amountMinor: Value(s.amountMinor),
          frequency: Value(s.frequency),
          nextDate: Value(s.nextDate.startInstant),
          status: Value(s.status),
        ),
      );

  @override
  Future<void> remove(int id) =>
      (_db.delete(_db.subscriptions)..where((t) => t.id.equals(id))).go();
}

final subscriptionsRepositoryProvider = Provider<SubscriptionsRepository>(
  (ref) => DriftSubscriptionsRepository(ref.watch(appDatabaseProvider)),
);
