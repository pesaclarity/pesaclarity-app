import 'privacy_policy.dart';

/// The optional uses of data the person can switch on or off.
enum ConsentKind {
  /// Federated model updates that improve the app. On by default.
  improveApp(defaultValue: true),

  /// Training models that may be licensed. Off unless the person opts in.
  licensedModels(defaultValue: false),

  /// Anonymous crash reports. Off unless the person opts in.
  crashReports(defaultValue: false);

  const ConsentKind({required this.defaultValue});

  final bool defaultValue;
}

/// One switch's value, when it was set and under which policy version.
class ConsentChoice {
  const ConsentChoice({
    required this.value,
    required this.changedAt,
    required this.policyVersion,
  });

  final bool value;
  final DateTime changedAt;
  final PolicyVersion policyVersion;
}

/// What the person has agreed to, kept on the phone.
class ConsentRecord {
  const ConsentRecord({
    this.acceptedVersion,
    this.acceptedAt,
    this.choices = const {},
  });

  /// Reads a record saved by [toJson]. Entries it cannot read are dropped.
  factory ConsentRecord.fromJson(Map<String, Object?> json) {
    PolicyVersion? version(Object? value) {
      if (value is! String) return null;
      try {
        return PolicyVersion.parse(value);
      } on FormatException {
        return null;
      }
    }

    DateTime? time(Object? value) =>
        value is String ? DateTime.tryParse(value)?.toUtc() : null;

    final choices = <ConsentKind, ConsentChoice>{};
    final saved = json['choices'];
    if (saved is Map) {
      for (final kind in ConsentKind.values) {
        final entry = saved[kind.name];
        if (entry is! Map) continue;
        final value = entry['value'];
        final at = time(entry['changedAt']);
        final policy = version(entry['policyVersion']);
        if (value is bool && at != null && policy != null) {
          choices[kind] = ConsentChoice(
            value: value,
            changedAt: at,
            policyVersion: policy,
          );
        }
      }
    }
    final accepted = version(json['acceptedVersion']);
    return ConsentRecord(
      acceptedVersion: accepted,
      acceptedAt: accepted == null ? null : time(json['acceptedAt']),
      choices: Map.unmodifiable(choices),
    );
  }

  /// The policy version last agreed to; null until the person agrees.
  final PolicyVersion? acceptedVersion;
  final DateTime? acceptedAt;
  final Map<ConsentKind, ConsentChoice> choices;

  /// The switch's value, or its default when never set.
  bool valueOf(ConsentKind kind) => choices[kind]?.value ?? kind.defaultValue;

  /// Whether [policy] is newer than the version agreed to, so the person
  /// should see what changed and agree again.
  bool needsReview(PrivacyPolicy policy) {
    final accepted = acceptedVersion;
    return accepted != null && policy.version.isNewerThan(accepted);
  }

  /// Whether a feature may use [kind] now: the switch is on and the person
  /// has not been asked to review a newer policy yet.
  bool allows(ConsentKind kind, PrivacyPolicy policy) =>
      valueOf(kind) && !needsReview(policy);

  /// This record with [kind] set to [value] at [at] under [policyVersion].
  ConsentRecord withChoice(
    ConsentKind kind,
    bool value, {
    required DateTime at,
    required PolicyVersion policyVersion,
  }) => ConsentRecord(
    acceptedVersion: acceptedVersion,
    acceptedAt: acceptedAt,
    choices: Map.unmodifiable({
      ...choices,
      kind: ConsentChoice(
        value: value,
        changedAt: at.toUtc(),
        policyVersion: policyVersion,
      ),
    }),
  );

  /// This record after agreeing to [version] at [at] with [values]; every
  /// switch is stamped with the new version.
  ConsentRecord accept(
    PolicyVersion version, {
    required DateTime at,
    required Map<ConsentKind, bool> values,
  }) => ConsentRecord(
    acceptedVersion: version,
    acceptedAt: at.toUtc(),
    choices: Map.unmodifiable({
      for (final kind in ConsentKind.values)
        kind: ConsentChoice(
          value: values[kind] ?? valueOf(kind),
          changedAt: at.toUtc(),
          policyVersion: version,
        ),
    }),
  );

  Map<String, Object?> toJson() => {
    if (acceptedVersion != null) 'acceptedVersion': '$acceptedVersion',
    if (acceptedAt != null) 'acceptedAt': acceptedAt!.toIso8601String(),
    'choices': {
      for (final MapEntry(key: kind, value: choice) in choices.entries)
        kind.name: {
          'value': choice.value,
          'changedAt': choice.changedAt.toIso8601String(),
          'policyVersion': '${choice.policyVersion}',
        },
    },
  };
}
