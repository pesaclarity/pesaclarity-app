import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../data/statement_file_picker.dart';
import 'statement_importer.dart';

/// Where the import screen has got to.
enum StatementImportStage {
  intro,
  reading,
  password,
  imported,
  alreadyImported,
  comingSoon,
  notStatement,
  notPdf,
  noText,
  failed,

  /// Several files were picked; [StatementImportState.results] has each.
  batchDone,
}

/// What happened to one file of a batch. [outcome] is null when the import
/// stopped with an error, and [skipped] when the person skipped it at the
/// password prompt.
@immutable
class StatementFileResult {
  const StatementFileResult(
    this.fileName,
    this.outcome, {
    this.skipped = false,
  });

  final String fileName;
  final StatementImportOutcome? outcome;
  final bool skipped;
}

@immutable
class StatementImportState {
  const StatementImportState(
    this.stage, {
    this.summary,
    this.bankName,
    this.wrongPassword = false,
    this.fileName,
    this.fileNumber = 1,
    this.fileCount = 1,
    this.retryAt,
    this.results = const [],
  });

  final StatementImportStage stage;

  /// For [StatementImportStage.imported] and
  /// [StatementImportStage.alreadyImported].
  final StatementImportSummary? summary;

  /// For [StatementImportStage.comingSoon].
  final String? bankName;

  /// For [StatementImportStage.password], after a typed password failed.
  final bool wrongPassword;

  /// The file being read or asking for a password.
  final String? fileName;

  /// Which file of the batch is being read, from 1, and how many there are.
  final int fileNumber, fileCount;

  /// After too many wrong passwords, when the next try is allowed.
  final DateTime? retryAt;

  /// For [StatementImportStage.batchDone].
  final List<StatementFileResult> results;

  bool get isBatch => fileCount > 1;
}

/// Wrong passwords in a row before the person has to wait.
const passwordTriesBeforeWait = 3;

/// How long to wait after [passwordTriesBeforeWait] wrong passwords.
const passwordWait = Duration(seconds: 30);

/// Picks statement PDFs and imports them one after another.
///
/// Files stay in memory only until they are imported. A password that opens
/// one file is kept in memory for the rest of the same batch, so a person
/// importing several months types it once; it is dropped when the batch
/// ends, is cancelled, or the screen closes. It is never stored.
class StatementImportController extends Notifier<StatementImportState> {
  final _queue = Queue<PickedStatement>();
  final _results = <StatementFileResult>[];
  var _fileCount = 0;
  String? _batchPassword;
  var _wrongTries = 0;
  Timer? _waitTimer;

  @override
  StatementImportState build() {
    ref.onDispose(_forget);
    return const StatementImportState(StatementImportStage.intro);
  }

  /// Opens the file picker, then imports the chosen PDFs.
  Future<void> pickAndImport() async {
    final List<PickedStatement> picked;
    try {
      picked = await ref.read(statementFilePickerProvider).pickPdfs();
    } on Object catch (error) {
      if (kDebugMode) debugPrint('Statement pick failed: $error');
      state = const StatementImportState(StatementImportStage.failed);
      return;
    }
    if (picked.isEmpty) return;
    _forget();
    _queue.addAll(picked);
    _fileCount = picked.length;
    await _importQueue();
  }

  /// Tries [password] on the encrypted statement being imported.
  Future<void> submitPassword(String password) async {
    final retryAt = state.retryAt;
    if (retryAt != null && ref.read(clockProvider)().isBefore(retryAt)) {
      return;
    }
    await _importQueue(typed: password);
  }

  /// Skips the file asking for a password and goes on with the batch.
  Future<void> skipFile() async {
    if (_queue.isEmpty) return startOver();
    _results.add(
      StatementFileResult(_queue.removeFirst().name, null, skipped: true),
    );
    _wrongTries = 0;
    await _importQueue();
  }

  /// Drops every pending file and the batch password, and goes back to the
  /// start.
  void startOver() {
    _forget();
    state = const StatementImportState(StatementImportStage.intro);
  }

