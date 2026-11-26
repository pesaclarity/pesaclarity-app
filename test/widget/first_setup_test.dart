// The whole first setup on the real router and providers, the way a new
// phone sees it: every button in order, from the welcome screen to Home,
// with made-up M-Pesa and bank messages. Then the ways a phone can make it
// go wrong: settings that cannot be read or saved, a slow database, no SMS
// access, no messages, and a database that opens before app lock has the
// key.
import 'package:drift/drift.dart' show LazyDatabase, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/build_info.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/core/money/money.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_key_store.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/onboarding_repository.dart';
import 'package:pesaclarity/src/features/app_status/application/app_status_providers.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/income/application/income_providers.dart';
import 'package:pesaclarity/src/features/security/data/secure_store.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:pesaclarity/src/routing/app_shell.dart';
import 'package:pesaclarity/src/shared/semantic_ids.dart';
import 'package:ujumbe/ujumbe.dart';

import '../features/app_status/app_status_fakes.dart';
import '../helpers/fake_sms_source.dart';
import '../helpers/sms_samples.dart';
import '../helpers/test_app.dart';

/// Made-up messages from three accounts, and one personal chat that must
/// never be read.
List<SmsMessage> _inbox() => [
  mpesaSent(),
  mpesaTill(),
  mpesaNotice(),
  kcbDebit(),
  equityReceived(),
  personal(),
];

/// Settings that fail as told: reads of [failReads] keys throw, the next
/// [failWrites] writes throw, and reads of [slowReads] keys take [slow].
class _FlakySettings implements AppSettingsRepository {
  _FlakySettings(
    this._inner, {
    this.failReads = const {},
    this.failWrites = 0,
    this.slowReads = const {},
    this.slow = Duration.zero,
  });

  final AppSettingsRepository _inner;
  final Set<String> failReads;
  final Set<String> slowReads;
  final Duration slow;
  int failWrites;
  int reads = 0;

  @override
  Future<Map<String, Object?>?> readJson(String key) async {
    reads++;
    if (slowReads.contains(key)) await Future<void>.delayed(slow);
    if (failReads.contains(key)) {
      throw const _DiskError('the settings could not be read');
    }
    return _inner.readJson(key);
  }

  @override
  Future<void> writeJson(String key, Map<String, Object?> value) async {
    if (failWrites > 0) {
      failWrites--;
      throw const _DiskError('the settings could not be written');
    }
    await _inner.writeJson(key, value);
  }
}

class _DiskError implements Exception {
  const _DiskError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A phone's keystore on first use, which makes its key before answering.
class _SlowKeystore extends MemorySecureStore {
  @override
  Future<String?> read(String key) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return super.write(key, value);
  }
}

/// The database as the phone opens it (connection.dart): on first use, with
/// the key the app lock released, after [delay] (SQLCipher on a slow
/// phone). [early] counts opens that came before the key.
AppDatabase _phoneDatabase(
  ReleasedDatabaseKey key, {
  Duration delay = Duration.zero,
  List<String>? early,
}) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final store = UnlockedDatabaseKeyStore(key);
  final db = AppDatabase(
    LazyDatabase(() async {
      if (key.value == null) early?.add(StackTrace.current.toString());
      final hex = await store.readOrCreateKey();
      expect(hex, hasLength(64));
      await Future<void>.delayed(delay);
      return NativeDatabase.memory();
    }),
  );
  addTearDown(db.close);
  return db;
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

Future<void> _tapId(WidgetTester tester, String id) async {
  await scrollTo(tester, find.bySemanticsIdentifier(id));
  await tester.tap(find.bySemanticsIdentifier(id));
  await tester.pumpAndSettle();
}

