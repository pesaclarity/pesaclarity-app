import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../theme/pesa_colors.dart';
import '../application/app_lock_controller.dart';
import '../domain/unlock_delay.dart';
import 'pin_pad.dart';

/// Asks for the PIN, or a fingerprint, before anything else shows.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  Timer? _ticker;
  bool _wrong = false;
  bool _waiting = true;

  @override
  void initState() {
    super.initState();
    // Rebuilds each second while a wait runs, and once more when it ends.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final waiting =
          ref.read(appLockControllerProvider.notifier).retryAt != null;
      if (waiting || _waiting) setState(() => _waiting = waiting);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    if (!mounted) return;
    await ref.read(appLockControllerProvider.notifier).unlockWithBiometric();
  }

  Future<void> _onPin(String pin) async {
    final result = await ref
        .read(appLockControllerProvider.notifier)
        .enterPin(pin);
    if (mounted) setState(() => _wrong = result != PinCheck.correct);
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockControllerProvider);
    final controller = ref.read(appLockControllerProvider.notifier);
    final retryAt = controller.retryAt;
    final colors = PesaColors.of(context);

    final String? message;
    if (retryAt != null) {
      final now = ref.read(clockProvider)();
      message =
          'Too many wrong PINs. Try again in '
          '${_countdown(retryAt.difference(now))}.';
    } else if (_wrong) {
      final left = freePinAttempts - lock.attempts.failed;
      message = left > 0
          ? 'Wrong PIN. $left ${left == 1 ? 'try' : 'tries'} left before a wait.'
          : 'Wrong PIN.';
    } else {
      message = null;
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                PinPad(
                  title: 'Enter your PIN',
                  message: message,
                  messageIsError: message != null,
                  enabled: retryAt == null,
                  onCompleted: _onPin,
                  extraKey: lock.settings.biometricEnabled
                      ? IconButton(
                          tooltip: 'Use fingerprint',
                          onPressed: _tryBiometric,
                          icon: const Icon(Icons.fingerprint, size: 32),
                        )
                      : null,
                  footer: Text(
                    'Forgot your PIN? Reinstall the app and restore '
                    'from your backup.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall!
                        .copyWith(color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _countdown(Duration left) {
  final seconds = left.inSeconds + (left.inMilliseconds % 1000 > 0 ? 1 : 0);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Covers the app with [LockScreen] while locked, keeping the screens
/// underneath in place for when the person unlocks.
class AppLockGate extends ConsumerWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      appLockControllerProvider.select((state) => state.status),
    );
    return switch (status) {
      LockStatus.loading || LockStatus.unlocked => child,
      LockStatus.locked => Stack(
        children: [
          Offstage(child: TickerMode(enabled: false, child: child)),
          const _LockOverlay(),
        ],
      ),
      LockStatus.failed => const _LockFailedScreen(),
    };
  }
}

/// Gives [LockScreen] its own overlay, since it sits above the router's
/// navigator; tooltips and ink need one.
class _LockOverlay extends StatefulWidget {
  const _LockOverlay();

  @override
  State<_LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends State<_LockOverlay> {
  final _entry = OverlayEntry(builder: (_) => const LockScreen());

  @override
  void dispose() {
    _entry
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}

class _LockFailedScreen extends ConsumerWidget {
  const _LockFailedScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pesa Clarity could not open its secure storage.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      ref.read(appLockControllerProvider.notifier).retry(),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
