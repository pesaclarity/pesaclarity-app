import 'dart:async';

import 'package:pesaclarity/src/features/sms/data/notification_source.dart';
import 'package:ujumbe/ujumbe.dart';

/// The phone's notification reader, in memory: keeps messages from watched
/// senders as the platform side does, and records what was asked of it.
class FakeNotificationSource implements NotificationSource {
  FakeNotificationSource({this.current = NotificationAccess.granted});

  NotificationAccess current;
  Set<String> watched = const {};
  final watchedHistory = <Set<String>>[];
  int settingsOpened = 0;
  final _waiting = <SmsMessage>[];
  final _arrivals = StreamController<void>.broadcast();

  /// Shows [message] as a notification; kept only if its sender is watched.
  void post(SmsMessage message) {
    final normalised = watched.map(SenderFilter.normalise).toSet();
    if (!normalised.contains(SenderFilter.normalise(message.sender))) return;
    _waiting.add(message);
    _arrivals.add(null);
  }

  Future<void> close() => _arrivals.close();

  @override
  Future<NotificationAccess> access() async => current;

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<void> setWatched(Set<String> senders) async {
    watched = senders;
    watchedHistory.add(senders);
    if (senders.isEmpty) _waiting.clear();
  }

  @override
  Future<List<SmsMessage>> drain() async {
    final out = [..._waiting];
    _waiting.clear();
    return out;
  }

  @override
  Stream<void> arrivals() => _arrivals.stream;
}
