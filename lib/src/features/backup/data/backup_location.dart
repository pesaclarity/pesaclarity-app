import 'dart:io';

import 'backup_settings_repository.dart';

/// One backup file at a location, as listed for restore.
final class BackupEntry {
  const BackupEntry({
    required this.id,
    required this.name,
    required this.createdAt,
    this.sizeBytes,
  });

  /// The location's own handle: a vault id, Drive file id or document URI.
  final String id;
  final String name;
  final DateTime createdAt;
  final int? sizeBytes;
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
}

/// A location that is switched on but cannot be reached.
final class BackupLocationException implements Exception {
  const BackupLocationException(this.message);

  final String message;

  @override
  String toString() => 'BackupLocationException: $message';
}

/// The file name every backup is written under, such as
/// `pesaclarity-2026-10-26-0610.pcbackup`.
String backupFileName(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'pesaclarity-${at.year}-${two(at.month)}-${two(at.day)}-'
      '${two(at.hour)}${two(at.minute)}.pcbackup';
}

/// Reads the time back out of a name made by [backupFileName].
DateTime? backupTimeFromName(String name) {
  final match = RegExp(r'pesaclarity-(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})')
      .firstMatch(name);
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 5; i++) int.parse(match.group(i)!)];
  return DateTime(parts[0], parts[1], parts[2], parts[3], parts[4]);
}
