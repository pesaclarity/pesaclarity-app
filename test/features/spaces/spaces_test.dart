import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/income/income_sources.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/income/application/income_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/features/spaces/presentation/spaces_sheet.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

class _MemoryStore implements ActiveSpaceStore {
  final written = <String>[];

  @override
  Future<void> write(String spaceId) async => written.add(spaceId);

  @override
  Future<void> writeOpenChoice(String choice) async => written.add(choice);
}

void main() {
  group('Space', () {
    test('the list always starts with Personal and skips bad entries', () {
      final spaces = spacesFromJson({
        'spaces': [
          {'id': 'abc123', 'name': 'Mama Mboga stall', 'kind': 'business'},
          {'id': 'Bad Id!', 'name': 'x', 'kind': 'business'},
          {'id': 'personal', 'name': 'Again', 'kind': 'personal'},
          {'id': 'def456', 'name': 'Shop', 'kind': 'unknown'},
        ],
      });
      expect(spaces.map((s) => s.id), [personalSpaceId, 'abc123']);
      expect(spaces.last.initial, 'M');
      expect(spacesFromJson(null), [Space.personal]);
      final back = spacesFromJson(spacesToJson(spaces));
      expect(back.map((s) => s.name), ['Personal', 'Mama Mboga stall']);
    });
  });

  test('the app opens in the last space unless one is chosen', () {
    expect(spaceToOpen(openLastSpace, 'abc123'), 'abc123');
    expect(spaceToOpen(askForSpace, 'abc123'), 'abc123');
    expect(spaceToOpen(personalSpaceId, 'abc123'), personalSpaceId);
    expect(spaceToOpen('def456', personalSpaceId), 'def456');
  });

  group('SpacesController', () {
    late AppDatabase personal;
    late AppDatabase business;
    late _MemoryStore store;
    late ProviderContainer container;

    setUp(() {
      personal = AppDatabase(NativeDatabase.memory());
      business = AppDatabase(NativeDatabase.memory());
      store = _MemoryStore();
      container = ProviderContainer(
        overrides: [
          activeSpaceStoreProvider.overrideWithValue(store),
          personalDatabaseProvider.overrideWithValue(personal),
          // Any other space opens the business database.
          appDatabaseProvider.overrideWith(
            (ref) => ref.watch(activeSpaceIdProvider) == personalSpaceId
                ? personal
                : business,
          ),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await personal.close();
      await business.close();
    });

    test('adding a business opens it and keeps the list in Personal', () async {
      final id = await container
          .read(spacesProvider.notifier)
          .add('  Mama Mboga stall ', SpaceKind.business);

      expect(container.read(activeSpaceIdProvider), id);
      expect(store.written, [id]);
      expect(container.read(activeSpaceProvider).name, 'Mama Mboga stall');
      expect(container.read(appDatabaseProvider), same(business));
      expect(container.read(mainDatabaseProvider), same(personal));

      // The list lives in Personal's database, not the new space's.
      final saved = await (personal.select(
        personal.appSettings,
      )..where((s) => s.key.equals(SpacesController.settingsKey))).get();
      expect(saved, hasLength(1));
      expect(
        await business
            .select(business.appSettings)
            .get()
            .then(
              (rows) =>
                  rows.where((r) => r.key == SpacesController.settingsKey),
            ),
        isEmpty,
      );

      // The business gets its own categories; Personal keeps its own.
      expect(await business.spaceKind(), SpaceKind.business);
      final businessKeys = {
        for (final c in await business.select(business.categories).get()) c.key,
      };
      expect(businessKeys, containsAll(['sales', 'stock', 'owner_pay']));
      expect(businessKeys, isNot(contains('betting')));
      expect(
        (await personal.select(personal.categories).get()).map((c) => c.key),
        contains('betting'),
      );

      // A business plans week by week from the start.
      final sources = await container.read(incomeSourcesProvider.future);
      expect(sources.picked, {IncomeSource.business});
    });

    test('switching back to Personal opens its database', () async {
      await container
          .read(spacesProvider.notifier)
          .add('Shop', SpaceKind.business);
      await container
          .read(activeSpaceIdProvider.notifier)
          .switchTo(personalSpaceId);
      expect(container.read(appDatabaseProvider), same(personal));
      expect(container.read(activeSpaceProvider), Space.personal);
    });

    test('a blank name is refused', () {
      expect(
        () => container
            .read(spacesProvider.notifier)
            .add(' ', SpaceKind.business),
        throwsArgumentError,
      );
    });
  });

  testWidgets('Open the app in saves the choice', (tester) async {
    final store = _MemoryStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          spacesProvider.overrideWith(_TwoSpaces.new),
          activeSpaceProvider.overrideWithValue(Space.personal),
          openSpaceChoiceProvider.overrideWith(() => _Choice(store)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: OpenSpaceSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('The last space you used'), findsOneWidget);
    expect(find.text('Personal right now'), findsOneWidget);
    expect(find.text('Ask each time'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-in-abc123')));
    await tester.pumpAndSettle();
    expect(store.written, ['abc123']);
  });

  testWidgets('the sheet lists spaces and opens one', (tester) async {
    final personal = AppDatabase(NativeDatabase.memory());
    final store = _MemoryStore();
    addTearDown(personal.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeSpaceStoreProvider.overrideWithValue(store),
          personalDatabaseProvider.overrideWithValue(personal),
          spacesProvider.overrideWith(_TwoSpaces.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: SpacesSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your spaces'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Mama Mboga stall'), findsOneWidget);
    expect(find.byKey(const Key('spaces-add')), findsOneWidget);
  });
}

class _TwoSpaces extends SpacesController {
  @override
  Future<List<Space>> build() async => const [
    Space.personal,
    Space(id: 'abc123', name: 'Mama Mboga stall', kind: SpaceKind.business),
  ];
}

class _Choice extends OpenSpaceChoice {
  _Choice(this.store);
  final _MemoryStore store;
  @override
  Future<void> choose(String choice) async {
    store.written.add(choice);
    state = choice;
  }
}
