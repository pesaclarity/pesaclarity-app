import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pesaclarity/src/features/backup/data/backup_location.dart';
import 'package:pesaclarity/src/features/backup/data/backup_settings_repository.dart';
import 'package:pesaclarity/src/features/backup/data/backup_sharing.dart';
import 'package:pesaclarity/src/features/backup/data/document_storage.dart';
import 'package:pesaclarity/src/features/backup/data/local_database_backup.dart';

const fakeSnapshotKey =
    'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899';

/// Snapshots a fixed byte string and records what a restore would install.
class FakeLocalDataStore implements LocalDataStore {
  FakeLocalDataStore(this.contents);

  List<int> contents;
  int replacements = 0;
  Object? failReplaceWith;

  @override
  Future<DatabaseSnapshot> snapshot(Directory directory) async {
    final file = File(p.join(directory.path, 'snapshot.sqlite'))
      ..writeAsBytesSync(contents);
    return DatabaseSnapshot(
      file: file,
      keyHex: fakeSnapshotKey,
      schemaVersion: 7,
    );
  }

  @override
  Future<void> replaceWith(File staged, String stagedKeyHex) async {
    if (failReplaceWith case final error?) throw error;
    if (stagedKeyHex != fakeSnapshotKey) throw StateError('wrong key');
    contents = staged.readAsBytesSync();
    replacements++;
  }
}

/// A location that keeps files in memory.
class MemoryLocation implements BackupLocation {
  MemoryLocation(this.id, {this.failWith});

  @override
  final BackupLocationId id;
  final String? failWith;
  final files = <String, Uint8List>{};

  @override
  Future<void> upload(File file, String fileName) async {
    if (failWith != null) throw BackupLocationException(failWith!);
    files[fileName] = file.readAsBytesSync();
  }

  @override
  Future<List<BackupEntry>> list() async => [
    for (final name in files.keys)
      BackupEntry(
        id: name,
        name: name,
        createdAt: backupTimeFromName(name)!,
        sizeBytes: files[name]!.length,
      ),
  ];

  @override
  Future<void> download(BackupEntry entry, File destination) =>
      destination.writeAsBytes(files[entry.id]!);
}

/// A folder picker and file store with no platform channel.
class FakeDocumentStorage implements DocumentStorage {
  DeviceFolder? nextFolder = const DeviceFolder(
    uri: 'content://tree/backups',
    name: 'Pesa Clarity',
  );
  final written = <String, Uint8List>{};
  final saved = <String>[];
  int folderPicks = 0;

  @override
  Future<DeviceFolder?> pickFolder() async {
    folderPicks++;
    return nextFolder;
  }

  @override
  Future<bool> canWrite(DeviceFolder folder) async => true;

  @override
  Future<void> writeFile(
    DeviceFolder folder,
    String name,
    File source, {
    String mimeType = 'application/octet-stream',
  }) async => written[name] = source.readAsBytesSync();

  @override
  Future<List<PickedDocument>> listFiles(DeviceFolder folder) async => [
    for (final name in written.keys)
      PickedDocument(uri: 'content://doc/$name', name: name),
  ];

  @override
  Future<PickedDocument?> pickFile() async => null;

  @override
  Future<void> copyToFile(String uri, File destination) =>
      destination.writeAsBytes(written[uri.split('/').last]!);

  @override
  Future<bool> saveAs(File source, String name, {required String mimeType}) {
    saved.add(name);
    return Future.value(true);
  }
}

class FakeFileSharer implements FileSharer {
  final shared = <String>[];

  @override
  Future<void> shareFile(File file, {required String subject, String? text}) {
    shared.add(p.basename(file.path));
    return Future.value();
  }

  @override
  Future<void> shareText(String text, {required String subject}) {
    shared.add(text);
    return Future.value();
  }
}

class FakeDocumentPrinter implements DocumentPrinter {
  int printed = 0;

  @override
  Future<void> printPdf(Uint8List bytes, {required String name}) async =>
      printed++;
}
