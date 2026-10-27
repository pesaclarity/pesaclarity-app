import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A statement file the person picked, held in memory.
@immutable
class PickedStatement {
  const PickedStatement({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Opens the system file picker for PDFs.
abstract interface class StatementFilePicker {
  /// The picked PDFs, in the order picked; empty if the person backed out.
  Future<List<PickedStatement>> pickPdfs();
}

/// Uses Android's document picker through file_selector.
class SystemStatementFilePicker implements StatementFilePicker {
  static const _pdf = XTypeGroup(
    label: 'PDF',
    extensions: ['pdf'],
    mimeTypes: ['application/pdf'],
    uniformTypeIdentifiers: ['com.adobe.pdf'],
  );

  @override
  Future<List<PickedStatement>> pickPdfs() async {
    final files = await openFiles(acceptedTypeGroups: const [_pdf]);
    final picked = <PickedStatement>[];
    for (final file in files) {
      try {
        picked.add(
          PickedStatement(name: file.name, bytes: await file.readAsBytes()),
        );
      } finally {
        await _deleteCachedCopy(file.path);
      }
    }
    return picked;
  }

  // The Android picker copies the document into the app's cache, in a
  // folder of its own; the statement is read into memory, so remove it.
  Future<void> _deleteCachedCopy(String path) async {
    if (path.isEmpty) return;
    try {
      final cache = (await getTemporaryDirectory()).path;
      if (!p.isWithin(cache, path)) return;
      final folder = File(path).parent;
      if (p.equals(folder.path, cache)) {
        await File(path).delete();
      } else {
        await folder.delete(recursive: true);
      }
    } on Object catch (error) {
      if (kDebugMode) debugPrint('Could not remove picked copy: $error');
    }
  }
}

final statementFilePickerProvider = Provider<StatementFilePicker>(
  (ref) => SystemStatementFilePicker(),
);
