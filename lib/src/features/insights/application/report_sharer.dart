import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a finished report to the phone's share sheet.
abstract interface class ReportSharer {
  Future<void> sharePdf(
    Uint8List bytes, {
    required String fileName,
    required String subject,
  });

  /// Any other file, such as a CSV, of [mimeType].
  Future<void> shareFile(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    required String subject,
  });

  /// Several files in one share.
  Future<void> shareFiles(List<SharedFile> files, {required String subject});
}

/// A file to share: its bytes, name and type.
typedef SharedFile = ({Uint8List bytes, String fileName, String mimeType});

/// Writes the PDF to the app's cache, then opens Android's share sheet.
class SharePlusReportSharer implements ReportSharer {
  const SharePlusReportSharer();

  @override
  Future<void> sharePdf(
    Uint8List bytes, {
    required String fileName,
    required String subject,
  }) => shareFile(
    bytes,
    fileName: fileName,
    mimeType: 'application/pdf',
    subject: subject,
  );

  @override
  Future<void> shareFile(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    required String subject,
  }) => shareFiles([
    (bytes: bytes, fileName: fileName, mimeType: mimeType),
  ], subject: subject);

  @override
  Future<void> shareFiles(
    List<SharedFile> files, {
    required String subject,
  }) async {
    final dir = await getTemporaryDirectory();
    final out = <XFile>[];
    for (final f in files) {
      final file = File(p.join(dir.path, f.fileName));
      await file.writeAsBytes(f.bytes, flush: true);
      out.add(XFile(file.path, mimeType: f.mimeType));
    }
    await SharePlus.instance.share(ShareParams(files: out, subject: subject));
  }
}

final reportSharerProvider = Provider<ReportSharer>(
  (ref) => const SharePlusReportSharer(),
);
