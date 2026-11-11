import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/space_move_repository.dart';
import 'package:pesaclarity/src/domain/categoriser/rule_categoriser.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/activity/presentation/activity_screen.dart';
import 'package:pesaclarity/src/features/categoriser/application/categoriser_providers.dart';
import 'package:pesaclarity/src/features/categoriser/data/model_store.dart';
import 'package:pesaclarity/src/features/spaces/application/space_manager.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/features/spaces/data/space_files.dart';
import 'package:pesaclarity/src/features/spaces/presentation/manage_spaces_screens.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../helpers/fake_app_lock.dart';
import '../../helpers/test_app.dart';

class _Files implements SpaceFiles {
  final deleted = <String>[];
  var erased = false;

  @override
  Future<void> deleteDatabase(String spaceId) async => deleted.add(spaceId);

  @override
  Future<void> eraseEverything() async => erased = true;

  @override
  Future<Directory> keptDirectory() async =>
      Directory.systemTemp.createTemp('kept');
}

class _Restarter implements AppRestarter {
  var restarted = false;

  @override
  Future<void> restart() async => restarted = true;
}

const _shop = Space(
  id: 'shop1',
  name: 'Green Basket',
  kind: SpaceKind.household,
);

Future<void> _seed(AppDatabase db) async {
  await DriftAppSettingsRepository(db).writeJson(
    SpacesController.settingsKey,
    spacesToJson([Space.personal, _shop]),
  );
  final account = await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingDate: DateTime.utc(2026),
        ),
      );
  await db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: account,
          occurredAt: DateTime.utc(2026, 11),
          amountMinor: 10000,
          direction: TransactionDirection.outflow,
          source: TransactionSource.manual,
        ),
      );
}

List<Override> _overrides(
  AppDatabase db,
  _Files files, {
  String active = personalSpaceId,
  _Restarter? restarter,
}) => [
  ...appLockOverrides(),
  appDatabaseProvider.overrideWithValue(db),
  personalDatabaseProvider.overrideWithValue(db),
  activeSpaceIdProvider.overrideWith(() => ActiveSpaceId(active)),
  activeSpaceStoreProvider.overrideWithValue(const _NoStore()),
  clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 11, 9)),
  spaceFilesProvider.overrideWithValue(files),
  if (restarter != null) appRestarterProvider.overrideWithValue(restarter),
];

class _NoStore implements ActiveSpaceStore {
  const _NoStore();

  @override
  Future<void> write(String spaceId) async {}

  @override
  Future<void> writeOpenChoice(String choice) async {}
}

Future<void> _show(
  WidgetTester tester,
  List<Override> overrides,
  Widget home,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: AppTheme.light, home: home),
    ),
  );
  await settleFrames(tester);
}

