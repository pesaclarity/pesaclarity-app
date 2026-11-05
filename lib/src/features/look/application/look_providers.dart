import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/app_settings_repository.dart';
import '../../../domain/look/look_settings.dart';

/// How the app looks, kept with the app-wide settings so every space shares
/// it.
class LookSettingsController extends AsyncNotifier<LookSettings> {
  static const settingsKey = 'look.settings';

  @override
  Future<LookSettings> build() async => LookSettings.fromJson(
    await ref.watch(mainSettingsRepositoryProvider).readJson(settingsKey),
  );

  Future<void> save(LookSettings next) async {
    await ref
        .read(mainSettingsRepositoryProvider)
        .writeJson(settingsKey, next.toJson());
    state = AsyncData(next);
  }
}

/// The app's [ThemeMode] for [choice].
ThemeMode themeModeFor(ThemeChoice choice) => switch (choice) {
  ThemeChoice.system => ThemeMode.system,
  ThemeChoice.light => ThemeMode.light,
  ThemeChoice.dark => ThemeMode.dark,
};

final lookSettingsProvider =
    AsyncNotifierProvider<LookSettingsController, LookSettings>(
      LookSettingsController.new,
    );
