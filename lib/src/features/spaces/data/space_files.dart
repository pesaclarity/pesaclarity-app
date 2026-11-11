import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../data/database/connection.dart';

/// The files a space lives in on this phone.
abstract interface class SpaceFiles {
  /// Where locked copies kept for 30 days go.
  Future<Directory> keptDirectory();

  /// Removes [spaceId]'s database file and its sidecars.
  Future<void> deleteDatabase(String spaceId);

  /// Removes every file and secret the app keeps on this phone.
  Future<void> eraseEverything();
}

class DeviceSpaceFiles implements SpaceFiles {
  const DeviceSpaceFiles();

  @override
  Future<Directory> keptDirectory() async {
    final dir = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'kept'),
    );
    return dir.create(recursive: true);
  }

  @override
  Future<void> deleteDatabase(String spaceId) async {
    final file = await databaseFile(spaceId);
    for (final suffix in const ['', '-journal', '-wal', '-shm']) {
      final f = File('${file.path}$suffix');
      if (f.existsSync()) await f.delete();
    }
  }

  @override
  Future<void> eraseEverything() async {
    for (final dir in [
      await getApplicationSupportDirectory(),
      await getApplicationDocumentsDirectory(),
      await getTemporaryDirectory(),
    ]) {
      if (!dir.existsSync()) continue;
      for (final entry in dir.listSync()) {
        await entry.delete(recursive: true);
      }
    }
    // The database key goes too, so nothing left behind can be opened.
    await const FlutterSecureStorage().deleteAll();
  }
}

final spaceFilesProvider = Provider<SpaceFiles>(
  (ref) => const DeviceSpaceFiles(),
);

/// Closes the app after everything is deleted; it opens again at setup.
abstract interface class AppRestarter {
  Future<void> restart();
}

class ClosingAppRestarter implements AppRestarter {
  const ClosingAppRestarter();

  @override
  Future<void> restart() => SystemNavigator.pop();
}

final appRestarterProvider = Provider<AppRestarter>(
  (ref) => const ClosingAppRestarter(),
);
