import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/pesa_colors.dart';
import '../application/notification_capture.dart';
import '../application/sms_capture_providers.dart';
import '../data/notification_source.dart';

/// Profile › Read from notifications: reads money messages from the
/// notifications other apps show, for phones without SMS access.
class NotificationCaptureScreen extends ConsumerStatefulWidget {
  const NotificationCaptureScreen({super.key});

  @override
  ConsumerState<NotificationCaptureScreen> createState() =>
      _NotificationCaptureScreenState();
}

class _NotificationCaptureScreenState
    extends ConsumerState<NotificationCaptureScreen> {
  // Access changes in the phone's settings, so check again on return.
  late final _lifecycle = AppLifecycleListener(
    onResume: () => ref.invalidate(notificationAccessProvider),
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _turnOn() async {
    await ref
        .read(notificationCaptureEnabledProvider.notifier)
        .setEnabled(true);
    final access = await ref.read(notificationAccessProvider.future);
    if (access != NotificationAccess.granted) {
      await ref.read(notificationSourceProvider).openSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(notificationCaptureEnabledProvider).value;
    final access = ref.watch(notificationAccessProvider).value;
    final granted = access == NotificationAccess.granted;
    final names = [
      for (final i in ref.watch(selectedInstitutionsProvider)) i.name,
    ];
    final colors = PesaColors.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Read from notifications')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'Your messages app shows each money message as a notification. '
            'Pesa Clarity can read those, so your spending stays up to date.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                _Point(
                  title: 'Only the senders you chose',
                  detail: names.isEmpty
                      ? 'Pick them in My accounts.'
                      : '${joinNames(names)}. Everything else is left alone.',
                ),
                const Divider(height: 1),
                const _Point(
                  title: 'Stays on this phone',
                  detail: 'Read here, kept encrypted, sent nowhere.',
                ),
                const Divider(height: 1),
                const _Point(
                  title: 'Works with SMS access',
                  detail: 'Each message is counted once.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  key: const Key('notification-capture-switch'),
                  title: const Text('Read money notifications'),
                  subtitle: Text(
                    switch ((enabled ?? false, granted)) {
                      (true, true) => 'On',
                      (true, false) => 'Allow access in phone settings',
                      _ => 'Off',
                    },
                    style: enabled == true && granted
                        ? TextStyle(color: colors.successText)
                        : null,
                  ),
                  value: (enabled ?? false) && granted,
                  onChanged: enabled == null || access == null
                      ? null
                      : (on) => on
                            ? _turnOn()
                            : ref
                                  .read(
                                    notificationCaptureEnabledProvider.notifier,
                                  )
                                  .setEnabled(false),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Notification access'),
                  trailing: const Text('Phone settings'),
                  onTap: () =>
                      ref.read(notificationSourceProvider).openSettings(),
                ),
              ],
            ),
          ),
          if (access != null && !granted) ...[
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _turnOn,
              child: const Text('Turn on in settings'),
            ),
          ],
        ],
      ),
    );
  }
}

/// "M-Pesa", "M-Pesa and KCB", "M-Pesa, I&M and KCB".
String joinNames(List<String> names) => switch (names) {
  [] => '',
  [final only] => only,
  [...final rest, final last] => '${rest.join(', ')} and $last',
};

class _Point extends StatelessWidget {
  const _Point({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(Icons.check, color: PesaColors.of(context).successText),
    title: Text(title),
    subtitle: Text(detail),
  );
}
