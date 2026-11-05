import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/domain/look/look_settings.dart';
import 'package:pesaclarity/src/features/look/application/look_providers.dart';
import 'package:pesaclarity/src/features/look/presentation/field_style_theme.dart';
import 'package:pesaclarity/src/features/profile/presentation/profile_screen.dart';
import 'package:pesaclarity/src/features/security/application/device_integrity_providers.dart';
import 'package:pesaclarity/src/features/security/data/device_integrity_checker.dart';
import 'package:pesaclarity/src/features/security/domain/device_integrity.dart';
import 'package:pesaclarity/src/routing/app_router.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../helpers/test_app.dart';

class _CleanPhone implements DeviceIntegrityChecker {
  const _CleanPhone();

  @override
  Future<DeviceIntegrityReport> check() async => DeviceIntegrityReport.clean;
}

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());

  test('the theme keeps; nothing saved, or older settings, mean System', () {
    expect(LookSettings.fromJson(null).theme, ThemeChoice.system);
    expect(
      LookSettings.fromJson(const {'fields': 'boxed'}).theme,
      ThemeChoice.system,
    );
    for (final t in ThemeChoice.values) {
      final back = LookSettings.fromJson(LookSettings(theme: t).toJson());
      expect(back.theme, t);
      expect(back.fields, FieldStyle.underlined);
    }
    expect(themeModeFor(ThemeChoice.system), ThemeMode.system);
    expect(themeModeFor(ThemeChoice.light), ThemeMode.light);
    expect(themeModeFor(ThemeChoice.dark), ThemeMode.dark);
  });

  for (final (choice, mode) in [
    (ThemeChoice.system, ThemeMode.system),
    (ThemeChoice.light, ThemeMode.light),
    (ThemeChoice.dark, ThemeMode.dark),
  ]) {
    testAppWidgets('the app opens in the ${choice.label} theme', (
      tester,
    ) async {
      await tester.runAsync(
        () => DriftAppSettingsRepository(db).writeJson(
          LookSettingsController.settingsKey,
          LookSettings(theme: choice).toJson(),
        ),
      );
      await pumpApp(
        tester,
        db: db,
        overrides: [
          launchGateProvider.overrideWithValue(const AsyncData(true)),
        ],
      );
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        mode,
      );
    });
  }

  testAppWidgets('until the app is open it follows the phone', (tester) async {
    await tester.runAsync(
      () => DriftAppSettingsRepository(db).writeJson(
        LookSettingsController.settingsKey,
        const LookSettings(theme: ThemeChoice.dark).toJson(),
      ),
    );
    await pumpApp(tester, db: db);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
  });

  test('the field style keeps; nothing saved means underlined', () {
    expect(LookSettings.fromJson(null).fields, FieldStyle.underlined);
    expect(
      LookSettings.fromJson(const {'fields': 'odd'}).fields,
      FieldStyle.underlined,
    );
    final boxed = const LookSettings().copyWith(fields: FieldStyle.boxed);
    expect(LookSettings.fromJson(boxed.toJson()).fields, FieldStyle.boxed);
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

  Future<void> pumpField(WidgetTester tester, {required bool open}) async {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        launchGateProvider.overrideWithValue(AsyncData(open)),
      ],
    );
    addTearDown(c.dispose);
    await tester.runAsync(
      () => c
          .read(lookSettingsProvider.notifier)
          .save(const LookSettings(fields: FieldStyle.boxed)),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => FieldStyleTheme(child: child!),
          home: const Scaffold(body: TextField(key: Key('page-field'))),
        ),
      ),
    );
    await settleFrames(tester);
  }

  InputBorder? borderOf(WidgetTester tester, String key) =>
      Theme.of(tester.element(find.byKey(Key(key))))
          .inputDecorationTheme
          .border;

  testAppWidgets('pages and dialogs follow the choice once the app is open', (
    tester,
  ) async {
    await pumpField(tester, open: true);
    expect(borderOf(tester, 'page-field'), isA<OutlineInputBorder>());
    unawaited(
      showDialog<void>(
        context: tester.element(find.byKey(const Key('page-field'))),
        builder: (_) =>
            const AlertDialog(content: TextField(key: Key('dialog-field'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(borderOf(tester, 'dialog-field'), isA<OutlineInputBorder>());
  });

  testAppWidgets('nothing is read while the app is locked', (tester) async {
    await pumpField(tester, open: false);
    expect(borderOf(tester, 'page-field'), isNot(isA<OutlineInputBorder>()));
  });

  testAppWidgets('Profile: Look sets the text fields for every space', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
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
    await tester.ensureVisible(find.byKey(const Key('look-theme-dark')));
    await tester.tap(find.byKey(const Key('look-theme-dark')));
    await settleFrames(tester);
    expect(find.text('Dark theme · boxed fields'), findsOneWidget);
    final c = ProviderScope.containerOf(
      tester.element(find.byType(ProfileScreen)),
    );
    final saved = await tester.runAsync(
      () => c.read(lookSettingsProvider.future),
    );
    expect(saved!.fields, FieldStyle.boxed);
    expect(saved.theme, ThemeChoice.dark);
  });
}
