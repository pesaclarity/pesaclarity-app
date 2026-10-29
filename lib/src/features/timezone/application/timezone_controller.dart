import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/app_settings_repository.dart';
import '../../../domain/time/calendar.dart';

/// Predefined common timezones for user selection.
class TimeZoneOption {
  const TimeZoneOption({
    required this.name,
    required this.label,
    required this.offsetMinutes,
  });

  final String name;
  final String label;
  final int offsetMinutes;

  Duration get offset => Duration(minutes: offsetMinutes);
}

const commonTimeZones = <TimeZoneOption>[
  TimeZoneOption(
    name: 'EAT',
    label: 'East Africa Time (Nairobi, Kampala, Dar es Salaam)',
    offsetMinutes: 180,
  ),
  TimeZoneOption(
    name: 'CAT',
    label: 'Central Africa Time (Kigali, Harare, Lusaka, Maputo)',
    offsetMinutes: 120,
  ),
  TimeZoneOption(
    name: 'WAT',
    label: 'West Africa Time (Lagos, Kinshasa, Luanda, Yaoundé)',
    offsetMinutes: 60,
  ),
  TimeZoneOption(
    name: 'GMT',
    label: 'Greenwich Mean Time (Accra, Dakar, London)',
    offsetMinutes: 0,
  ),
  TimeZoneOption(
    name: 'CET',
    label: 'Central European Time (Paris, Berlin, Rome)',
    offsetMinutes: 60,
  ),
  TimeZoneOption(
    name: 'SAST',
    label: 'South Africa Standard Time (Johannesburg, Cape Town)',
    offsetMinutes: 120,
  ),
  TimeZoneOption(
    name: 'GST',
    label: 'Gulf Standard Time (Dubai, Abu Dhabi, Muscat)',
    offsetMinutes: 240,
  ),
  TimeZoneOption(
    name: 'IST',
    label: 'India Standard Time (New Delhi, Mumbai)',
    offsetMinutes: 330,
  ),
  TimeZoneOption(
    name: 'EST',
    label: 'Eastern Time (New York, Toronto)',
    offsetMinutes: -300,
  ),
  TimeZoneOption(
    name: 'CST',
    label: 'Central Time (Chicago, Mexico City)',
    offsetMinutes: -360,
  ),
  TimeZoneOption(
    name: 'PST',
    label: 'Pacific Time (Los Angeles, Vancouver)',
    offsetMinutes: -480,
  ),
];

@immutable
class TimeZoneSettings {
  const TimeZoneSettings({
    required this.offsetMinutes,
    this.name,
    this.isAuto = true,
  });

  factory TimeZoneSettings.fromJson(Map<String, Object?> json) {
    return TimeZoneSettings(
      offsetMinutes:
          json['offsetMinutes'] as int? ??
          DateTime.now().timeZoneOffset.inMinutes,
      name: json['name'] as String?,
      isAuto: json['isAuto'] as bool? ?? true,
    );
  }

  final int offsetMinutes;
  final String? name;
  final bool isAuto;

  Duration get offset => Duration(minutes: offsetMinutes);

  String get displayName {
    final formatted = UserTimeZone.formatOffset(offset);
    if (isAuto) {
      return name != null && name!.isNotEmpty
          ? '$name ($formatted) · Device location'
          : '$formatted · Device location';
    }
    return name != null && name!.isNotEmpty ? '$name ($formatted)' : formatted;
  }

  Map<String, Object?> toJson() => {
    'offsetMinutes': offsetMinutes,
    'name': name,
    'isAuto': isAuto,
  };
}

/// Controller managing the user's location-based or manually selected timezone.
/// Persists the active timezone in the local SQLite db (`app_settings`).
class TimeZoneController extends AsyncNotifier<TimeZoneSettings> {
  static const settingsKey = 'timezone.settings';

  AppSettingsRepository get _settings =>
      ref.read(appSettingsRepositoryProvider);

  @override
  Future<TimeZoneSettings> build() async {
    final saved = await _settings.readJson(settingsKey);
    final TimeZoneSettings settings;
    if (saved != null) {
      settings = TimeZoneSettings.fromJson(saved);
    } else {
      // Default to device local timezone based on user's location
      final now = DateTime.now();
      settings = TimeZoneSettings(
        offsetMinutes: now.timeZoneOffset.inMinutes,
        name: now.timeZoneName,
      );
      await _settings.writeJson(settingsKey, settings.toJson());
    }

    UserTimeZone.set(settings.offset, name: settings.name);
    return settings;
  }

  Future<void> setTimeZone(
    Duration offset, {
    String? name,
    bool isAuto = false,
  }) async {
    final updated = TimeZoneSettings(
      offsetMinutes: offset.inMinutes,
      name: name,
      isAuto: isAuto,
    );
    UserTimeZone.set(offset, name: name);
    state = AsyncData(updated);
    await _settings.writeJson(settingsKey, updated.toJson());
  }

  Future<void> useDeviceLocation() async {
    final now = DateTime.now();
    await setTimeZone(now.timeZoneOffset, name: now.timeZoneName, isAuto: true);
  }
}

final timeZoneControllerProvider =
    AsyncNotifierProvider<TimeZoneController, TimeZoneSettings>(
      TimeZoneController.new,
    );

final userTimeZoneProvider = Provider<TimeZoneSettings>((ref) {
  return ref.watch(timeZoneControllerProvider).value ??
      TimeZoneSettings(
        offsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
        name: DateTime.now().timeZoneName,
      );
});
