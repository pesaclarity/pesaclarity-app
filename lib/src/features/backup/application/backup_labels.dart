import '../data/backup_settings_repository.dart';

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
