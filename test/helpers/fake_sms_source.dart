import 'dart:async';

import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:ujumbe/ujumbe.dart';

/// An in-memory phone inbox. Applies the same sender and date filter as the
/// platform channel, and records what was asked of it.
class FakeSmsSource implements SmsSource {
  FakeSmsSource({
    List<SmsMessage> inbox = const [],
    this.dialogAnswer = SmsAccess.granted,
    SmsAccess? current,
  }) : inbox = [...inbox],
       current = current ?? dialogAnswer;

  final List<SmsMessage> inbox;

  /// What the permission dialog answers.
  SmsAccess dialogAnswer;

  /// The access the app has now, as set in the phone's settings.
  SmsAccess current;

  final reads = <({Set<String> senders, DateTime since})>[];
  final listenedSenders = <Set<String>>[];
  int permissionRequests = 0;
  int settingsOpened = 0;

  final _incoming = StreamController<SmsMessage>.broadcast();

  /// Delivers [message] as if it just arrived, to watched listeners only.
  void receive(SmsMessage message) {
    inbox.add(message);
    _incoming.add(message);
  }

  @override
  Future<SmsAccess> access() async => current;

  @override
  Future<SmsAccess> requestAccess() async {
    permissionRequests++;
    if (current != SmsAccess.granted) current = dialogAnswer;
    return current;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<List<SmsMessage>> readInbox({
    required Set<String> senders,
    required DateTime since,
  }) async {
    reads.add((senders: senders, since: since));
    final watched = senders.map(SenderFilter.normalise).toSet();
    return [
      for (final m in inbox)
        if (watched.contains(SenderFilter.normalise(m.sender)) &&
            !m.receivedAt.isBefore(since))
          m,
    ]..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
  }

  @override
  Stream<SmsMessage> incoming(Set<String> senders) {
    listenedSenders.add(senders);
    final watched = senders.map(SenderFilter.normalise).toSet();
    return _incoming.stream.where(
      (m) => watched.contains(SenderFilter.normalise(m.sender)),
    );
  }

  /// The cut-offs passed to [release], in order.
  final releases = <DateTime>[];

  @override
  Future<void> release(DateTime before) async => releases.add(before);

  Future<void> close() => _incoming.close();
}
