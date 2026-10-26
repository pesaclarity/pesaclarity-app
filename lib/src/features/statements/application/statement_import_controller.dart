import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  failed,
}

@immutable
class StatementImportState {
  const StatementImportState(
    this.stage, {
    this.summary,
    this.bankName,
    this.wrongPassword = false,
  });

  final StatementImportStage stage;

  /// For [StatementImportStage.imported] and
  /// [StatementImportStage.alreadyImported].
  final StatementImportSummary? summary;

  /// For [StatementImportStage.comingSoon].
  final String? bankName;

  /// For [StatementImportStage.password], after a password failed.
  final bool wrongPassword;
}

/// Picks a statement PDF and imports it.
///
/// The file's bytes stay in memory only while a password is asked for. The
/// password itself is handed to the importer and not kept here.
class StatementImportController extends Notifier<StatementImportState> {
  PickedStatement? _pending;

  @override
  StatementImportState build() {
    ref.onDispose(() => _pending = null);
    return const StatementImportState(StatementImportStage.intro);
  }

  /// Opens the file picker, then imports the chosen PDF.
  Future<void> pickAndImport() async {
    final PickedStatement? picked;
    try {
      picked = await ref.read(statementFilePickerProvider).pickPdf();
    } on Object catch (error) {
      if (kDebugMode) debugPrint('Statement pick failed: $error');
      state = const StatementImportState(StatementImportStage.failed);
      return;
    }
    if (picked == null) return;
    _pending = picked;
    await _import();
  }

  /// Tries [password] on the encrypted statement being imported.
  Future<void> submitPassword(String password) => _import(password: password);

  /// Drops the pending file and goes back to the start.
  void startOver() {
    _pending = null;
    state = const StatementImportState(StatementImportStage.intro);
  }

  Future<void> _import({String? password}) async {
    final pending = _pending;
    if (pending == null) return startOver();
    state = const StatementImportState(StatementImportStage.reading);
    try {
      final outcome = await ref
          .read(statementImporterProvider)
          .importPdf(pending.bytes, password: password);
      if (outcome is! StatementNeedsPassword) _pending = null;
      state = switch (outcome) {
        StatementImported(:final summary) => StatementImportState(
          StatementImportStage.imported,
          summary: summary,
        ),
        StatementAlreadyImported(:final summary) => StatementImportState(
          StatementImportStage.alreadyImported,
          summary: summary,
        ),
        StatementNeedsPassword(:final wrongPassword) => StatementImportState(
          StatementImportStage.password,
          wrongPassword: wrongPassword,
        ),
        StatementComingSoon(:final bankName) => StatementImportState(
          StatementImportStage.comingSoon,
          bankName: bankName,
        ),
        StatementNotRead(isPdf: true) => const StatementImportState(
          StatementImportStage.notStatement,
        ),
        StatementNotRead(isPdf: false) => const StatementImportState(
          StatementImportStage.notPdf,
        ),
      };
    } on Object catch (error) {
      // The error type only; a message could carry statement text.
      if (kDebugMode) {
        debugPrint('Statement import failed: ${error.runtimeType}');
      }
      _pending = null;
      state = const StatementImportState(StatementImportStage.failed);
    }
  }
}

final statementImportControllerProvider =
    NotifierProvider.autoDispose<
      StatementImportController,
      StatementImportState
    >(StatementImportController.new);
