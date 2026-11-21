import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/spaces/space.dart';
import '../repositories/app_settings_repository.dart';
import 'app_database.dart';
import 'connection.dart';
import 'database_providers.dart';

/// Where Personal's settings keep the list of spaces on this phone.
const spacesListKey = 'spaces.list';

/// Something asked for a space that is not on this phone's list, such as a
/// business deleted since a rule was made for it.
final class SpaceNotOnPhone implements Exception {
  const SpaceNotOnPhone(this.spaceId);

  final String spaceId;

  @override
  String toString() => 'SpaceNotOnPhone: $spaceId is not on the list';
}

/// The databases of the spaces on this phone, for work that reaches beyond
/// the open one: a move to another space, a backup copy, clearing a space.
///
/// Every such open goes through here, so nothing is ever moved into, and no
/// file is ever made for, a space that is not on the list.
class SpaceDatabases {
  SpaceDatabases(this._ref);

  final Ref _ref;

  /// Every space on this phone, Personal first, as Personal's settings list
  /// them now.
  Future<List<Space>> listed() async => spacesFromJson(
    await DriftAppSettingsRepository(_ref.read(mainDatabaseProvider))
        .readJson(spacesListKey),
  );

  /// [spaceId]'s database, and whether the caller must close it.
  ///
  /// Throws [SpaceNotOnPhone], touching no file, when the space is not on
  /// the list.
  Future<(AppDatabase, bool)> open(String spaceId) async {
    if (spaceId != personalSpaceId &&
        !(await listed()).any((space) => space.id == spaceId)) {
      throw SpaceNotOnPhone(spaceId);
    }
    if (spaceId == _ref.read(activeSpaceIdProvider)) {
      return (_ref.read(appDatabaseProvider), false);
    }
    if (spaceId == personalSpaceId) {
      return (_ref.read(personalDatabaseProvider), false);
    }
    return (
      openEncryptedDatabase(
        _ref.read(databaseKeyStoreProvider),
        beforeOpen: _ref.read(databaseFileLockProvider).waitUntilFree,
        spaceId: spaceId,
      ),
      true,
    );
  }
}

final spaceDatabasesProvider = Provider<SpaceDatabases>(SpaceDatabases.new);
