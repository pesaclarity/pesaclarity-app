/// What a business sells, which sets the screens it gets.
enum BusinessSells {
  products(
    'Products',
    'Things you buy and sell: vegetables, clothes, airtime. Keeps stock.',
  ),
  services(
    'Services',
    'Your time or skill: consulting, salon, repairs, transport. No stock.',
  ),
  both(
    'Both',
    'A salon that also sells hair products, a mechanic who sells spare parts.',
  );

  const BusinessSells(this.label, this.hint);

  final String label;
  final String hint;

  /// Whether the business keeps stock.
  bool get keepsStock => this != services;
}

/// How far a business has got with setting up its records.
class BusinessSetup {
  const BusinessSetup({this.sells, this.recordsStartedAt});

  /// Reads saved setup; anything malformed counts as not set.
  factory BusinessSetup.fromJson(Map<String, Object?>? json) {
    final sells = json?['sells'];
    final started = json?['recordsStartedAtMs'];
    return BusinessSetup(
      sells: BusinessSells.values.where((s) => s.name == sells).firstOrNull,
      recordsStartedAt: started is int
          ? DateTime.fromMillisecondsSinceEpoch(started, isUtc: true)
          : null,
    );
  }

  /// Null until the owner answers "What do you sell?".
  final BusinessSells? sells;

  /// When "Start your records" was done; null until then.
  final DateTime? recordsStartedAt;

  bool get isDone => sells != null && recordsStartedAt != null;

  BusinessSetup copyWith({BusinessSells? sells, DateTime? recordsStartedAt}) =>
      BusinessSetup(
        sells: sells ?? this.sells,
        recordsStartedAt: recordsStartedAt ?? this.recordsStartedAt,
      );

  Map<String, Object?> toJson() => {
    if (sells != null) 'sells': sells!.name,
    if (recordsStartedAt != null)
      'recordsStartedAtMs': recordsStartedAt!.millisecondsSinceEpoch,
  };
}
