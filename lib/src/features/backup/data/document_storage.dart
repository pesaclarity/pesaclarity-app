import 'dart:io';

import 'package:flutter/services.dart';

import 'backup_location.dart';
import 'backup_settings_repository.dart';

/// A document the user picked or the app listed through the system picker.
final class PickedDocument {
  const PickedDocument({
    required this.uri,
    required this.name,
    this.sizeBytes,
    this.modifiedAt,
  });

  final String uri;
  final String name;
  final int? sizeBytes;
  final DateTime? modifiedAt;
}

/// The Android Storage Access Framework: folders and files the user chooses
/// in the system picker, on the phone, an SD card or any document provider.
///
/// Needs no storage permission; access is granted per folder or file.
abstract interface class DocumentStorage {
  /// Asks the user for a folder and keeps access to it across restarts.
  Future<DeviceFolder?> pickFolder();

  /// Whether access to [folder] is still held.
  Future<bool> canWrite(DeviceFolder folder);

  /// Copies [source] into [folder] as [name].
  Future<void> writeFile(
    DeviceFolder folder,
    String name,
    File source, {
    String mimeType,
  });

  Future<List<PickedDocument>> listFiles(DeviceFolder folder);

  /// Asks the user for one file to open.
  Future<PickedDocument?> pickFile();

  /// Copies the document at [uri] into [destination].
  Future<void> copyToFile(String uri, File destination);

  /// Opens the system "save as" screen for [source], suggesting [name].
  ///
  /// Returns false if the user backs out.
  Future<bool> saveAs(File source, String name, {required String mimeType});
}

/// [DocumentStorage] over the `com.pesaclarity.app/documents` channel.
class MethodChannelDocumentStorage implements DocumentStorage {
  const MethodChannelDocumentStorage();

  static const _channel = MethodChannel('com.pesaclarity.app/documents');

  @override
  Future<DeviceFolder?> pickFolder() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'pickFolder',
    );
    if (result == null) return null;
    return DeviceFolder(
      uri: result['uri']! as String,
      name: result['name'] as String? ?? 'Chosen folder',
    );
  }

  @override
  Future<bool> canWrite(DeviceFolder folder) async =>
      await _channel.invokeMethod<bool>('canWrite', {'uri': folder.uri}) ??
      false;

  @override
  Future<void> writeFile(
    DeviceFolder folder,
    String name,
    File source, {
    String mimeType = 'application/octet-stream',
  }) => _guard(
    () => _channel.invokeMethod<void>('writeFile', {
      'treeUri': folder.uri,
      'name': name,
      'mimeType': mimeType,
      'source': source.path,
    }),
  );

  @override
  Future<List<PickedDocument>> listFiles(DeviceFolder folder) async {
    final rows = await _guard(
      () => _channel.invokeListMethod<Map<Object?, Object?>>('listFiles', {
        'treeUri': folder.uri,
      }),
    );
    return [
      for (final row in rows ?? const <Map<Object?, Object?>>[]) _document(row),
    ];
  }

  @override
  Future<PickedDocument?> pickFile() async {
    final row = await _channel.invokeMethod<Map<Object?, Object?>>('pickFile');
    return row == null ? null : _document(row);
  }

  @override
  Future<void> copyToFile(String uri, File destination) => _guard(
    () => _channel.invokeMethod<void>('copyToFile', {
      'uri': uri,
      'destination': destination.path,
    }),
  );

  @override
  Future<bool> saveAs(
    File source,
    String name, {
    required String mimeType,
  }) async {
    final saved = await _guard<bool?>(
      () => _channel.invokeMethod<bool>('saveAs', {
        'name': name,
        'mimeType': mimeType,
        'source': source.path,
      }),
    );
    return saved ?? false;
  }

  static PickedDocument _document(Map<Object?, Object?> row) {
    final modified = row['modifiedMillis'] as int?;
    return PickedDocument(
      uri: row['uri']! as String,
      name: row['name'] as String? ?? '',
      sizeBytes: row['size'] as int?,
      modifiedAt: modified == null || modified <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(modified),
    );
  }

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      throw BackupLocationException(
        e.code == 'no_access'
            ? 'Pesa Clarity no longer has access to that folder. Choose it again.'
            : 'The phone could not read or write the file.',
      );
    }
  }
}

/// Backups as `.pcbackup` files in a folder the user chose.
class DeviceFolderLocation implements BackupLocation {
  DeviceFolderLocation(this._storage, this.folder);

  final DocumentStorage _storage;
  final DeviceFolder folder;

  @override
  BackupLocationId get id => BackupLocationId.deviceFolder;

  @override
  Future<void> upload(File file, String fileName) =>
      _storage.writeFile(folder, fileName, file);

  @override
  Future<List<BackupEntry>> list() async {
    final files = await _storage.listFiles(folder);
    final entries = [
      for (final doc in files)
        if (doc.name.endsWith('.pcbackup'))
          BackupEntry(
            id: doc.uri,
            name: doc.name,
            createdAt:
                backupTimeFromName(doc.name) ??
                doc.modifiedAt ??
                DateTime.fromMillisecondsSinceEpoch(0),
            sizeBytes: doc.sizeBytes,
          ),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  @override
  Future<void> download(BackupEntry entry, File destination) =>
      _storage.copyToFile(entry.id, destination);
}
