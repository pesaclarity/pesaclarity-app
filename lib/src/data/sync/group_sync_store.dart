import '../repositories/app_settings_repository.dart';
import 'group_sync.dart';

/// Keeps each shared space's pull cursor in that space's own encrypted
/// database (its app settings table), so a restart carries on where the
/// last sync stopped instead of pulling everything again.
class SettingsSyncCursorStore implements SyncCursorStore {
  SettingsSyncCursorStore(this._settings);

  static const key = 'group_sync_cursor';

  final AppSettingsRepository _settings;

  @override
  Future<int> read(String space) async {
    final v = (await _settings.readJson(key))?[space];
    return v is int && v >= 0 ? v : 0;
  }

  @override
  Future<void> write(String space, int cursor) async {
    final all = {...?await _settings.readJson(key)};
    all[space] = cursor;
    await _settings.writeJson(key, all);
  }

  /// Starts the space again from the beginning, after the owner turns sync
  /// off and the server forgets it.
  Future<void> clear(String space) async {
    final all = {...?await _settings.readJson(key)}..remove(space);
    await _settings.writeJson(key, all);
  }
}

/// What this phone knows about sync for the open space. Off until the
/// owner turns it on.
class GroupSyncSettings {
  const GroupSyncSettings({
    this.on = false,
    this.lastSyncAt,
    this.problem,
    this.readOnly = false,
  });

  /// The owner: their switch. A member: whether the owner's space was on
  /// the server at the last sync.
  final bool on;

  /// When this phone last synced, in milliseconds.
  final int? lastSyncAt;

  /// Why the last sync did not finish (a server code, `offline` ...).
  final String? problem;

  /// The owner's Premium has ended: changes come in, none go out.
  final bool readOnly;

  static const key = 'group_sync';

  static Future<GroupSyncSettings> read(AppSettingsRepository s) async {
    final j = await s.readJson(key);
    if (j == null) return const GroupSyncSettings();
    return GroupSyncSettings(
      on: j['on'] == true,
      lastSyncAt: j['lastSyncAt'] is int ? j['lastSyncAt']! as int : null,
      problem: j['problem'] is String ? j['problem']! as String : null,
      readOnly: j['readOnly'] == true,
    );
  }

  Future<void> write(AppSettingsRepository s) => s.writeJson(key, {
    'on': on,
    'lastSyncAt': ?lastSyncAt,
    'problem': ?problem,
    'readOnly': readOnly,
  });

  GroupSyncSettings copyWith({
    bool? on,
    int? lastSyncAt,
    String? problem,
    bool clearProblem = false,
    bool? readOnly,
  }) => GroupSyncSettings(
    on: on ?? this.on,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    problem: clearProblem ? null : (problem ?? this.problem),
    readOnly: readOnly ?? this.readOnly,
  );
}
