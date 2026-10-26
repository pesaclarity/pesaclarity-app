import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hands a prefilled message to another app, such as WhatsApp, through the
/// Android share sheet. The person picks the app and sends it themselves.
abstract interface class ReminderSharer {
  Future<void> share(String message);
}

class PlatformReminderSharer implements ReminderSharer {
  const PlatformReminderSharer();

  static const _channel = MethodChannel('com.pesaclarity.app/share');

  @override
  Future<void> share(String message) =>
      _channel.invokeMethod<void>('shareText', {'text': message});
}

final reminderSharerProvider = Provider<ReminderSharer>(
  (ref) => const PlatformReminderSharer(),
);
