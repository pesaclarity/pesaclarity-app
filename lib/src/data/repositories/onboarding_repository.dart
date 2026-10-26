import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Remembers whether onboarding is done, so it shows only once.
abstract interface class OnboardingRepository {
  Future<bool> isComplete();

  Future<void> markComplete();
}

class DriftOnboardingRepository implements OnboardingRepository {
  DriftOnboardingRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const completedAtKey = 'onboarding.completed_at';

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Future<bool> isComplete() async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((t) => t.key.equals(completedAtKey))).getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> markComplete() => _db
      .into(_db.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          key: completedAtKey,
          value: _clock().toUtc().toIso8601String(),
        ),
        mode: InsertMode.insertOrIgnore,
      );
}

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => DriftOnboardingRepository(ref.watch(appDatabaseProvider)),
);
