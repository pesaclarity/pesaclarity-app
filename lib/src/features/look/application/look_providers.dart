import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/app_settings_repository.dart';
import '../../../domain/look/look_settings.dart';
import '../../security/application/app_lock_controller.dart';
import '../../security/data/secure_store.dart';

/// Where a copy of the look is kept for before unlock: the lock's own store,
/// which the lock screen can read. The look is not sensitive.
const lookStartupKey = 'look.settings';

/// The copy of the look kept for before unlock; the usual look when there is
/// none or it cannot be read.
Future<LookSettings> readStartupLook(SecureStore store) async {
  try {
    final raw = await store.read(lookStartupKey);
    if (raw == null) return const LookSettings();
    final json = jsonDecode(raw);
    return LookSettings.fromJson(json is Map<String, Object?> ? json : null);
  } on Object {
    return const LookSettings();
  }
}

/// The look read before the first frame, so the lock screen and setup use
/// it; `main` overrides it.
final startupLookProvider = Provider<LookSettings>(
  (ref) => const LookSettings(),
);

/// How the app looks. Before unlock it is the copy kept with the lock; once
/// the database key is released, the encrypted settings in Personal are the
/// source of truth, and the copy is brought in line with them.
class LookSettingsController extends AsyncNotifier<LookSettings> {
  static const settingsKey = 'look.settings';

  @override
  Future<LookSettings> build() async {
    final released = ref.watch(
      appLockControllerProvider.select((s) => s.keyReleased),
    );
    // Opening the database while it is locked would fail for the session.
    if (!released) return ref.watch(startupLookProvider);
    final saved = LookSettings.fromJson(
      await ref.watch(mainSettingsRepositoryProvider).readJson(settingsKey),
    );
    final early = await readStartupLook(ref.read(secureStoreProvider));
    if (jsonEncode(early.toJson()) != jsonEncode(saved.toJson())) {
      await _keepEarlyCopy(saved);
    }
    return saved;
  }

  Future<void> save(LookSettings next) async {
    await ref
        .read(mainSettingsRepositoryProvider)
        .writeJson(settingsKey, next.toJson());
    await _keepEarlyCopy(next);
    state = AsyncData(next);
  }

  /// The copy for before unlock is a convenience: a failed write leaves the
  /// lock screen on the last copy until the next save or unlock.
  Future<void> _keepEarlyCopy(LookSettings look) async {
    try {
      await ref
          .read(secureStoreProvider)
          .write(lookStartupKey, jsonEncode(look.toJson()));
    } on Object {
      // Kept in the database either way.
    }
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

/// The look to draw now: the saved one, or before it is read, the copy from
/// startup, so the first frame already has it.
final currentLookProvider = Provider<LookSettings>(
  (ref) =>
      ref.watch(lookSettingsProvider).value ?? ref.watch(startupLookProvider),
);
