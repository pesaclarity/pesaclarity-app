/// What the person wants reminding about, and when.
class ReminderSettings {
  const ReminderSettings({
    this.enabled = false,
    this.bills = true,
    this.cardCharges = true,
    this.payday = true,
    this.dailySafeToSpend = false,
    this.dailyMinuteOfDay = 8 * 60,
    this.leadDays = 1,
  });

  /// Reads settings saved by [toJson]; unknown or missing values fall back to
  /// the defaults.
  factory ReminderSettings.fromJson(Map<String, Object?> json) {
    const defaults = ReminderSettings();
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key]! as bool : fallback;
    int number(String key, int fallback, {required int max}) {
      final value = json[key];
      return value is int && value >= 0 && value <= max ? value : fallback;
    }

    return ReminderSettings(
      enabled: flag('enabled', defaults.enabled),
      bills: flag('bills', defaults.bills),
      cardCharges: flag('cardCharges', defaults.cardCharges),
      payday: flag('payday', defaults.payday),
      dailySafeToSpend: flag('dailySafeToSpend', defaults.dailySafeToSpend),
      dailyMinuteOfDay: number(
        'dailyMinuteOfDay',
        defaults.dailyMinuteOfDay,
        max: 24 * 60 - 1,
      ),
      leadDays: number('leadDays', defaults.leadDays, max: 31),
    );
  }

  /// The lead times offered, in days before the due date.
  static const leadDayChoices = [0, 1, 2, 3, 7];

  /// Hour of day, Nairobi time, for bill, card charge and payday reminders.
  static const dueReminderMinuteOfDay = 9 * 60;

  /// Master switch. Nothing is scheduled while it is off.
  final bool enabled;
  final bool bills;
  final bool cardCharges;
  final bool payday;

  /// A notification each day with what is safe to spend.
  final bool dailySafeToSpend;

  /// When the daily safe-to-spend notification shows, in minutes after
  /// midnight Nairobi time.
  final int dailyMinuteOfDay;

  /// How many days before a bill or card charge to remind.
  final int leadDays;

  ReminderSettings copyWith({
    bool? enabled,
    bool? bills,
    bool? cardCharges,
    bool? payday,
    bool? dailySafeToSpend,
    int? dailyMinuteOfDay,
    int? leadDays,
  }) => ReminderSettings(
    enabled: enabled ?? this.enabled,
    bills: bills ?? this.bills,
    cardCharges: cardCharges ?? this.cardCharges,
    payday: payday ?? this.payday,
    dailySafeToSpend: dailySafeToSpend ?? this.dailySafeToSpend,
    dailyMinuteOfDay: dailyMinuteOfDay ?? this.dailyMinuteOfDay,
    leadDays: leadDays ?? this.leadDays,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'bills': bills,
    'cardCharges': cardCharges,
    'payday': payday,
    'dailySafeToSpend': dailySafeToSpend,
    'dailyMinuteOfDay': dailyMinuteOfDay,
    'leadDays': leadDays,
  };

  @override
  bool operator ==(Object other) =>
      other is ReminderSettings &&
      other.enabled == enabled &&
      other.bills == bills &&
      other.cardCharges == cardCharges &&
      other.payday == payday &&
      other.dailySafeToSpend == dailySafeToSpend &&
      other.dailyMinuteOfDay == dailyMinuteOfDay &&
      other.leadDays == leadDays;

  @override
  int get hashCode => Object.hash(
    enabled,
    bills,
    cardCharges,
    payday,
    dailySafeToSpend,
    dailyMinuteOfDay,
    leadDays,
  );
}

/// How a lead time reads in settings, such as `1 day before`.
String leadDaysLabel(int days) => switch (days) {
  0 => 'On the day',
  1 => '1 day before',
  7 => '1 week before',
  _ => '$days days before',
};
