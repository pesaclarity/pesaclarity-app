import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/app.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/onboarding_repository.dart';
import 'package:pesaclarity/src/domain/look/look_settings.dart';
import 'package:pesaclarity/src/features/look/application/look_providers.dart';
import 'package:pesaclarity/src/features/look/presentation/field_style_theme.dart';
import 'package:pesaclarity/src/features/profile/presentation/profile_screen.dart';
import 'package:pesaclarity/src/features/security/application/device_integrity_providers.dart';
import 'package:pesaclarity/src/features/security/data/device_integrity_checker.dart';
import 'package:pesaclarity/src/features/security/data/secure_store.dart';
import 'package:pesaclarity/src/features/security/domain/device_integrity.dart';
import 'package:pesaclarity/src/features/security/domain/lock_settings.dart';
import 'package:pesaclarity/src/features/security/presentation/lock_screen.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../helpers/fake_app_lock.dart';
import '../../helpers/fake_sms_source.dart';
import '../../helpers/test_app.dart';

class _CleanPhone implements DeviceIntegrityChecker {
  const _CleanPhone();

  @override
  Future<DeviceIntegrityReport> check() async => DeviceIntegrityReport.clean;
}

const _dark = LookSettings(theme: ThemeChoice.dark, fields: FieldStyle.boxed);

