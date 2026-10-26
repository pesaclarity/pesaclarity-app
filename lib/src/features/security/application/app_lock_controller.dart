import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/database_providers.dart';
import '../data/biometric_authenticator.dart';
import '../data/key_vault.dart';
import '../data/secure_store.dart';
import '../domain/lock_settings.dart';
import '../domain/unlock_delay.dart';
import 'balance_visibility.dart';

enum LockStatus {
  /// Reading lock settings; nothing from the database is shown yet.
  loading,

  /// A PIN is set and the person has not unlocked yet.
  locked,

  /// The database key is released.
  unlocked,

  /// Lock settings could not be read.
  failed,
}

/// What the app lock knows right now. The key itself is never part of it.
final class AppLockState {
  const AppLockState({
    required this.status,
    this.settings = const LockSettings(),
    this.attempts = const PinAttempts(),
    this.keyReleased = false,
  });

  final LockStatus status;
  final LockSettings settings;
  final PinAttempts attempts;

  /// Whether the database key has been released since the app started. It
  /// stays true when the app locks again on return from the background.
  final bool keyReleased;

  AppLockState copyWith({
    LockStatus? status,
    LockSettings? settings,
    PinAttempts? attempts,
    bool? keyReleased,
  }) => AppLockState(
    status: status ?? this.status,
    settings: settings ?? this.settings,
    attempts: attempts ?? this.attempts,
    keyReleased: keyReleased ?? this.keyReleased,
  );
}

/// The outcome of a PIN try.
enum PinCheck { correct, wrong, waiting }

/// Locks and unlocks the app, and releases the database key on unlock.
class AppLockController extends Notifier<AppLockState> {
  String? _key;
  DateTime? _backgroundedAt;

  KeyVault get _vault => ref.read(keyVaultProvider);
  DateTime _now() => ref.read(clockProvider)();

  @override
  AppLockState build() {
    final listener = AppLifecycleListener(onStateChange: _onLifecycle);
    ref.onDispose(listener.dispose);
    unawaited(_load());
    return const AppLockState(status: LockStatus.loading);
  }

  /// Reads the lock settings again after a failure.
  Future<void> retry() async {
    state = const AppLockState(status: LockStatus.loading);
    await _load();
  }

  Future<void> _load() async {
    try {
      final settings = await _vault.readSettings();
      final attempts = await _vault.readAttempts();
      if (settings.pinSet) {
        state = AppLockState(
          status: LockStatus.locked,
          settings: settings,
          attempts: attempts,
        );
        return;
      }
      final key = await _vault.readOrCreateOpenKey();
      _release(key, settings);
      state = AppLockState(
        status: LockStatus.unlocked,
        settings: settings,
        keyReleased: true,
      );
    } catch (error, stack) {
      debugPrint('App lock settings could not be read: $error\n$stack');
      state = const AppLockState(status: LockStatus.failed);
    }
  }

  void _release(String key, LockSettings settings) {
    _key = key;
    ref.read(releasedDatabaseKeyProvider).release(key);
    ref.read(balancesHiddenProvider.notifier).set(settings.hideBalancesOnOpen);
  }

  /// When the next PIN try is allowed, or null if it is allowed now.
  DateTime? get retryAt {
    final at = state.attempts.retryAt;
    return at != null && at.isAfter(_now()) ? at : null;
  }

  /// Checks [pin], counting wrong tries toward the growing wait.
  ///
  /// Unlocks the app when it is locked and the PIN is right.
  Future<PinCheck> enterPin(String pin) async {
    if (retryAt != null) return PinCheck.waiting;
    final key = await _vault.unlockWithPin(pin);
    if (key == null) {
      final failed = state.attempts.failed + 1;
      final delay = unlockDelayAfter(failed);
      final attempts = PinAttempts(
        failed: failed,
        retryAt: delay == Duration.zero ? null : _now().add(delay),
      );
      await _vault.writeAttempts(attempts);
      state = state.copyWith(attempts: attempts);
      return PinCheck.wrong;
    }
    await _vault.clearAttempts();
    if (state.status == LockStatus.locked) _release(key, state.settings);
    state = state.copyWith(
      status: LockStatus.unlocked,
      attempts: const PinAttempts(),
      keyReleased: true,
    );
    return PinCheck.correct;
  }

  /// Shows the biometric prompt if fingerprint unlock is on; true on unlock.
  Future<bool> unlockWithBiometric() async {
    if (state.status != LockStatus.locked) return false;
    if (!state.settings.biometricEnabled) return false;
    if (!await ref.read(biometricAuthenticatorProvider).authenticate()) {
      return false;
    }
    final key = await _vault.readBiometricKey();
    if (key == null || state.status != LockStatus.locked) return false;
    await _vault.clearAttempts();
    _release(key, state.settings);
    state = state.copyWith(
      status: LockStatus.unlocked,
      attempts: const PinAttempts(),
      keyReleased: true,
    );
    return true;
  }

  /// Turns the lock on with [pin], or changes the PIN if it is already on.
  Future<void> setPin(String pin) async {
    await _vault.setPin(pin, _requireKey());
    await _saveSettings(state.settings.copyWith(pinSet: true));
    state = state.copyWith(attempts: const PinAttempts());
  }

  /// Turns the lock off. Call after the person confirms their PIN.
  Future<void> removePin() async {
    await _vault.removePin(_requireKey());
    await _saveSettings(
      state.settings.copyWith(pinSet: false, biometricEnabled: false),
    );
  }

  /// Turns fingerprint unlock on or off. Turning it on asks for a
  /// fingerprint first; returns whether the setting changed.
  Future<bool> setBiometricEnabled(bool enabled) async {
    if (enabled) {
      if (!state.settings.pinSet) return false;
      if (!await ref.read(biometricAuthenticatorProvider).authenticate()) {
        return false;
      }
      await _vault.enableBiometric(_requireKey());
    } else {
      await _vault.disableBiometric();
    }
    await _saveSettings(state.settings.copyWith(biometricEnabled: enabled));
    return true;
  }

  Future<void> setLockAfter(Duration lockAfter) =>
      _saveSettings(state.settings.copyWith(lockAfter: lockAfter));

  Future<void> setHideBalancesOnOpen(bool hide) async {
    await _saveSettings(state.settings.copyWith(hideBalancesOnOpen: hide));
    ref.read(balancesHiddenProvider.notifier).set(hide);
  }

  Future<void> _saveSettings(LockSettings settings) async {
    await _vault.writeSettings(settings);
    state = state.copyWith(settings: settings);
  }

  String _requireKey() {
    final key = _key;
    if (key == null || state.status != LockStatus.unlocked) {
      throw StateError('Unlock the app first');
    }
    return key;
  }

  void _onLifecycle(AppLifecycleState lifecycle) {
    switch (lifecycle) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _backgroundedAt ??= _now();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null) _onReturn(_now().difference(since));
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  void _onReturn(Duration away) {
    if (state.status != LockStatus.unlocked) return;
    final settings = state.settings;
    if (away < settings.lockAfter) return;
    ref.read(balancesHiddenProvider.notifier).set(settings.hideBalancesOnOpen);
    if (settings.pinSet) state = state.copyWith(status: LockStatus.locked);
  }
}

final keyVaultProvider = Provider<KeyVault>(
  (ref) => KeyVault(ref.watch(secureStoreProvider)),
);

final appLockControllerProvider =
    NotifierProvider<AppLockController, AppLockState>(AppLockController.new);
