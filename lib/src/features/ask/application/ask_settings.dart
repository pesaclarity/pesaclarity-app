import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/app_settings_repository.dart';

/// How long saved conversations stay.
enum AskKeepFor {
  untilDeleted(null),
  year(Duration(days: 365)),
  days90(Duration(days: 90)),
  days30(Duration(days: 30)),
  days7(Duration(days: 7));

  const AskKeepFor(this.duration);

  /// Null keeps them until the person deletes them.
  final Duration? duration;
}

/// Ask's settings for one space, kept in that space's app settings.
class AskSettings {
  const AskSettings({
    this.show = true,
    this.save = true,
    this.keepFor = AskKeepFor.untilDeleted,
    this.charts = true,
  });

  factory AskSettings.fromJson(Map<String, Object?>? json) => AskSettings(
    show: json?['show'] as bool? ?? true,
    save: json?['save'] as bool? ?? true,
    keepFor:
        AskKeepFor.values.asNameMap()[json?['keepFor']] ??
        AskKeepFor.untilDeleted,
    charts: json?['charts'] as bool? ?? true,
  );

  /// The settings key in the space's app settings.
  static const key = 'ask.settings';

  /// The Ask button on Home.
  final bool show;

  /// Whether conversations are kept on this phone at all.
  final bool save;
  final AskKeepFor keepFor;

  /// Bar charts and split bars in answers.
  final bool charts;

  AskSettings copyWith({
    bool? show,
    bool? save,
    AskKeepFor? keepFor,
    bool? charts,
  }) => AskSettings(
    show: show ?? this.show,
    save: save ?? this.save,
    keepFor: keepFor ?? this.keepFor,
    charts: charts ?? this.charts,
  );

  Map<String, Object?> toJson() => {
    'show': show,
    'save': save,
    'keepFor': keepFor.name,
    'charts': charts,
  };
}

class AskSettingsController extends AsyncNotifier<AskSettings> {
  @override
  Future<AskSettings> build() async => AskSettings.fromJson(
    await ref.watch(appSettingsRepositoryProvider).readJson(AskSettings.key),
  );

  Future<void> save(AskSettings settings) async {
    // Let the first read finish so it cannot overwrite this.
    await future;
    state = AsyncData(settings);
    await ref
        .read(appSettingsRepositoryProvider)
        .writeJson(AskSettings.key, settings.toJson());
  }
}

/// Ask's settings in the open space.
final askSettingsProvider =
    AsyncNotifierProvider<AskSettingsController, AskSettings>(
      AskSettingsController.new,
    );
