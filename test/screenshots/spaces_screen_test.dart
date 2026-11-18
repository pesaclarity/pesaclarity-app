// The Spaces screen for the marketing screenshots, with made-up spaces
// (README, Screenshots).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/features/spaces/presentation/manage_spaces_screens.dart';

import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';
import 'harness.dart';

void main() {
  screenshot('spaces', statusBar: false, (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(
      () => DriftAppSettingsRepository(db).writeJson(
        SpacesController.settingsKey,
        spacesToJson([
          Space.personal,
          const Space(
            id: 'shop1',
            name: 'Green Basket',
            kind: SpaceKind.business,
          ),
          const Space(id: 'home1', name: 'Home', kind: SpaceKind.household),
        ]),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...appLockOverrides(),
          appDatabaseProvider.overrideWithValue(db),
          personalDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 11, 9)),
        ],
        child: shotApp(const SpacesScreen()),
      ),
    );
    await settleFrames(tester);
    await snap(tester);
  });
}
