import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/category_seeds.dart';
import 'package:pesaclarity/src/data/repositories/sales_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/spaces/space_categories.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/books/application/books_providers.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/lending/data/reminder_sharer.dart';
import 'package:pesaclarity/src/features/people/presentation/people_screen.dart';
import 'package:pesaclarity/src/features/people/presentation/statement_screen.dart';
import 'package:pesaclarity/src/features/reminders/application/business_reminders.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

class _Sharer implements ReminderSharer {
  final shared = <String>[];

  @override
  Future<void> share(String message) async => shared.add(message);
}

class _Launcher implements MessageLauncher {
  final opened = <(SendWith, String, String)>[];

  @override
  Future<bool> open(SendWith app, String international, String text) async {
    opened.add((app, international, text));
    return true;
  }
}

class _Picker implements ContactPicker {
  @override
  Future<PickedContact?> pickPhone() async =>
      (number: '+254 712 345 678', name: 'Otieno');
}

const _stall = Space(
  id: 'abc123',
  name: 'Vegetable stall',
  kind: SpaceKind.business,
);

void main() {
  late AppDatabase db;
  late _Sharer sharer;
  late _Launcher launcher;
  final now = eat(2026, 11, 5, 10);

  setUp(() {
    db = openTestDatabase();
    sharer = _Sharer();
    launcher = _Launcher();
  });

  List<Override> overrides() => [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(() => now),
    activeSpaceProvider.overrideWithValue(_stall),
    reminderSharerProvider.overrideWithValue(sharer),
    messageLauncherProvider.overrideWithValue(launcher),
    contactPickerProvider.overrideWithValue(_Picker()),
    deviceRegionProvider.overrideWithValue('KE'),
  ];

  Future<void> seed(ProviderContainer c) async {
    final controller = c.read(salesControllerProvider);
    await controller.sell(
      [const SalePart(SalePaymentMethod.credit, 120000)],
      credit: CreditTerms(
        customer: 'Otieno',
        dueDate: CalendarDate(2026, 11, 5),
      ),
    );
    await controller.bought(
      amountMinor: 450000,
      method: SalePaymentMethod.credit,
      categoryId: await ensureCategory(db, stockSeed),
      supplier: 'Wakulima wholesaler',
      dueDate: CalendarDate(2026, 11, 7),
      note: 'Tomatoes',
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    String path = AppRoutes.people,
  }) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    await tester.runAsync(() => seed(c));
    final router = GoRouter(
      initialLocation: path,
      routes: [
        GoRoute(
          path: AppRoutes.people,
          builder: (_, _) => const PeopleScreen(),
          routes: [
            GoRoute(
              path: 'customer',
              builder: (_, state) => CustomerStatementScreen(
                name: state.uri.queryParameters['name']!,
              ),
            ),
            GoRoute(
              path: 'supplier/:id',
              builder: (_, state) => SupplierStatementScreen(
                debtId: int.parse(state.pathParameters['id']!),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await settleFrames(tester);
  }

  testAppWidgets('customers show what they owe; Remind without a number '
      'shares the message', (tester) async {
    await pump(tester);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Otieno'), findsOneWidget);
    expect(find.text('Due today · since 5 Nov'), findsOneWidget);
    expect(find.byKey(const Key('remind-all')), findsOneWidget);

    await tester.tap(find.byKey(const Key('remind-Otieno')));
    await settleFrames(tester);
    // Due today picks the Due today message.
    final message = tester.widget<TextField>(
      find.byKey(const Key('remind-message')),
    );
    expect(
      message.controller!.text,
      'Hi Otieno, KES 1,200 is due today. Thank you!',
    );
    await tester.tap(find.byKey(const Key('remind-send')));
    await settleFrames(tester);
    expect(
      sharer.shared.single,
      'Hi Otieno, KES 1,200 is due today. Thank you!',
    );
  });

  testAppWidgets('Remind with a contact opens WhatsApp to their number', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('remind-Otieno')));
    await settleFrames(tester);
    await tester.tap(find.byKey(const Key('phone-contacts')));
    await settleFrames(tester);
    // Three messages: a drop-down, starting on Due today.
    expect(
      find.descendant(
        of: find.byKey(const Key('remind-template')),
        matching: find.text('Due today'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('remind-template')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('template-friendly')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remind-send')));
    await settleFrames(tester);
    final (app, number, text) = launcher.opened.single;
    expect(app, SendWith.whatsapp);
    expect(number, '+254712345678');
    expect(
      text,
      'Hi Otieno, a friendly reminder from Vegetable stall: KES 1,200, due '
      'today. Thank you!',
    );
    final saved = await tester.runAsync(() => db.select(db.contacts).get());
    expect(saved!.single.phone, '+254712345678');
  });

  testAppWidgets('suppliers show what is owed and due', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Suppliers'));
    await settleFrames(tester);
    expect(find.text('Wakulima wholesaler'), findsOneWidget);
    expect(find.text('Due 7 Nov'), findsOneWidget);
    expect(find.text('4,500'), findsWidgets);
    expect(find.byKey(const Key('bought-on-credit')), findsOneWidget);
  });

  testAppWidgets('a customer statement lists credit and payments', (
    tester,
  ) async {
    await pump(tester, path: AppRoutes.customerStatement('Otieno'));
    expect(find.text('1,200'), findsOneWidget);
    expect(find.text('On credit'), findsOneWidget);
    expect(find.text('+1,200'), findsOneWidget);
  });

  testAppWidgets('a supplier statement lists what was bought', (tester) async {
    // The first debt in a fresh database is the one Bought made.
    await pump(tester, path: AppRoutes.supplierStatement(1));
    expect(find.text('Tomatoes on credit'), findsOneWidget);
    expect(find.text('4,500'), findsOneWidget);
  });

  test(
    'customers and suppliers from before the records join the books',
    () async {
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'Cash',
              type: AccountType.cash,
              openingDate: eat(2026, 11, 1, 0),
            ),
          );
      await db
          .into(db.lentLoans)
          .insert(
            LentLoansCompanion.insert(
              person: 'Kamau',
              amountMinor: 70000,
              lentOn: eat(2026, 10, 18, 0),
            ),
          );
      await db
          .into(db.debts)
          .insert(
            DebtsCompanion.insert(
              lender: 'Mzee Juma',
              type: DebtType.supplier,
              startingBalanceMinor: 150000,
              isFormal: const Value(false),
            ),
          );
      final books = await c.read(booksProvider.future);
      expect(books.unbalanced, isEmpty);
      expect(books.balanceOf(BookAccount.owedToYou, currency: 'KES'), 70000);
      expect(
        books.balanceOf(BookAccount.owedToSuppliers, currency: 'KES'),
        150000,
      );
    },
  );
}