void main() {
  testAppWidgets('clearing keeps the space, its accounts and settings', (
    tester,
  ) async {
    final db = openTestDatabase();
    final container = ProviderContainer(overrides: _overrides(db, _Files()));
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await _seed(db);
      final before = await db.select(db.categories).get();
      await container
          .read(spaceManagerProvider)
          .clear(Space.personal, keep: false);
      expect(await db.select(db.transactions).get(), isEmpty);
      expect(await db.select(db.accounts).get(), hasLength(1));
      expect(await db.select(db.categories).get(), hasLength(before.length));
      expect(await container.read(spacesProvider.future), hasLength(2));
    });
  });

  testAppWidgets('clearing a date range keeps what is outside it', (
    tester,
  ) async {
    final db = openTestDatabase();
    final container = ProviderContainer(overrides: _overrides(db, _Files()));
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await _seed(db);
      final account = (await db.select(db.accounts).get()).first.id;
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: account,
              occurredAt: DateTime.utc(2026, 10, 5),
              amountMinor: 5000,
              direction: TransactionDirection.outflow,
              source: TransactionSource.manual,
            ),
          );
      await container
          .read(spaceManagerProvider)
          .clear(
            Space.personal,
            keep: false,
            from: DateTime.utc(2026, 11),
            to: DateTime.utc(2026, 12),
          );
      final left = await db.select(db.transactions).get();
      expect(left.single.occurredAt.toUtc(), DateTime.utc(2026, 10, 5));
    });
  });

  testAppWidgets('deleting a space removes only that space', (tester) async {
    final db = openTestDatabase();
    final files = _Files();
    final container = ProviderContainer(overrides: _overrides(db, files));
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await _seed(db);
      await container.read(spaceManagerProvider).delete(_shop, keep: false);
      expect(files.deleted, ['shop1']);
      expect(await container.read(spacesProvider.future), [
        isA<Space>().having((s) => s.id, 'id', personalSpaceId),
      ]);
      // Personal's own records are untouched.
      expect(await db.select(db.transactions).get(), hasLength(1));
      expect(
        () => container
            .read(spaceManagerProvider)
            .delete(Space.personal, keep: false),
        throwsArgumentError,
      );
    });
  });

  testAppWidgets('Spaces lists each space, kept apart', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => _seed(db));
    await _show(tester, _overrides(db, _Files()), const SpacesScreen());
    expect(
      find.text(
        'Each space keeps its own records, locked on this phone. Nothing is '
        'shared between them.',
      ),
      findsOneWidget,
    );
    expect(find.text('Green Basket'), findsOneWidget);
    expect(find.text('Open now'), findsOneWidget);
    expect(find.text('Delete all my data'), findsOneWidget);
  });

  testAppWidgets('changing the kind warns first, then changes it', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(() => _seed(db));
    await _show(
      tester,
      _overrides(db, _Files(), active: 'shop1'),
      const SpaceSettingsScreen(spaceId: 'shop1'),
    );
    await tester.tap(find.byKey(const Key('space-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('space-kind-business')).last);
    await tester.pumpAndSettle();
    expect(find.text('Change Green Basket to a business?'), findsOneWidget);
    expect(find.text('Comes in'), findsOneWidget);
    expect(find.text('Goes away'), findsOneWidget);
    await tester.tap(find.byKey(const Key('space-kind-confirm')));
    await settleFrames(tester);
    final spaces = await tester.runAsync(
      () =>
          DriftAppSettingsRepository(db).readJson(SpacesController.settingsKey),
    );
    expect(spacesFromJson(spaces).last.kind, SpaceKind.business);
  });

  testAppWidgets('deleting a space needs its name typed', (tester) async {
    final db = openTestDatabase();
    final files = _Files();
    await tester.runAsync(() => _seed(db));
    await _show(
      tester,
      _overrides(db, files),
      const SpaceSettingsScreen(spaceId: 'shop1'),
    );
    await tester.ensureVisible(find.byKey(const Key('space-delete')));
    await tester.tap(find.byKey(const Key('space-delete')));
    await tester.pumpAndSettle();
    FilledButton confirm() => tester.widget<FilledButton>(
      find.byKey(const Key('space-delete-confirm')),
    );
    expect(confirm().onPressed, isNull);
    await tester.tap(find.byKey(const Key('keep-30-days')));
    await tester.enterText(
      find.byKey(const Key('space-delete-name')),
      'green basket',
    );
    await tester.pump();
    expect(confirm().onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('space-delete-confirm')));
    await settleFrames(tester);
    expect(files.deleted, ['shop1']);
  });

  testAppWidgets('Delete all my data asks before deleting everything', (
    tester,
  ) async {
    final db = openTestDatabase();
    final files = _Files();
    final restarter = _Restarter();
    await tester.runAsync(() => _seed(db));
    await _show(
      tester,
      _overrides(db, files, restarter: restarter),
      const DeleteAllScreen(),
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('delete-all-confirm')))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('delete-all-check')), 'DELETE');
    await tester.pump();
    await tester.tap(find.byKey(const Key('delete-all-confirm')));
    await settleFrames(tester);
    expect(files.erased, isTrue);
    expect(restarter.restarted, isTrue);
  });

  testAppWidgets('several transactions move to another space at once', (
    tester,
  ) async {
    final db = openTestDatabase();
    final moves = _Moves();
    await tester.runAsync(() async {
      await _seed(db);
      final account = (await db.select(db.accounts).get()).first.id;
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: account,
              occurredAt: DateTime.utc(2026, 11, 10, 9),
              amountMinor: 20000,
              direction: TransactionDirection.outflow,
              source: TransactionSource.manual,
            ),
          );
    });
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _show(tester, [
      ..._overrides(db, _Files()),
      spaceMoveRepositoryProvider.overrideWithValue(moves),
      loadedCategoriserProvider.overrideWithValue(
        const AsyncData(
          LoadedCategoriser(RuleCategoriser(), ModelStatus.notInstalled),
        ),
      ),
    ], const ActivityScreen());
    final rows = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('activity-choose-'),
    );
    expect(rows, findsNWidgets(2));
    await tester.longPress(rows.first);
    await tester.pump();
    await tester.tap(rows.last);
    await tester.pump();
    expect(find.text('2 chosen'), findsOneWidget);
    await tester.tap(find.byKey(const Key('activity-move-chosen')));
    await tester.pumpAndSettle();
    expect(find.text('Move 2 transactions'), findsOneWidget);
    await tester.tap(find.byKey(const Key('move-chosen-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('move-chosen-category-7')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('move-chosen-confirm')));
    await settleFrames(tester);
    expect(moves.moved.map((m) => (m.$2, m.$3)), [('shop1', 7), ('shop1', 7)]);
    expect(find.text('2 chosen'), findsNothing);
  });
}

class _Moves implements SpaceMoveRepository {
  final moved = <(int, String, int?)>[];

  @override
  Future<void> move(
    int transactionId,
    String spaceId, {
    int? toCategoryId,
  }) async => moved.add((transactionId, spaceId, toCategoryId));

  @override
  Future<List<({int id, String name})>> categoriesIn(String spaceId) async =>
      const [(id: 7, name: 'Stock bought')];
}
