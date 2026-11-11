import 'dart:io';

import '../../../domain/spaces/space.dart';
import 'backup_settings_repository.dart';

/// One backup file at a location, as listed for restore.
final class BackupEntry {
  const BackupEntry({
    required this.id,
    required this.name,
    required this.createdAt,
    this.sizeBytes,
    this.space = personalSpaceId,
  });

  /// The location's own handle: a vault id, Drive file id or document URI.
  final String id;
  final String name;
  final DateTime createdAt;
  final int? sizeBytes;

  /// Which space this is a copy of.
  final String space;
}

/// Somewhere encrypted backup files can be stored and fetched back from.
///
/// Every implementation moves opaque `.pcbackup` bytes only; encryption
/// happens before [upload] and after [download].
abstract interface class BackupLocation {
  BackupLocationId get id;

  Future<void> upload(File file, String fileName);

  /// Backups at this location, newest first.
  Future<List<BackupEntry>> list();

  Future<void> download(BackupEntry entry, File destination);

  /// Removes [entry] from this location for good.
  Future<void> delete(BackupEntry entry);
}

/// A location that is switched on but cannot be reached.
final class BackupLocationException implements Exception {
  const BackupLocationException(this.message);

  final String message;

  @override
  String toString() => 'BackupLocationException: $message';
}

/// The file name every backup is written under, such as
/// `pesaclarity-2026-10-26-0610.pcbackup` for Personal, or
/// `pesaclarity-abc123-2026-10-26-0610.pcbackup` for another space.
String backupFileName(DateTime at, [String space = personalSpaceId]) {
  String two(int n) => n.toString().padLeft(2, '0');
  final prefix = space == personalSpaceId ? '' : '$space-';
  return 'pesaclarity-$prefix${at.year}-${two(at.month)}-${two(at.day)}-'
      '${two(at.hour)}${two(at.minute)}.pcbackup';
}

final _backupName = RegExp(
  r'pesaclarity-(?:([a-z0-9]{1,32})-)?(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})'
  r'\.pcbackup',
);

/// Reads the time back out of a name made by [backupFileName].
DateTime? backupTimeFromName(String name) {
  final match = _backupName.firstMatch(name);
  if (match == null) return null;
  final parts = [for (var i = 2; i <= 6; i++) int.parse(match.group(i)!)];
  return DateTime(parts[0], parts[1], parts[2], parts[3], parts[4]);
}

/// Reads the space back out of a name made by [backupFileName]; Personal for
/// names without one, and for any other file.
String backupSpaceFromName(String name) =>
    _backupName.firstMatch(name)?.group(1) ?? personalSpaceId;
