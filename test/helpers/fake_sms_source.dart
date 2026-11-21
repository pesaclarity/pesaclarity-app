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
  int accessChecks = 0;
  int permissionRequests = 0;
  int settingsOpened = 0;

  final _incoming = StreamController<SmsMessage>.broadcast();

  /// Delivers [message] as if it just arrived, to watched listeners only.
  void receive(SmsMessage message) {
    inbox.add(message);
    _incoming.add(message);
  }

  @override
  Future<SmsAccess> access() async {
    accessChecks++;
    return current;
  }

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

  /// What [release] was asked to let go of, in order.
  final releases = <({Set<String> senders, DateTime since, DateTime before})>[];

  @override
  Future<void> release({
    required Set<String> senders,
    required DateTime since,
    required DateTime before,
  }) async => releases.add((senders: senders, since: since, before: before));

  Future<void> close() => _incoming.close();
}

/// A phone's messages as `SmsChannel.kt` and Flutter's `EventChannel` give
/// them: the inbox keeps every message, and only the latest listener gets
/// new ones, for its own senders (a new `listen` replaces the receiver and
/// the channel's handler). For tests that switch between spaces.
class PhoneInbox implements SmsSource {
  final inbox = <SmsMessage>[];
  final listenedSenders = <Set<String>>[];
  final releases = <({Set<String> senders, DateTime since, DateTime before})>[];
  StreamController<SmsMessage>? _listener;
  Set<String> _watched = const {};

  /// A message arrives on the phone.
  void receive(SmsMessage message) {
    inbox.add(message);
    final listener = _listener;
    if (listener != null &&
        !listener.isClosed &&
        _watched.contains(SenderFilter.normalise(message.sender))) {
      listener.add(message);
    }
  }

  @override
  Future<SmsAccess> access() async => SmsAccess.granted;

  @override
  Future<SmsAccess> requestAccess() async => SmsAccess.granted;

  @override
  Future<void> openSettings() async {}

  @override
  Future<List<SmsMessage>> readInbox({
    required Set<String> senders,
    required DateTime since,
  }) async {
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
    // The earlier listener simply hears nothing more.
    _listener = StreamController<SmsMessage>();
    _watched = senders.map(SenderFilter.normalise).toSet();
    return _listener!.stream;
  }

  @override
  Future<void> release({
    required Set<String> senders,
    required DateTime since,
    required DateTime before,
  }) async => releases.add((senders: senders, since: since, before: before));

  Future<void> close() async => _listener?.close();
}

/// The iPhone's message queue as `MessageQueue.swift` and
/// `MessagesChannel.swift` keep it: one list for the whole app, which the
/// Shortcuts automation appends to; `readInbox` filters it by sender and
/// time, and `release` drops what a scan read, by sender and time.
class ShortcutQueue implements SmsSource {
  final queue = <SmsMessage>[];

  /// The senders of the messages each [release] dropped.
  final released = <String>[];
  StreamController<SmsMessage>? _listener;
  Set<String> _watched = const {};

  /// The Shortcuts automation hands a message over.
  void append(SmsMessage message) {
    queue.add(message);
    if (_watched.contains(SenderFilter.normalise(message.sender))) {
      _listener?.add(message);
    }
  }

  @override
  Future<SmsAccess> access() async => SmsAccess.granted;

  @override
  Future<SmsAccess> requestAccess() async => SmsAccess.granted;

  @override
  Future<void> openSettings() async {}

  @override
  Future<List<SmsMessage>> readInbox({
    required Set<String> senders,
    required DateTime since,
  }) async {
    final watched = senders.map(SenderFilter.normalise).toSet();
    return [
      for (final m in queue)
        if (watched.contains(SenderFilter.normalise(m.sender)) &&
            !m.receivedAt.isBefore(since))
          m,
    ]..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
  }

  @override
  Stream<SmsMessage> incoming(Set<String> senders) {
    _listener = StreamController<SmsMessage>();
    _watched = senders.map(SenderFilter.normalise).toSet();
    return _listener!.stream;
  }

  @override
  Future<void> release({
    required Set<String> senders,
    required DateTime since,
    required DateTime before,
  }) async {
    final read = senders.map(SenderFilter.normalise).toSet();
    bool goes(SmsMessage m) =>
        read.contains(SenderFilter.normalise(m.sender)) &&
        !m.receivedAt.isBefore(since) &&
        m.receivedAt.isBefore(before);
    released.addAll([
      for (final m in queue)
        if (goes(m)) m.sender,
    ]);
    queue.removeWhere(goes);
  }

  Future<void> close() async => _listener?.close();
}
