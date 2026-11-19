import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/domain/categoriser/trainable.dart';
import 'package:pesaclarity/src/features/categoriser/data/tuned_weights_store.dart';

import '../../domain/categoriser/trainable_test.dart' show tinyNetwork;

void main() {
  late AppDatabase db;
  late SettingsTunedWeightsStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = SettingsTunedWeightsStore(DriftAppSettingsRepository(db));
  });
  tearDown(() => db.close());

  test('keeps tuned weights and the last run in the database', () async {
    expect(await store.read(), isNull);
    expect(await store.lastRun(), isNull);

    final weights = TunedWeights(
      weightsSha256: 'cd',
      trainedAt: DateTime.utc(2026, 11, 4, 9),
      exampleCount: 12,
      weights: tinyNetwork().shipped.toNamed(),
    );
    await store.write(weights);
    await store.markRun(DateTime.utc(2026, 11, 4, 9, 5));

    final back = (await store.read())!;
    expect(back.weightsSha256, 'cd');
    expect(back.weights['category.kernel'], weights.weights['category.kernel']);
    expect(await store.lastRun(), DateTime.utc(2026, 11, 4, 9, 5));
  });

  test('a record saved for the TFLite model reads as none', () async {
    await DriftAppSettingsRepository(db)
        .writeJson(SettingsTunedWeightsStore.weightsKey, {
          'trainable_sha256': 'cd',
          'trained_at_ms': 0,
          'examples': 12,
          'weights': {'w1': 'AAAAAA=='},
        });
    expect(await store.read(), isNull);
  });
}
