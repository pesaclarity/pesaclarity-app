import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/app_settings_repository.dart';
import '../data/notification_source.dart';
import 'sms_capture_providers.dart';
import 'sms_ingestor.dart';

/// Whether the person turned on reading money notifications.
class NotificationCaptureController extends AsyncNotifier<bool> {
  static const settingsKey = 'notification_capture.settings';

  @override
  Future<bool> build() async {
    final json = await ref
        .read(appSettingsRepositoryProvider)
        .readJson(settingsKey);
    return json?['enabled'] == true;
  }

  Future<void> setEnabled(bool enabled) async {
    await ref.read(appSettingsRepositoryProvider).writeJson(settingsKey, {
      'enabled': enabled,
    });
    state = AsyncData(enabled);
  }
}

final notificationCaptureEnabledProvider =
    AsyncNotifierProvider<NotificationCaptureController, bool>(
      NotificationCaptureController.new,
    );

/// Whether the phone lets the app read notifications. Refresh it after the
/// person comes back from the phone's settings.
final notificationAccessProvider = FutureProvider<NotificationAccess>(
  (ref) => ref.watch(notificationSourceProvider).access(),
);

/// Adds money messages read from notifications while the app runs: first
/// those that arrived while it was closed, then each as it lands.
///
/// Notification text can be cut short, so a message no rule reads is
/// dropped rather than kept for review; SMS access covers that case.
final liveNotificationCaptureProvider = StreamProvider<SmsIngestSummary>((
  ref,
) async* {
  final selected = ref.watch(selectedInstitutionsProvider);
  final source = ref.watch(notificationSourceProvider);
  final enabled = await ref.watch(notificationCaptureEnabledProvider.future);
  final access = await ref.watch(notificationAccessProvider.future);
  if (access == NotificationAccess.unavailable) return;

  final senders = {for (final i in selected) ...i.senderIds};
  if (!enabled || senders.isEmpty || access != NotificationAccess.granted) {
    await source.setWatched(const {});
    return;
  }
  await source.setWatched(senders);

  final ingestor = ref.watch(smsIngestorProvider);
  Future<SmsIngestSummary> ingestWaiting() async =>
      ingestor.ingest(await source.drain(), selected, reviewUnmatched: false);

  yield await ingestWaiting();
  await for (final _ in source.arrivals()) {
    yield await ingestWaiting();
  }
});
