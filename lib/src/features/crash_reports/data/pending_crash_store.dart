import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/crash_report.dart';

/// Reports waiting for the next start. Only built reports are kept, never
/// the error or its stack as they were, and at most [maxPending].
abstract interface class PendingCrashStore {
  static const maxPending = 3;

  Future<List<CrashReport>> read();

  /// Adds [report] unless [maxPending] are already waiting.
  Future<void> add(CrashReport report);

  Future<void> clear();
}

/// A small file in the app's support directory, outside every space's
/// database and so outside backups.
class FilePendingCrashStore implements PendingCrashStore {
  const FilePendingCrashStore();

  static const fileName = 'pending-crash-reports';

  Future<File> _file() async =>
      File(p.join((await getApplicationSupportDirectory()).path, fileName));

  @override
  Future<List<CrashReport>> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      final json = jsonDecode(await file.readAsString());
      if (json is! List) return const [];
      return [
        for (final entry in json.take(PendingCrashStore.maxPending))
          ?CrashReport.fromJson(entry),
      ];
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> add(CrashReport report) async {
    final pending = await read();
    if (pending.length >= PendingCrashStore.maxPending) return;
    final file = await _file();
    await file.writeAsString(
      jsonEncode([
        for (final r in [...pending, report]) r.toJson(),
      ]),
      flush: true,
    );
  }

  @override
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}

/// [PendingCrashStore] in memory, for tests.
class MemoryPendingCrashStore implements PendingCrashStore {
  final reports = <CrashReport>[];

  @override
  Future<List<CrashReport>> read() async => List.of(reports);

  @override
  Future<void> add(CrashReport report) async {
    if (reports.length < PendingCrashStore.maxPending) reports.add(report);
  }

  @override
  Future<void> clear() async => reports.clear();
}

final pendingCrashStoreProvider = Provider<PendingCrashStore>(
  (ref) => const FilePendingCrashStore(),
);