FilledButton _button(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

/// Welcome: Get started.
Future<void> _welcome(WidgetTester tester) async {
  expect(find.text('Know what you can spend today.'), findsOneWidget);
  await tester.tap(find.text('Get started'));
  await tester.pumpAndSettle();
}

/// Currency: the suggested KES, Continue working at once.
Future<void> _currency(WidgetTester tester, {String? second}) async {
  expect(find.text('Which currency do you count in?'), findsOneWidget);
  expect(
    tester.getSemantics(
      find.bySemanticsIdentifier(SemanticIds.currency('KES')),
    ),
    isSemantics(isChecked: true, hasCheckedState: true),
  );
  expect(find.text('Second currency (optional)'), findsOneWidget);
  expect(_button(tester, 'Continue with KES').onPressed, isNotNull);
  if (second != null) {
    await tester.tap(find.byKey(const Key('second-currency')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Second currency'), findsOneWidget);
    // The main currency is not offered as the second.
    expect(find.byKey(const Key('currency-KES')), findsNothing);
    await tester.enterText(find.byKey(const Key('currency-search')), second);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('currency-$second')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('second-currency')),
        matching: find.text(second),
      ),
      findsOneWidget,
    );
  }
  await _tapId(tester, SemanticIds.onboardingCurrencyContinue);
}

/// Income: Salary, then Continue.
Future<void> _income(WidgetTester tester) async {
  expect(find.text('How does money usually come to you?'), findsOneWidget);
  await _tapId(tester, SemanticIds.incomeSource('salary'));
  await _tapId(tester, SemanticIds.onboardingIncomeContinue);
}

/// My accounts: M-Pesa, KCB and Equity, then Scan my messages.
Future<void> _accounts(WidgetTester tester) async {
  expect(find.text('Which accounts do you use?'), findsOneWidget);
  for (final id in ['mpesa', 'kcb', 'equity']) {
    await _tapId(tester, SemanticIds.institution(id));
  }
  await _tapId(tester, SemanticIds.onboardingScanMessages);
  expect(
    find.text('Let Pesa Clarity read your account messages'),
    findsOneWidget,
  );
}

/// Home, as its tab bar and lead card show it.
void _expectHome() {
  expect(find.bySemanticsIdentifier(SemanticIds.titleHome), findsOneWidget);
  expect(find.byType(PillNavigationBar), findsOneWidget);
}

