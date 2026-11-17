/// What the app keeps between launches about app status, in the encrypted
/// database: the last verified response, when it was fetched, and which
/// notices were closed or have asked for a re-read.
class AppStatusMemo {
  const AppStatusMemo({
    this.envelope,
    this.fetchedAt,
    this.fetchedFor,
    this.issuedAt,
    this.dismissed = const {},
    this.reread = const {},
  });

  static const settingsKey = 'app_status';

  /// The last signed response that verified, as the server sent it.
  final Map<String, Object?>? envelope;
  final DateTime? fetchedAt;

  /// The app version that fetch was for. A new version asks again.
  final String? fetchedFor;

  /// When the newest accepted response was issued. Older ones are refused.
  final DateTime? issuedAt;

  /// [AppNotice.dismissKey]s of closed cards.
  final Set<String> dismissed;

  /// Ids of notices whose re-read was accepted.
  final Set<String> reread;

  AppStatusMemo copyWith({
    Map<String, Object?>? envelope,
    bool clearEnvelope = false,
    DateTime? fetchedAt,
    String? fetchedFor,
    DateTime? issuedAt,
    Set<String>? dismissed,
    Set<String>? reread,
  }) => AppStatusMemo(
    envelope: clearEnvelope ? null : envelope ?? this.envelope,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    fetchedFor: fetchedFor ?? this.fetchedFor,
    issuedAt: issuedAt ?? this.issuedAt,
    dismissed: dismissed ?? this.dismissed,
    reread: reread ?? this.reread,
  );

  static AppStatusMemo fromJson(Map<String, Object?>? json) {
    if (json == null) return const AppStatusMemo();
    DateTime? time(String key) => switch (json[key]) {
      final String text => DateTime.tryParse(text)?.toUtc(),
      _ => null,
    };
    Set<String> strings(String key) => switch (json[key]) {
      final List<Object?> items => {...items.whereType<String>()},
      _ => const {},
    };
    final envelope = json['envelope'];
    return AppStatusMemo(
      envelope: envelope is Map<String, Object?> ? envelope : null,
      fetchedAt: time('fetched_at'),
      fetchedFor: json['fetched_for'] is String
          ? json['fetched_for'] as String
          : null,
      issuedAt: time('issued_at'),
      dismissed: strings('dismissed'),
      reread: strings('reread'),
    );
  }

  Map<String, Object?> toJson() => {
    'envelope': ?envelope,
    'fetched_at': ?fetchedAt?.toUtc().toIso8601String(),
    'fetched_for': ?fetchedFor,
    'issued_at': ?issuedAt?.toUtc().toIso8601String(),
    'dismissed': dismissed.toList()..sort(),
    'reread': reread.toList()..sort(),
  };
}