void main() {
  late AppDatabase db;
  late MemorySecureStore store;

  setUp(() {
    db = openTestDatabase();
    store = MemorySecureStore();
  });

  Future<void> saveInDatabase(WidgetTester tester, LookSettings look) =>
      tester.runAsync(
        () =>
            DriftAppSettingsRepository(db)
                .writeJson(LookSettingsController.settingsKey, look.toJson()),
      );

  ThemeMode modeOf(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

  InputBorder? borderOf(WidgetTester tester, Finder finder) =>
      Theme.of(tester.element(finder)).inputDecorationTheme.border;

  test('the look keeps; nothing saved, or older settings, mean the usual', () {
    expect(LookSettings.fromJson(null).theme, ThemeChoice.system);
    expect(LookSettings.fromJson(null).fields, FieldStyle.underlined);
    expect(
      LookSettings.fromJson(const {'fields': 'boxed'}).theme,
      ThemeChoice.system,
    );
    expect(
      LookSettings.fromJson(const {'fields': 'odd'}).fields,
      FieldStyle.underlined,
    );
    for (final t in ThemeChoice.values) {
      for (final f in FieldStyle.values) {
        final back = LookSettings.fromJson(
          LookSettings(theme: t, fields: f).toJson(),
        );
        expect((back.theme, back.fields), (t, f));
      }
    }
    expect(themeModeFor(ThemeChoice.system), ThemeMode.system);
    expect(themeModeFor(ThemeChoice.light), ThemeMode.light);
    expect(themeModeFor(ThemeChoice.dark), ThemeMode.dark);
  });

  test('the copy for before unlock reads back, or the usual look', () async {
    expect(
      (await readStartupLook(store)).toJson(),
      const LookSettings().toJson(),
    );
    store.values[lookStartupKey] = jsonEncode(_dark.toJson());
    expect((await readStartupLook(store)).toJson(), _dark.toJson());
    store.values[lookStartupKey] = 'not json';
    expect(
      (await readStartupLook(store)).toJson(),
      const LookSettings().toJson(),
    );
  });

  test('boxed fields get an outline in both themes', () {
    final light = AppTheme.light;
    expect(
      identical(AppTheme.withFields(light, FieldStyle.underlined), light),
      isTrue,
    );
    for (final base in [AppTheme.light, AppTheme.dark]) {
      final boxed = AppTheme.withFields(base, FieldStyle.boxed);
      expect(boxed.inputDecorationTheme.border, isA<OutlineInputBorder>());
      expect(
        boxed.inputDecorationTheme.enabledBorder,
        isA<OutlineInputBorder>(),
      );
      expect(
        (boxed.inputDecorationTheme.focusedBorder! as OutlineInputBorder)
            .borderSide
            .color,
        base.colorScheme.primary,
      );
    }
  });

  testAppWidgets('a fresh install follows the phone with underlined fields', (
    tester,
  ) async {
    await pumpApp(tester, db: db, secureStore: store);
    expect(modeOf(tester), ThemeMode.system);
    final field = find.byType(EditableText);
    if (field.evaluate().isNotEmpty) {
      expect(borderOf(tester, field.first), isNot(isA<OutlineInputBorder>()));
    }
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first))
          .inputDecorationTheme
          .border,
      isNot(isA<OutlineInputBorder>()),
    );
  });

  for (final (choice, mode) in [
    (ThemeChoice.system, ThemeMode.system),
    (ThemeChoice.light, ThemeMode.light),
    (ThemeChoice.dark, ThemeMode.dark),
  ]) {
    testAppWidgets('the app opens in the ${choice.label} theme', (
      tester,
    ) async {
      await saveInDatabase(tester, LookSettings(theme: choice));
      await pumpApp(tester, db: db, secureStore: store);
      expect(modeOf(tester), mode);
      // The copy for before unlock now matches the database.
      final early = await tester.runAsync(() => readStartupLook(store));
      expect(early!.toJson(), LookSettings(theme: choice).toJson());
    });
  }

  testAppWidgets('the lock screen uses the saved Dark theme before unlock', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await DriftOnboardingRepository(db).markComplete();
      final vault = testKeyVault(store);
      final key = await vault.readOrCreateOpenKey();
      await vault.setPin('246810', key);
      await vault.writeSettings(const LockSettings(pinSet: true));
      await store.write(lookStartupKey, jsonEncode(_dark.toJson()));
    });
    final look = await tester.runAsync(() => readStartupLook(store));
    var opened = false;
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          ...appLockOverrides(store: store),
          appDatabaseProvider.overrideWith((ref) {
            opened = true;
            return db;
          }),
          smsSourceProvider.overrideWithValue(FakeSmsSource()),
          startupLookProvider.overrideWithValue(look!),
        ],
        child: const PesaClarityApp(),
      ),
    );
    // The very first frame already has the saved theme.
    expect(modeOf(tester), ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsOneWidget);
    expect(modeOf(tester), ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.byType(LockScreen))).brightness,
      Brightness.dark,
    );
    expect(
      borderOf(tester, find.byType(LockScreen)),
      isA<OutlineInputBorder>(),
    );
    expect(opened, isFalse);
  });

  testAppWidgets('after unlock the database wins and the copy follows it', (
    tester,
  ) async {
    await saveInDatabase(tester, const LookSettings(theme: ThemeChoice.light));
    store.values[lookStartupKey] = jsonEncode(_dark.toJson());
    await pumpApp(
      tester,
      db: db,
      secureStore: store,
      overrides: [startupLookProvider.overrideWithValue(_dark)],
    );
    expect(modeOf(tester), ThemeMode.light);
    expect(
      jsonDecode(store.values[lookStartupKey]!),
      const LookSettings(theme: ThemeChoice.light).toJson(),
    );
  });

  testAppWidgets('saving keeps the look in the database and the lock copy', (
    tester,
  ) async {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ...appLockOverrides(store: store),
      ],
    );
    addTearDown(c.dispose);
    await tester.runAsync(() async {
      await c.read(lookSettingsProvider.future);
      await c.read(lookSettingsProvider.notifier).save(_dark);
    });
    final saved = await tester.runAsync(
      () =>
          DriftAppSettingsRepository(db)
              .readJson(LookSettingsController.settingsKey),
    );
    expect(saved, _dark.toJson());
    expect(jsonDecode(store.values[lookStartupKey]!), _dark.toJson());
  });

  testAppWidgets('pages and dialogs follow the field style', (tester) async {
    await saveInDatabase(tester, const LookSettings(fields: FieldStyle.boxed));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ...appLockOverrides(store: store),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => FieldStyleTheme(child: child!),
          home: const Scaffold(body: TextField(key: Key('page-field'))),
        ),
      ),
    );
    await settleFrames(tester);
    final page = find.byKey(const Key('page-field'));
    expect(borderOf(tester, page), isA<OutlineInputBorder>());
    unawaited(
      showDialog<void>(
        context: tester.element(page),
        builder: (_) =>
            const AlertDialog(content: TextField(key: Key('dialog-field'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      borderOf(tester, find.byKey(const Key('dialog-field'))),
      isA<OutlineInputBorder>(),
    );
  });

  testAppWidgets('Profile: Look sets the theme and text fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ...appLockOverrides(store: store),
          deviceIntegrityCheckerProvider.overrideWithValue(const _CleanPhone()),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ProfileScreen()),
      ),
    );
    await settleFrames(tester);
    await scrollTo(tester, find.byKey(const Key('profile-look')));
    expect(find.text('System theme · underlined fields'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-look')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('look-fields-boxed')));
    await settleFrames(tester);
    await tester.tap(find.byKey(const Key('look-theme')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('look-theme-dark')));
    await settleFrames(tester);
    expect(find.text('Dark theme · boxed fields'), findsOneWidget);
    expect(jsonDecode(store.values[lookStartupKey]!), _dark.toJson());
  });
}
