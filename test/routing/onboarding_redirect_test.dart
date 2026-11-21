import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/routing/app_router.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';

import '../helpers/spaces_harness.dart';
import '../helpers/test_app.dart';

const _welcome = 'Know what you can spend today.';

void main() {
  group('onboardingRedirect', () {
    const loading = AsyncLoading<bool>();
    const notDone = AsyncData(false);
    const done = AsyncData(true);

    test('asks which space after unlocking when set to ask', () {
      expect(
        onboardingRedirect(done, AppRoutes.launch, askSpace: true),
        AppRoutes.chooseSpace,
      );
      expect(onboardingRedirect(done, AppRoutes.launch), AppRoutes.home);
      expect(
        onboardingRedirect(done, AppRoutes.chooseSpace, askSpace: true),
        isNull,
      );
    });

    test('waits on the launch screen while loading', () {
      expect(onboardingRedirect(loading, AppRoutes.launch), isNull);
      expect(onboardingRedirect(loading, AppRoutes.home), AppRoutes.launch);
    });

    test('keeps people in onboarding until it is complete', () {
      expect(
        onboardingRedirect(notDone, AppRoutes.launch),
        AppRoutes.onboarding,
      );
      expect(onboardingRedirect(notDone, AppRoutes.plan), AppRoutes.onboarding);
      expect(onboardingRedirect(notDone, AppRoutes.onboardingAccounts), isNull);
    });

    test('skips onboarding once complete', () {
      expect(onboardingRedirect(done, AppRoutes.launch), AppRoutes.home);
      expect(onboardingRedirect(done, AppRoutes.onboarding), AppRoutes.home);
      expect(onboardingRedirect(done, AppRoutes.plan), isNull);
    });

    test('shows onboarding if the saved state cannot be read', () {
      final error = AsyncError<bool>(StateError('locked'), StackTrace.empty);
      expect(onboardingRedirect(error, AppRoutes.home), AppRoutes.onboarding);
    });
  });

  testAppWidgets('shows onboarding once, then opens on Home', (tester) async {
    final db = openTestDatabase();

    await pumpApp(tester, db: db);
    expect(find.text(_welcome), findsOneWidget);
    await finishOnboarding(tester);
    expect(find.text('Safe to spend today'), findsOneWidget);

    await pumpApp(tester, db: db);
    expect(find.text(_welcome), findsNothing);
    expect(find.text('Safe to spend today'), findsOneWidget);
  });

  testAppWidgets('opens in Personal when the space it was to open is not '
      'on the list', (tester) async {
    final db = openTestDatabase();
    await pumpApp(tester, db: db);
    await finishOnboarding(tester);

    // The next launch is told to open a space the list does not have.
    await pumpApp(
      tester,
      db: db,
      overrides: [
        personalDatabaseProvider.overrideWithValue(db),
        activeSpaceIdProvider.overrideWith(() => ActiveSpaceId('gone1')),
        activeSpaceStoreProvider.overrideWithValue(const NoActiveSpaceStore()),
      ],
    );

    expect(find.text('Safe to spend today'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.text('Safe to spend today')),
    );
    expect(container.read(activeSpaceIdProvider), personalSpaceId);
  });

  testAppWidgets('shows onboarding again if it was left unfinished', (
    tester,
  ) async {
    final db = openTestDatabase();

    await pumpApp(tester, db: db);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    await pumpApp(tester, db: db);
    expect(find.text(_welcome), findsOneWidget);
  });
}
