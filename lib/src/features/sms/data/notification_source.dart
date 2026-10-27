import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ujumbe/ujumbe.dart';

/// Whether the person has let the app read notifications.
enum NotificationAccess {
  granted,
  denied,

  /// This platform has no notification access to give.
  unavailable,
}

/// Money messages read from other apps' notifications, such as the messages
/// app showing an M-Pesa SMS. The phone keeps only those from watched
/// senders, encrypted, until [drain] takes them.
abstract interface class NotificationSource {
  Future<NotificationAccess> access();

  /// Opens the phone's notification access page for this app.
  Future<void> openSettings();

  /// The senders to keep. An empty set stops reading and clears the queue.
  Future<void> setWatched(Set<String> senders);

  /// Every message read since the last drain, oldest first.
  Future<List<SmsMessage>> drain();

  /// Fires when a new message is waiting, while listened to.
  Stream<void> arrivals();
}

/// [NotificationSource] backed by `NotificationsChannel.kt`.
class PlatformNotificationSource implements NotificationSource {
  const PlatformNotificationSource();

  static const _methods = MethodChannel('com.pesaclarity.app/notifications');
  static const _events = EventChannel(
    'com.pesaclarity.app/notifications/arrivals',
  );

  @override
  Future<NotificationAccess> access() async {
    try {
      final name = await _methods.invokeMethod<String>('access');
      return NotificationAccess.values.asNameMap()[name] ??
          NotificationAccess.denied;
    } on MissingPluginException {
      return NotificationAccess.unavailable;
    }
  }

  @override
  Future<void> openSettings() => _methods.invokeMethod<void>('openSettings');

  @override
  Future<void> setWatched(Set<String> senders) async {
    try {
      await _methods.invokeMethod<void>('setWatched', {
        'senders': senders.toList(),
      });
    } on MissingPluginException {
      // Nothing to stop on a platform without notification access.
    }
  }

  @override
  Future<List<SmsMessage>> drain() async {
    final rows = await _methods.invokeListMethod<Map<Object?, Object?>>(
      'drain',
    );
    return [
      for (final row in rows ?? const <Map<Object?, Object?>>[])
        SmsMessage(
          sender: row['sender']! as String,
          body: row['body']! as String,
          receivedAt: DateTime.fromMillisecondsSinceEpoch(
            row['receivedAtMillis']! as int,
            isUtc: true,
          ),
        ),
    ];
  }

  @override
  Stream<void> arrivals() => _events.receiveBroadcastStream();
}

final notificationSourceProvider = Provider<NotificationSource>(
  (ref) => const PlatformNotificationSource(),
);
