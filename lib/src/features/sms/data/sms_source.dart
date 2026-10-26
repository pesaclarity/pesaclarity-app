import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ujumbe/ujumbe.dart';

/// Whether the app may read SMS.
enum SmsAccess {
  granted,

  /// Refused, but the app may ask again.
  denied,

  /// Refused for good; only the phone's settings can grant it now.
  blocked,

  /// This platform has no SMS inbox the app can read.
  unavailable,
}

/// The phone's SMS inbox and incoming messages, limited to given senders.
abstract interface class SmsSource {
  Future<SmsAccess> access();

  /// Shows the system permission dialog, unless access is already granted.
  Future<SmsAccess> requestAccess();

  /// Opens the app's page in the phone's settings.
  Future<void> openSettings();

  /// Inbox messages from [senders] received at or after [since], oldest
  /// first. Messages from any other sender are never read.
  Future<List<SmsMessage>> readInbox({
    required Set<String> senders,
    required DateTime since,
  });

  /// Messages from [senders] as they arrive, while listened to.
  Stream<SmsMessage> incoming(Set<String> senders);
}

/// [SmsSource] backed by the Android platform channel in `SmsChannel.kt`.
class PlatformSmsSource implements SmsSource {
  const PlatformSmsSource();

  static const _methods = MethodChannel('com.pesaclarity.app/sms');
  static const _events = EventChannel('com.pesaclarity.app/sms/incoming');

  @override
  Future<SmsAccess> access() => _accessCall('access');

  @override
  Future<SmsAccess> requestAccess() => _accessCall('requestAccess');

  Future<SmsAccess> _accessCall(String method) async {
    try {
      final name = await _methods.invokeMethod<String>(method);
      return SmsAccess.values.asNameMap()[name] ?? SmsAccess.denied;
    } on MissingPluginException {
      return SmsAccess.unavailable;
    }
  }

  @override
  Future<void> openSettings() => _methods.invokeMethod<void>('openSettings');

  @override
  Future<List<SmsMessage>> readInbox({
    required Set<String> senders,
    required DateTime since,
  }) async {
    if (senders.isEmpty) return const [];
    final rows = await _methods.invokeListMethod<Map<Object?, Object?>>(
      'readInbox',
      {
        'senders': senders.toList(),
        'sinceMillis': since.millisecondsSinceEpoch,
      },
    );
    return [
      for (final row in rows ?? const <Map<Object?, Object?>>[]) _fromMap(row),
    ];
  }

  @override
  Stream<SmsMessage> incoming(Set<String> senders) => senders.isEmpty
      ? const Stream.empty()
      : _events
            .receiveBroadcastStream(senders.toList())
            .map((event) => _fromMap(event as Map<Object?, Object?>));

  static SmsMessage _fromMap(Map<Object?, Object?> map) => SmsMessage(
    sender: map['sender']! as String,
    body: map['body']! as String,
    receivedAt: DateTime.fromMillisecondsSinceEpoch(
      map['receivedAtMillis']! as int,
      isUtc: true,
    ),
  );
}

final smsSourceProvider = Provider<SmsSource>(
  (ref) => const PlatformSmsSource(),
);