void main() {
  setUp(() {
    addTearDown(() => BaseCurrency.code = 'KES');
  });

  testAppWidgets('a new phone: every setup button in order, to Home with the '
      'messages read', (tester) async {
    final semantics = tester.ensureSemantics();
    final db = openTestDatabase();
    final sms = FakeSmsSource(inbox: _inbox(), current: SmsAccess.denied);
    addTearDown(sms.close);
    await pumpApp(tester, db: db, sms: sms);

    await _welcome(tester);
    await _currency(tester, second: 'USD');
    await _income(tester);
    await _accounts(tester);

    await tapText(tester, 'Allow access to messages');
    expect(sms.permissionRequests, 1);
    // Only the ticked accounts' senders; never the personal chat.
    final read = sms.reads.expand((r) => r.senders).toSet();
    expect(read, containsAll(['MPESA', 'KCB']));
    expect(read, isNot(contains(personal().sender)));
    expect(find.text('Found 4 transactions'), findsOneWidget);
    expect(find.textContaining('1 message could not be read'), findsOneWidget);

    await tapText(tester, 'Continue');
    expect(find.text('Everything so far'), findsOneWidget);
    expect(find.text('From 4 transactions in your messages.'), findsOneWidget);
    await tapText(tester, 'Go to Home');

    _expectHome();
    expect(find.text('Safe to spend today'), findsOneWidget);
    // On hand adds up what the balances in the messages say; it is in
    // Insights › Your month.
    await openYourMonth(tester);
    await scrollTo(tester, find.byKey(const Key('home-on-hand')));
    expect(find.byKey(const Key('home-on-hand')), findsOneWidget);
    // No rates yet (nothing fetched, none set): no second figure.
    expect(find.textContaining('≈ USD'), findsNothing);
    await backToHome(tester);

    final saved = await tester.runAsync(() async {
      final settings = DriftAppSettingsRepository(db);
      return (
        currency: await settings.readJson(CurrencyController.settingsKey),
        income: await settings.readJson(IncomeSourcesController.settingsKey),
        done: await DriftOnboardingRepository(db).isComplete(),
        transactions: await db.select(db.transactions).get(),
      );
    });
    expect(saved!.currency, containsPair('base', 'KES'));
    expect(saved.currency, containsPair('secondary', 'USD'));
    expect(saved.income, isNotNull);
    expect(saved.done, isTrue);
    expect(saved.transactions, hasLength(4));

    // The transactions read are the ones in Activity.
    await tester.tap(
      find.descendant(
        of: find.byType(PillNavigationBar),
        matching: find.text('Activity'),
      ),
    );
    await tester.pumpAndSettle();
    for (final name in ['JANE DOE', 'EXAMPLE GROCERS']) {
      expect(find.textContaining(name), findsWidgets, reason: name);
    }
    semantics.dispose();
  });

  testAppWidgets('a database read before app lock has the key waits for it, '
      'so setup goes on', (tester) async {
    // A release build: the app status check starts with the first frame,
    // before a new phone's keystore has made the key.
    final key = ReleasedDatabaseKey();
    final early = <String>[];
    final db = _phoneDatabase(key, early: early);
    final sms = FakeSmsSource(inbox: _inbox());
    addTearDown(sms.close);
    await pumpApp(
      tester,
      db: db,
      sms: sms,
      flavor: AppFlavor.play,
      secureStore: _SlowKeystore(),
      overrides: [
        releasedDatabaseKeyProvider.overrideWithValue(key),
        appStatusSourceProvider.overrideWithValue(FakeAppStatusSource()),
        buildVersionProvider.overrideWithValue('0.3.0'),
      ],
    );

    // The check did reach for the database first: the case on the phone.
    expect(early, isNotEmpty);
    await _welcome(tester);
    await _currency(tester);
    expect(find.text('How does money usually come to you?'), findsOneWidget);
    await _income(tester);
    await _accounts(tester);
    await tapText(tester, 'Allow access to messages');
    expect(find.text('Found 4 transactions'), findsOneWidget);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Go to Home');
    _expectHome();
  });

  testAppWidgets('settings that cannot be read: setup still shows its '
      'suggestions and goes on', (tester) async {
    final db = openTestDatabase();
    final settings = _FlakySettings(
      DriftAppSettingsRepository(db),
      failReads: {
        CurrencyController.settingsKey,
        CurrencyController.ratesKey,
        IncomeSourcesController.settingsKey,
      },
    );
    final sms = FakeSmsSource(inbox: _inbox());
    addTearDown(sms.close);
    await pumpApp(
      tester,
      db: db,
      sms: sms,
      overrides: [appSettingsRepositoryProvider.overrideWithValue(settings)],
    );

    await _welcome(tester);
    expect(_container(tester).read(currencyControllerProvider).hasError, true);
    await _currency(tester);
    await _income(tester);
    await _accounts(tester);
    await tapText(tester, 'Allow access to messages');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Go to Home');
    _expectHome();
    final saved = await tester.runAsync(
      () =>
          DriftAppSettingsRepository(db)
              .readJson(CurrencyController.settingsKey),
    );
    expect(saved, containsPair('base', 'KES'));
  });

  testAppWidgets('a save that fails says so, with Try again, and the next '
      'try goes on', (tester) async {
    final db = openTestDatabase();
    final settings = _FlakySettings(
      DriftAppSettingsRepository(db),
      failWrites: 1,
    );
    await pumpApp(
      tester,
      db: db,
      overrides: [appSettingsRepositoryProvider.overrideWithValue(settings)],
    );

    await _welcome(tester);
    await _currency(tester);
    expect(find.text('Which currency do you count in?'), findsOneWidget);
    expect(find.text('Your currency could not be saved.'), findsOneWidget);
    expect(_button(tester, 'Try again').onPressed, isNotNull);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('How does money usually come to you?'), findsOneWidget);

    settings.failWrites = 1;
    await _tapId(tester, SemanticIds.incomeSource('salary'));
    await _tapId(tester, SemanticIds.onboardingIncomeContinue);
    expect(find.text('Your answer could not be saved.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Which accounts do you use?'), findsOneWidget);
  });

  testAppWidgets('a slow database: the currency step works at once, and the '
      'choice survives the slow read', (tester) async {
    final key = ReleasedDatabaseKey();
    final db = _phoneDatabase(key, delay: const Duration(seconds: 5));
    final settings = _FlakySettings(
      DriftAppSettingsRepository(db),
      slowReads: {CurrencyController.settingsKey},
      slow: const Duration(seconds: 12),
    );
    await pumpApp(
      tester,
      db: db,
      overrides: [
        releasedDatabaseKeyProvider.overrideWithValue(key),
        appSettingsRepositoryProvider.overrideWithValue(settings),
      ],
    );

    await _welcome(tester);
    // Still reading: the suggestion shows and Continue works.
    expect(_container(tester).read(currencyControllerProvider).isLoading, true);
    await tester.enterText(find.byKey(const Key('currency-search')), 'USD');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('currency-USD')));
    await tester.pump();
    final button = find.widgetWithText(FilledButton, 'Continue with USD');
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pump();
    // Saving shows, rather than a grey button with no word of why.
    expect(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(find.text('How does money usually come to you?'), findsOneWidget);

    // Once the slow read ends, the choice is what the app counts in.
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    final current = _container(tester).read(currencyControllerProvider).value;
    expect(current?.base, 'USD');
    expect(current?.chosen, isTrue);
  });

  testAppWidgets('no SMS access: Continue without messages reaches Home', (
    tester,
  ) async {
    final sms = FakeSmsSource(inbox: _inbox(), dialogAnswer: SmsAccess.denied);
    addTearDown(sms.close);
    await pumpApp(tester, db: openTestDatabase(), sms: sms);
    await _welcome(tester);
    await _currency(tester);
    await _income(tester);
    await _accounts(tester);
    await tapText(tester, 'Allow access to messages');
    expect(find.text('Messages not shared'), findsOneWidget);
    await tapText(tester, 'Continue without messages');
    _expectHome();
    expect(sms.reads, isEmpty);
  });

  testAppWidgets('no messages yet: Continue reaches Home', (tester) async {
    final sms = FakeSmsSource();
    addTearDown(sms.close);
    await pumpApp(tester, db: openTestDatabase(), sms: sms);
    await _welcome(tester);
    await _currency(tester);
    await _income(tester);
    await _accounts(tester);
    await tapText(tester, 'Allow access to messages');
    expect(find.text('No transactions found yet'), findsOneWidget);
    await tapText(tester, 'Continue');
    _expectHome();
  });

  testAppWidgets('when asking for SMS access fails, the step offers Try '
      'again and going on', (tester) async {
    final sms = _ThrowingAccess(inbox: _inbox());
    addTearDown(sms.close);
    await pumpApp(tester, db: openTestDatabase(), sms: sms);
    await _welcome(tester);
    await _currency(tester);
    await _income(tester);
    await _accounts(tester);
    await tapText(tester, 'Allow access to messages');
    expect(find.text('The scan stopped'), findsOneWidget);
    sms.fails = false;
    await tapText(tester, 'Try again');
    expect(find.text('Found 4 transactions'), findsOneWidget);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Go to Home');
    _expectHome();
  });

  testAppWidgets('when finishing setup cannot be saved, it says so and Try '
      'again finishes', (tester) async {
    final db = openTestDatabase();
    final onboarding = _FlakyOnboarding(DriftOnboardingRepository(db));
    await pumpApp(
      tester,
      db: db,
      sms: FakeSmsSource(current: SmsAccess.denied),
      overrides: [onboardingRepositoryProvider.overrideWithValue(onboarding)],
    );
    await _welcome(tester);
    await _currency(tester);
    await _income(tester);
    await _accounts(tester);
    onboarding.failures = 1;
    await tapText(tester, 'Do this later');
    expect(find.text('Setup could not be finished.'), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Try again'));
    await tester.pumpAndSettle();
    _expectHome();
  });
}

class _ThrowingAccess extends FakeSmsSource {
  _ThrowingAccess({super.inbox});

  bool fails = true;

  @override
  Future<SmsAccess> requestAccess() async {
    if (fails) throw StateError('The permission channel did not answer');
    return super.requestAccess();
  }
}

class _FlakyOnboarding implements OnboardingRepository {
  _FlakyOnboarding(this._inner);

  final OnboardingRepository _inner;
  int failures = 0;

  @override
  Future<bool> isComplete() => _inner.isComplete();

  @override
  Future<void> markComplete() async {
    if (failures > 0) {
      failures--;
      throw const _DiskError('setup could not be saved');
    }
    await _inner.markComplete();
  }
}
