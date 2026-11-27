import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/categories_repository.dart';
import 'package:pesaclarity/src/features/payees/presentation/categories_screen.dart';
import 'package:pesaclarity/src/features/payees/presentation/category_picker.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late int transport;
  late int uber;
  setUp(() => db = openTestDatabase());

  Future<void> seed(WidgetTester tester) => tester.runAsync(() async {
    final repo = DriftCategoriesRepository(db);
    transport = (await repo.byKey('transport'))!.id;
    uber = await repo.create(
      name: 'Uber',
      type: CategoryType.expense,
      parentId: transport,
    );
    await repo.create(
      name: 'Matatu',
      type: CategoryType.expense,
      parentId: transport,
    );
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testAppWidgets('the picker opens a parent in place, with its own '
      '"only" choice and its subcategories', (tester) async {
    await seed(tester);
    CategoryChoice? picked;
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              picked = await pickCategory(context, selectedId: transport),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // The chosen parent starts open.
    expect(find.text('Transport only'), findsOneWidget);
    expect(find.text('No subcategory'), findsOneWidget);
    final list = find
        .descendant(
          of: find.byType(CategoryPicker),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('New subcategory of Transport'),
      200,
      scrollable: list,
    );
    await tester.ensureVisible(find.text('Uber'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uber'));
    await tester.pumpAndSettle();
    expect((picked! as ChosenCategory).id, uber);
  });

  testAppWidgets('searching finds a subcategory by its full name', (
    tester,
  ) async {
    await seed(tester);
    await pump(tester, const CategoryPicker());
    await tester.enterText(find.byType(TextField), 'uber');
    await tester.pumpAndSettle();
    expect(find.text('Transport › Uber'), findsOneWidget);
  });

  testAppWidgets('a category lists its subcategories and adds one', (
    tester,
  ) async {
    await seed(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: CategoryScreen(categoryId: transport),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Spending · Counts toward safe to spend'), findsOneWidget);
    expect(find.text('Uber'), findsOneWidget);
    expect(find.text('Matatu'), findsOneWidget);
    expect(find.text('No subcategory · 0 this month'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('add-to-category')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('subcategory-name')),
      'Boda boda',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add to Transport'));
    await tester.tap(find.text('Add to Transport'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    final boda = await tester.runAsync(
      () => (db.select(
        db.categories,
      )..where((c) => c.name.equals('Boda boda'))).getSingle(),
    );
    expect(boda!.parentId, transport);
  });
}
