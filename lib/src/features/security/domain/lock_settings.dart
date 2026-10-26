/// App lock and privacy preferences, kept outside the database so they can be
/// read before it opens.
final class LockSettings {
  const LockSettings({
    this.pinSet = false,
    this.biometricEnabled = false,
    this.lockAfter = defaultLockAfter,
    this.hideBalancesOnOpen = false,
  });

  static const defaultLockAfter = Duration(seconds: 30);

  /// Choices offered for [lockAfter].
  static const lockAfterChoices = [
    Duration.zero,
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  /// Whether an app PIN is set, which turns the lock on.
  final bool pinSet;

  /// Whether fingerprint or another strong biometric can unlock the app.
  final bool biometricEnabled;

  /// How long the app can stay in the background before it locks.
  final Duration lockAfter;

  /// Whether amounts start hidden each time the app opens.
  final bool hideBalancesOnOpen;

  LockSettings copyWith({
    bool? pinSet,
    bool? biometricEnabled,
    Duration? lockAfter,
    bool? hideBalancesOnOpen,
  }) => LockSettings(
    pinSet: pinSet ?? this.pinSet,
    biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    lockAfter: lockAfter ?? this.lockAfter,
    hideBalancesOnOpen: hideBalancesOnOpen ?? this.hideBalancesOnOpen,
  );

  /// The preferences part, as stored. [pinSet] comes from the PIN record.
  Map<String, Object> toJson() => {
    'biometric': biometricEnabled,
    'lockAfterSeconds': lockAfter.inSeconds,
    'hideBalances': hideBalancesOnOpen,
  };

  static LockSettings fromJson(
    Map<String, Object?> json, {
    required bool pinSet,
  }) {
    return LockSettings(
      pinSet: pinSet,
      biometricEnabled: pinSet && json['biometric'] == true,
      lockAfter: switch (json['lockAfterSeconds']) {
        final int seconds when seconds >= 0 => Duration(seconds: seconds),
        _ => defaultLockAfter,
      },
      hideBalancesOnOpen: json['hideBalances'] == true,
    );
  }
}

/// [duration] as a short label, such as `30 seconds` or `Immediately`.
String lockAfterLabel(Duration duration) {
  if (duration == Duration.zero) return 'Immediately';
  if (duration.inMinutes >= 1 && duration.inSeconds % 60 == 0) {
    final m = duration.inMinutes;
    return m == 1 ? '1 minute' : '$m minutes';
  }
  return '${duration.inSeconds} seconds';
}
