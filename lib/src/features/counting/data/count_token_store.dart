import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/count_token.dart';

/// Where the counting token lives: outside every space's database, so it is
/// never in a backup and a restored phone does not reuse it.
abstract interface class CountTokenStore {
  Future<CountToken?> read();

  Future<void> write(CountToken token);

  Future<void> delete();
}

/// A small file in the app's support directory, beside the open-space
/// files. Android's backups are off for the app, and the vault backs up the
/// spaces' databases only.
class FileCountTokenStore implements CountTokenStore {
  const FileCountTokenStore();

  static const fileName = 'count-token';

  Future<File> _file() async =>
      File(p.join((await getApplicationSupportDirectory()).path, fileName));

  @override
  Future<CountToken?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return CountToken.fromJson(jsonDecode(await file.readAsString()));
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(CountToken token) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(token.toJson()), flush: true);
  }

  @override
  Future<void> delete() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}

/// [CountTokenStore] in memory, for tests.
class MemoryCountTokenStore implements CountTokenStore {
  CountToken? token;

  @override
  Future<CountToken?> read() async => token;

  @override
  Future<void> write(CountToken token) async => this.token = token;

  @override
  Future<void> delete() async => token = null;
}

final countTokenStoreProvider = Provider<CountTokenStore>(
  (ref) => const FileCountTokenStore(),
);
