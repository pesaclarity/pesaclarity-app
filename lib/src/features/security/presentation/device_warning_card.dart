import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/pesa_colors.dart';
import '../application/device_integrity_providers.dart';

/// A one-time notice in Profile when the phone looks rooted or the build
/// looks modified. It informs only; the app works the same either way.
class DeviceWarningCard extends ConsumerWidget {
  const DeviceWarningCard({super.key});

  static const title = 'This phone may be modified';
  static const body =
      'It looks rooted or runs a test version of Android. Apps with full '
      'access to a phone can read other apps\' data. Pesa Clarity keeps '
      'working, and app lock adds protection.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(showDeviceWarningProvider).value ?? false;
    if (!show) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = PesaColors.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, color: colors.warning),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          body,
                          style: theme.textTheme.bodyMedium!.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    await ref.read(deviceWarningRepositoryProvider).dismiss();
                    ref.invalidate(showDeviceWarningProvider);
                  },
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