  void _forget() {
    _queue.clear();
    _results.clear();
    _fileCount = 0;
    _batchPassword = null;
    _wrongTries = 0;
    _waitTimer?.cancel();
    _waitTimer = null;
  }

  Future<void> _importQueue({String? typed}) async {
    var password = typed;
    while (_queue.isNotEmpty) {
      final file = _queue.first;
      final number = _results.length + 1;
      state = StatementImportState(
        StatementImportStage.reading,
        fileName: file.name,
        fileNumber: number,
        fileCount: _fileCount,
      );
      final StatementImportOutcome? outcome;
      try {
        outcome = await ref
            .read(statementImporterProvider)
            .importPdf(file.bytes, password: password ?? _batchPassword);
      } on Object catch (error) {
        // The error type only; a message could carry statement text.
        if (kDebugMode) {
          debugPrint('Statement import failed: ${error.runtimeType}');
        }
        _queue.removeFirst();
        _results.add(StatementFileResult(file.name, null));
        password = null;
        continue;
      }

      if (outcome is StatementNeedsPassword) {
        _askForPassword(file.name, number, typedWrong: password != null);
        return;
      }
      if (password != null) {
        // It opened this file, so try it on the rest of the batch.
        _batchPassword = password;
        password = null;
      }
      _wrongTries = 0;
      _queue.removeFirst();
      _results.add(StatementFileResult(file.name, outcome));
    }
    _finish();
  }

  void _askForPassword(
    String fileName,
    int number, {
    required bool typedWrong,
  }) {
    DateTime? retryAt;
    if (typedWrong) {
      _wrongTries++;
      if (_wrongTries >= passwordTriesBeforeWait) {
        _wrongTries = 0;
        retryAt = ref.read(clockProvider)().add(passwordWait);
        _waitTimer?.cancel();
        _waitTimer = Timer(passwordWait, () {
          if (state.stage == StatementImportStage.password) {
            state = StatementImportState(
              StatementImportStage.password,
              wrongPassword: state.wrongPassword,
              fileName: state.fileName,
              fileNumber: state.fileNumber,
              fileCount: state.fileCount,
            );
          }
        });
      }
    }
    state = StatementImportState(
      StatementImportStage.password,
      wrongPassword: typedWrong,
      fileName: fileName,
      fileNumber: number,
      fileCount: _fileCount,
      retryAt: retryAt,
    );
  }

  void _finish() {
    final results = List<StatementFileResult>.unmodifiable(_results);
    final count = _fileCount;
    _forget();
    if (count > 1) {
      state = StatementImportState(
        StatementImportStage.batchDone,
        fileCount: count,
        results: results,
      );
      return;
    }
    state = stateFor(results.single.outcome);
  }

  /// The screen state for a single file's [outcome]; null means it failed.
  static StatementImportState stateFor(StatementImportOutcome? outcome) =>
      switch (outcome) {
        null => const StatementImportState(StatementImportStage.failed),
        StatementImported(:final summary) => StatementImportState(
          StatementImportStage.imported,
          summary: summary,
        ),
        StatementAlreadyImported(:final summary) => StatementImportState(
          StatementImportStage.alreadyImported,
          summary: summary,
        ),
        StatementNeedsPassword() => const StatementImportState(
          StatementImportStage.password,
        ),
        StatementComingSoon(:final bankName) => StatementImportState(
          StatementImportStage.comingSoon,
          bankName: bankName,
        ),
        StatementHasNoText() => const StatementImportState(
          StatementImportStage.noText,
        ),
        StatementNotRead(isPdf: true) => const StatementImportState(
          StatementImportStage.notStatement,
        ),
        StatementNotRead(isPdf: false) => const StatementImportState(
          StatementImportStage.notPdf,
        ),
      };
}

final statementImportControllerProvider =
    NotifierProvider.autoDispose<
      StatementImportController,
      StatementImportState
    >(StatementImportController.new);
