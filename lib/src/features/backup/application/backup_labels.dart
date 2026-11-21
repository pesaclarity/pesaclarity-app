import '../../../shared/offline_messages.dart';
import '../data/backup_settings_repository.dart';
import 'backup_service.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "today", "yesterday", "12 Oct" or "12 Oct 2025", relative to [now].
String backupDayLabel(DateTime at, DateTime now) {
  final local = at.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'today';
  if (diff == 1) return 'yesterday';
  final base = '${local.day} ${_months[local.month - 1]}';
  return local.year == now.year ? base : '$base ${local.year}';
}

/// "today, 06:10" and so on.
String backupTimeLabel(DateTime at, DateTime now) {
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${backupDayLabel(at, now)}, ${two(local.hour)}:${two(local.minute)}';
}

/// The Profile summary, such as "Vault + SD card · today", or null before
/// the first successful backup.
String? lastBackupSummary(BackupSettings settings, DateTime now) {
  final at = settings.lastSuccessAt;
  if (at == null) return null;
  final where = [
    for (final id in BackupLocationId.values)
      if (settings.lastSuccessTo.contains(id)) id.shortLabel,
  ].join(' + ');
  final when = backupDayLabel(at, now);
  return where.isEmpty ? 'Backed up $when' : '$where · $when';
}

/// What to say after a backup run: where it went, and what did not.
///
/// A vault that needs a connection is no failure: the other places still
/// have their copy, and the vault gets its own once the phone is online.
String backupRunMessage(BackupRunReport report) {
  if (report.failed.isEmpty) return 'Backed up.';
  final others = {
    for (final MapEntry(:key, :value) in report.failed.entries)
      if (!(key == BackupLocationId.vault && report.offline.contains(key)))
        key: value,
  };
  if (others.isEmpty) {
    if (report.succeeded.isEmpty) return OfflineMessages.vaultOnly;
    final places = [
      for (final id in BackupLocationId.values)
        if (report.succeeded.contains(id)) id.shortLabel,
    ];
    return OfflineMessages.backedUpExceptVault(_list(places));
  }
  final problems = [
    for (final MapEntry(:key, :value) in report.failed.entries)
      '${key.label}: $value',
  ].join('\n');
  return report.succeeded.isEmpty ? problems : 'Backed up, except:\n$problems';
}

/// "SD card", "Drive and SD card".
String _list(List<String> items) => items.length < 2
    ? items.join()
    : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
