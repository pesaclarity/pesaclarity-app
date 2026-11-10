import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../application/app_lock_controller.dart';
import '../data/biometric_authenticator.dart';
import '../domain/lock_settings.dart';
import 'pin_entry_screens.dart';

/// The Security section of Profile: app lock, fingerprint unlock, when to
/// lock, and hiding balances.
class SecuritySettingsCard extends ConsumerWidget {
  const SecuritySettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(
      appLockControllerProvider.select((state) => state.settings),
    );
    final controller = ref.read(appLockControllerProvider.notifier);
    final biometricAvailable =
        ref.watch(biometricAvailableProvider).value ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Security'),
        Card(
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: const Text('App lock'),
                subtitle: Text(
                  settings.pinSet
                      ? 'Asks for your PIN to open the app'
                      : 'Set a PIN to open the app',
                ),
                value: settings.pinSet,
                onChanged: (on) =>
                    on ? _turnOn(context, ref) : _turnOff(context, ref),
              ),
              if (settings.pinSet) ...[
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  title: const Text('Fingerprint unlock'),
                  subtitle: biometricAvailable
                      ? null
                      : const Text('Add a fingerprint in phone settings first'),
                  value: settings.biometricEnabled,
                  onChanged: biometricAvailable || settings.biometricEnabled
                      ? controller.setBiometricEnabled
                      : null,
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Lock after'),
                  trailing: ChoiceMenu<Duration>(
                    key: const Key('lock-after'),
                    name: 'Lock after',
                    options: [
                      for (final option in LockSettings.lockAfterChoices)
                        (option, lockAfterLabel(option)),
                    ],
                    value: settings.lockAfter,
                    onChanged: controller.setLockAfter,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Change PIN'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _changePin(context, ref),
                ),
              ],
              const Divider(height: 1),
              SwitchListTile.adaptive(
                title: const Text('Hide balances on open'),
                subtitle: const Text(
                  'Tap the eye on any screen to show or hide them. Selling '
                  'and forms always show amounts.',
                ),
                value: settings.hideBalancesOnOpen,
                onChanged: controller.setHideBalancesOnOpen,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _turnOn(BuildContext context, WidgetRef ref) async {
    final pin = await _push<String>(context, const ChoosePinScreen());
    if (pin == null) return;
    await ref.read(appLockControllerProvider.notifier).setPin(pin);
    if (context.mounted) showNote(context, 'App lock is on.');
  }

  Future<void> _turnOff(BuildContext context, WidgetRef ref) async {
    final confirmed = await _push<bool>(context, const ConfirmPinScreen());
    if (confirmed != true) return;
    await ref.read(appLockControllerProvider.notifier).removePin();
    if (context.mounted) showNote(context, 'App lock is off.');
  }

  Future<void> _changePin(BuildContext context, WidgetRef ref) async {
    final confirmed = await _push<bool>(context, const ConfirmPinScreen());
    if (confirmed != true || !context.mounted) return;
    final pin = await _push<String>(context, const ChoosePinScreen());
    if (pin == null) return;
    await ref.read(appLockControllerProvider.notifier).setPin(pin);
    if (context.mounted) showNote(context, 'PIN changed.');
  }

  Future<T?> _push<T>(BuildContext context, Widget screen) => Navigator.of(
    context,
    rootNavigator: true,
  ).push<T>(MaterialPageRoute(builder: (_) => screen, fullscreenDialog: true));
}
