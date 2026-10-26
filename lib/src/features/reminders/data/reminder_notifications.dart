import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../domain/reminders/reminder_schedule.dart';

/// Shows reminders as local notifications on this phone.
abstract interface class ReminderNotifications {
  /// Asks for permission to post notifications where the system needs it
  /// (Android 13 and later). Returns whether notifications may be shown.
  Future<bool> requestPermission();

  /// Cancels every scheduled reminder and schedules [reminders] instead.
  Future<void> replaceAll(List<Reminder> reminders);

  Future<void> cancelAll();
}

/// [ReminderNotifications] on flutter_local_notifications, with inexact
/// alarms, so no exact-alarm permission is needed. Does nothing off Android.
class LocalReminderNotifications implements ReminderNotifications {
  LocalReminderNotifications([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _icon = 'ic_stat_reminder';
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Bills, card charges, payday and safe-to-spend',
      icon: _icon,
    ),
  );

  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _ready;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> _initialise() => _ready ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_icon),
        ),
      )
      .then((ok) => ok ?? false);

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    await _initialise();
    return await _android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    if (!_supported) return;
    await _initialise();
    await _plugin.cancelAllPendingNotifications();
    for (final reminder in reminders) {
      await _plugin.zonedSchedule(
        id: reminder.id,
        scheduledDate: tz.TZDateTime.from(reminder.at, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: reminder.title,
        body: reminder.body,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_supported) return;
    await _initialise();
    await _plugin.cancelAllPendingNotifications();
  }
}

final reminderNotificationsProvider = Provider<ReminderNotifications>(
  (ref) => LocalReminderNotifications(),
);
