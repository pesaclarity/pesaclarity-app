import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/time/week_start.dart';
import 'package:pesaclarity/src/features/settings/application/week_start_provider.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async {
    FirstWeekday.reset();
    await db.close();
  });

  ProviderContainer open() =>
      ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);

  test('the week starts on Monday until another day is chosen', () async {
    final container = open();
    addTearDown(container.dispose);
    expect(await container.read(weekStartControllerProvider.future), 1);
    expect(container.read(weekStartsOnProvider), DateTime.monday);
  });

  test('the chosen day is kept and used everywhere', () async {
    final first = open();
    await first.read(weekStartControllerProvider.future);
    await first
        .read(weekStartControllerProvider.notifier)
        .change(DateTime.sunday);
    expect(first.read(weekStartsOnProvider), DateTime.sunday);
    expect(FirstWeekday.current, DateTime.sunday);
    first.dispose();

    FirstWeekday.reset();
    final again = open();
    addTearDown(again.dispose);
    expect(
      await again.read(weekStartControllerProvider.future),
      DateTime.sunday,
    );
    expect(FirstWeekday.current, DateTime.sunday);
  });
}
