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

  /// Reports the person chose to send that could not go yet (offline),
  /// at most [maxPending]. They go without asking again.
  Future<List<CrashReport>> readToSend();

  /// Replaces the reports waiting to be sent with [reports].
  Future<void> keepToSend(List<CrashReport> reports);
}

/// A small file in the app's support directory, outside every space's
/// database and so outside backups.
class FilePendingCrashStore implements PendingCrashStore {
  const FilePendingCrashStore();

  static const fileName = 'pending-crash-reports';

  /// The reports the person chose to send, waiting for a connection.
  static const toSendFileName = 'crash-reports-to-send';

  Future<File> _file([String name = fileName]) async =>
      File(p.join((await getApplicationSupportDirectory()).path, name));

  @override
  Future<List<CrashReport>> read() => _read(fileName);

  @override
  Future<void> add(CrashReport report) async {
    final pending = await read();
    if (pending.length >= PendingCrashStore.maxPending) return;
    await _write(fileName, [...pending, report]);
  }

  @override
  Future<void> clear() => _delete(fileName);

  @override
  Future<List<CrashReport>> readToSend() => _read(toSendFileName);

  @override
  Future<void> keepToSend(List<CrashReport> reports) => reports.isEmpty
      ? _delete(toSendFileName)
      : _write(
          toSendFileName,
          reports.take(PendingCrashStore.maxPending).toList(),
        );

  Future<List<CrashReport>> _read(String name) async {
    try {
      final file = await _file(name);
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

  Future<void> _write(String name, List<CrashReport> reports) async {
    final file = await _file(name);
    await file.writeAsString(
      jsonEncode([for (final r in reports) r.toJson()]),
      flush: true,
    );
  }

  Future<void> _delete(String name) async {
    try {
      final file = await _file(name);
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

  /// The reports waiting to be sent.
  final toSend = <CrashReport>[];

  @override
  Future<List<CrashReport>> readToSend() async => List.of(toSend);

  @override
  Future<void> keepToSend(List<CrashReport> reports) async => toSend
    ..clear()
    ..addAll(reports.take(PendingCrashStore.maxPending));
}

final pendingCrashStoreProvider = Provider<PendingCrashStore>(
  (ref) => const FilePendingCrashStore(),
);
