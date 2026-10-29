import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/semantic_ids.dart';
import '../../../theme/pesa_colors.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../data/sms_source.dart';

/// The Shortcuts automation that passes messages to the app on iPhone.
final shortcutConnectionProvider = Provider<ShortcutConnection>(
  (ref) => const ShortcutSmsSource(),
);

/// When the automation last passed a message, or null before the first.
final lastShortcutMessageProvider = FutureProvider.autoDispose<DateTime?>(
  (ref) => ref.watch(shortcutConnectionProvider).lastArrival(),
);

/// `just now`, `12 min ago`, `today, 08:10`, `Yesterday, 21:05` or
/// `Fri 23 Oct`.
String arrivalLabel(DateTime at, DateTime now) {
  final since = now.difference(at);
  if (since < const Duration(minutes: 1)) return 'just now';
  if (since < const Duration(hours: 1)) return '${since.inMinutes} min ago';
  final day = CalendarDate.local(at);
  final today = CalendarDate.local(now);
  if (day == today) return 'today, ${formatTime(at)}';
  if (day == today.addDays(-1)) return 'yesterday, ${formatTime(at)}';
  return dayHeading(day, today: today);
}

/// iPhone: how to set up the Shortcuts automation that passes each M-Pesa or
/// bank message to the app, and whether messages are arriving. Shown in
/// onboarding in place of the SMS scan, and from Profile.
class ConnectMessagesScreen extends ConsumerStatefulWidget {
  const ConnectMessagesScreen({this.onboarding = false, super.key});

  /// Whether this is the onboarding step, which ends onboarding when left.
  final bool onboarding;

  @override
  ConsumerState<ConnectMessagesScreen> createState() =>
      _ConnectMessagesScreenState();
}

class _ConnectMessagesScreenState extends ConsumerState<ConnectMessagesScreen> {
  late final AppLifecycleListener _lifecycle;

  static const _steps = [
    ('Open Shortcuts, then Automation', 'Tap + and choose Message.'),
    ('Pick the senders', 'MPESA and your bank, then Run Immediately.'),
    (
      'Add "Add transaction from message"',
      'Pass it the message content and sender. Done.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Coming back from Shortcuts: check whether a message has arrived.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(lastShortcutMessageProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _finish() => ref.read(onboardingControllerProvider.notifier).complete();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final last = ref.watch(lastShortcutMessageProvider).value;
    final now = ref.watch(clockProvider)();
    final connected = last != null;

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleConnectMessages,
          child: const Text('Your messages'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text('Connect your messages', style: theme.textTheme.headlineLarge),
            const SizedBox(height: 8),
            Text(
              'A Shortcuts automation sends each M-Pesa or bank message to '
              'Pesa Clarity as it arrives. It stays on this iPhone.',
              style: theme.textTheme.bodyLarge!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            _Status(
              key: const Key('connect-status'),
              title: connected ? 'Connected' : 'Waiting for your first message',
              detail: connected
                  ? 'Last message ${arrivalLabel(last, now)}'
                  : 'Set up the automation below, once.',
              connected: connected,
            ),
            GroupedSection(
              header: 'Three steps, once',
              footer: 'For past months, import a statement from Profile.',
              children: [
                for (final (i, (title, detail)) in _steps.indexed)
                  ListTile(
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.titleSmall!.copyWith(
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                    title: Text(title),
                    subtitle: Text(detail),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            if (widget.onboarding && connected)
              FilledButton(onPressed: _finish, child: const Text('Continue'))
            else
              FilledButton(
                key: const Key('connect-open-shortcuts'),
                onPressed: ref.read(shortcutConnectionProvider).openShortcuts,
                child: const Text('Open Shortcuts'),
              ),
            if (widget.onboarding && !connected) ...[
              const SizedBox(height: 8),
              Semantics(
                identifier: SemanticIds.smsScanNotNow,
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('Do this later'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.title,
    required this.detail,
    required this.connected,
    super.key,
  });

  final String title;
  final String detail;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final tone = connected ? colors.successText : colors.textMuted;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Card(
        color: connected ? colors.success.withValues(alpha: 0.12) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                connected ? Icons.check_circle : Icons.schedule,
                size: 20,
                color: tone,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium!.copyWith(color: tone),
                    ),
                    Text(
                      detail,
                      style: theme.textTheme.bodyMedium!.copyWith(color: tone),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
